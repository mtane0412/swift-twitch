// FollowedStreamStore.swift
// フォロー中の配信中ストリーム一覧の取得・定期更新サービス
// Twitch Helix API /helix/streams/followed からライブ中のストリームを取得してサイドバーに提供する

import Foundation
import Observation

/// フォロー中の配信中ストリーム一覧を管理するストア
///
/// - `startAutoRefresh()` で60秒ごとの自動更新を開始する
/// - `stopAutoRefresh()` で自動更新を停止する
/// - `refresh()` で手動で即時更新する
/// - ユーザーIDが未設定（未ログイン）の場合はリフレッシュをスキップする
@Observable
@MainActor
final class FollowedStreamStore {

    // MARK: - 定数

    /// 自動更新の間隔（秒）
    private static let refreshInterval: TimeInterval = 60

    /// Helix API エンドポイント
    private static let followedStreamsURL = URL(string: "https://api.twitch.tv/helix/streams/followed")!

    // MARK: - 公開プロパティ

    /// フォロー中の配信中ストリーム一覧（API レスポンス順）
    private(set) var streams: [FollowedStream] = []

    /// データ取得中フラグ
    private(set) var isLoading = false

    /// 最後に発生したエラーメッセージ（正常時は `nil`）
    private(set) var lastError: String?

    // MARK: - プライベートプロパティ

    private let apiClient: any HelixAPIClientProtocol
    private let authState: AuthState?
    /// AuthState を使わずに直接 userId を指定する場合（テスト用）
    private let overrideUserId: String?
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - 初期化

    /// FollowedStreamStore を初期化する（本番用）
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント
    ///   - authState: 認証状態（userId の取得に使用）
    init(apiClient: any HelixAPIClientProtocol, authState: AuthState) {
        self.apiClient = apiClient
        self.authState = authState
        self.overrideUserId = nil
    }

    /// FollowedStreamStore を初期化する（テスト用: userId 直接指定）
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント
    ///   - userId: 対象ユーザーID（nil の場合はリフレッシュをスキップ）
    init(apiClient: any HelixAPIClientProtocol, userId: String?) {
        self.apiClient = apiClient
        self.authState = nil
        self.overrideUserId = userId
    }

    // MARK: - 公開メソッド

    /// 自動更新ループを開始する
    ///
    /// 即時1回フェッチした後、`refreshInterval` 秒ごとに自動更新する
    func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    /// ストリーム一覧をクリアする
    ///
    /// ログアウト時など、データを消去したい場合に使用する
    func clear() {
        streams = []
        lastError = nil
    }

    /// 自動更新ループを停止する
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// ストリーム一覧を即時更新する
    ///
    /// ユーザーIDが未設定の場合はスキップする（サイレント）。
    /// 認証エラーの場合もサイレントスキップ（ログアウト状態での呼び出しを考慮）。
    func refresh() async {
        guard let userId = currentUserId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: HelixFollowedStreamsResponse = try await apiClient.get(
                url: Self.followedStreamsURL,
                queryItems: [URLQueryItem(name: "user_id", value: userId)]
            )
            // ドメインモデルに変換（パース失敗のストリームはスキップ）
            streams = response.data.compactMap { $0.toFollowedStream() }
            lastError = nil
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // 未ログイン時はサイレントスキップ（エラー表示しない）
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - プライベートメソッド

    /// 有効なユーザーIDを取得する
    private var currentUserId: String? {
        overrideUserId ?? authState?.userId
    }
}
