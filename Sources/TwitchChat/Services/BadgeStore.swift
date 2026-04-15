// BadgeStore.swift
// Twitch バッジ定義の取得・管理サービス
// Twitch Helix API からグローバル・チャンネルバッジ定義をフェッチし、画像URLを解決する

import Foundation

/// バッジ定義の URL マッピング型
/// [バッジ名: [バージョン: 画像URLString]]
typealias BadgeURLMapping = [String: [String: String]]

// MARK: - トークンプロバイダープロトコル

/// バッジ Helix API 呼び出しに必要な認証情報を提供するプロトコル
///
/// `BadgeStore`（actor）と `AuthState`（@MainActor クラス）の分離境界を吸収するため、
/// 最小限のインターフェースとして切り出している。テスト時のモック差し替えも容易。
protocol BadgeAPITokenProvider: Sendable {
    /// 現在の有効なアクセストークンを取得する。未ログインまたは取得失敗の場合は `nil`
    func fetchAccessToken() async -> String?

    /// Twitch アプリの Client ID を返す
    ///
    /// - Throws: `AuthConfigError.missingClientID` が未設定の場合
    func clientID() async throws -> String
}

/// バッジ定義の取得・管理を行うサービス
///
/// - グローバルバッジ（broadcaster, moderator, vip 等）は接続時に1回フェッチ
/// - チャンネルバッジ（subscriber 等の独自アート）は room-id 取得後にフェッチ
/// - imageURL(for:) はチャンネルバッジを優先し、なければグローバルにフォールバック
/// - 並行フェッチの重複実行を Task-based deduplication で防止
/// - トークン未設定（未ログイン）の場合はフェッチをスキップする
actor BadgeStore {

    // MARK: - 定数

    /// Helix グローバルバッジエンドポイント
    private static let helixGlobalBadgesURL = URL(string: "https://api.twitch.tv/helix/chat/badges/global")!

    /// Helix チャンネルバッジエンドポイント
    private static let helixChannelBadgesURL = URL(string: "https://api.twitch.tv/helix/chat/badges")!

    /// リクエストのタイムアウト秒数
    private static let requestTimeout: TimeInterval = 10

    // MARK: - 状態

    /// グローバルバッジのURLマッピング
    private var globalBadges: BadgeURLMapping = [:]

    /// チャンネルバッジのURLマッピング
    private var channelBadges: BadgeURLMapping = [:]

    /// グローバルバッジ取得済みフラグ
    private var isGlobalLoaded = false

    /// 進行中のグローバルバッジフェッチタスク（並行重複排除用）
    private var globalBadgesTask: Task<Void, Never>?

    /// 認証情報プロバイダー
    private let tokenProvider: any BadgeAPITokenProvider

    // MARK: - 初期化

    /// BadgeStore を初期化する
    ///
    /// - Parameter tokenProvider: Helix API 認証情報プロバイダー
    init(tokenProvider: any BadgeAPITokenProvider) {
        self.tokenProvider = tokenProvider
    }

    // MARK: - 公開メソッド

    /// グローバルバッジ定義をフェッチする
    ///
    /// 並行して複数回呼ばれた場合でも、ネットワークリクエストは1回のみ実行される。
    /// トークン未設定（未ログイン）の場合はスキップし、次回接続時に再取得できるよう
    /// `isGlobalLoaded` フラグを `true` にしない。
    func fetchGlobalBadges() async {
        guard !isGlobalLoaded else { return }
        // 進行中タスクがあれば完了を待って返す（TOCTOU 防止）
        if let existing = globalBadgesTask {
            await existing.value
            return
        }
        let task = Task {
            if let response = try? await self.fetchHelix(
                url: Self.helixGlobalBadgesURL,
                queryItems: nil
            ) {
                self.globalBadges = Self.buildMapping(from: response.data)
                self.isGlobalLoaded = true
            }
        }
        globalBadgesTask = task
        await task.value
        globalBadgesTask = nil
    }

    /// チャンネルバッジ定義をフェッチする
    ///
    /// - Parameter channelId: Twitch チャンネルID（IRCの room-id タグの値、数字のみ）
    /// トークン未設定（未ログイン）の場合はスキップする。
    func fetchChannelBadges(channelId: String) async {
        // Twitch の room-id は数字のみで構成される（URLパラメータインジェクション対策）
        guard !channelId.isEmpty, channelId.allSatisfy(\.isNumber) else { return }
        guard let response = try? await fetchHelix(
            url: Self.helixChannelBadgesURL,
            queryItems: [URLQueryItem(name: "broadcaster_id", value: channelId)]
        ) else { return }
        channelBadges = Self.buildMapping(from: response.data)
    }

    /// バッジの画像 URL を解決する
    ///
    /// チャンネルバッジを優先し、見つからない場合はグローバルバッジにフォールバックする
    ///
    /// - Parameter badge: IRC から取得した Badge
    /// - Returns: バッジ画像の URL、未登録の場合は nil
    func imageURL(for badge: Badge) -> URL? {
        let urlString = channelBadges[badge.name]?[badge.version]
            ?? globalBadges[badge.name]?[badge.version]
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    /// チャンネルバッジのマッピングをクリアする
    ///
    /// チャンネル切替時（connect 呼び出し前）に呼び出すことで、
    /// 前チャンネルのチャンネルバッジが新チャンネルのメッセージに誤解決されるのを防ぐ
    func resetChannelBadges() {
        channelBadges = [:]
    }

    /// 進行中のグローバルバッジフェッチタスクをキャンセルする
    ///
    /// disconnect 時に呼び出すことで、不要なネットワークリクエストを中断できる
    func cancelGlobalFetch() {
        globalBadgesTask?.cancel()
        globalBadgesTask = nil
    }

    // MARK: - テスト用メソッド

#if DEBUG
    /// グローバルバッジのURLマッピングを直接設定する（テスト用）
    func setGlobalBadges(_ mapping: BadgeURLMapping) {
        globalBadges = mapping
        isGlobalLoaded = true
    }

    /// チャンネルバッジのURLマッピングを直接設定する（テスト用）
    func setChannelBadges(_ mapping: BadgeURLMapping) {
        channelBadges = mapping
    }
#endif

    // MARK: - 静的ユーティリティ

    /// HelixBadgeSet の配列から URLマッピングを構築する
    ///
    /// 画像サイズは 2x（`imageUrl2x`）を使用する。
    /// 現在の表示サイズ 18pt では Retina 対応として 2x 画像が適切。
    ///
    /// - Parameter badgeSets: Helix バッジセットの配列
    /// - Returns: [バッジ名: [バージョン: URLString]] のマッピング
    static func buildMapping(from badgeSets: [HelixBadgeSet]) -> BadgeURLMapping {
        var mapping: BadgeURLMapping = [:]
        for set in badgeSets {
            var versions: [String: String] = [:]
            for version in set.versions {
                versions[version.id] = version.imageUrl2x
            }
            mapping[set.setId] = versions
        }
        return mapping
    }

    // MARK: - プライベートメソッド

    /// Helix API にリクエストを送信して結果をデコードする
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    /// - Returns: デコードされた `HelixBadgesResponse`
    /// - Throws: トークン未設定時は `URLError(.userAuthenticationRequired)`、
    ///           HTTP エラー時は `URLError(.badServerResponse)`
    private func fetchHelix(
        url: URL,
        queryItems: [URLQueryItem]?
    ) async throws -> HelixBadgesResponse {
        // トークンまたは Client ID が取得できない場合はリクエストしない
        guard let token = await tokenProvider.fetchAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        guard let clientId = try? await tokenProvider.clientID() else {
            throw URLError(.userAuthenticationRequired)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems

        guard let safeURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: safeURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(HelixBadgesResponse.self, from: data)
    }
}
