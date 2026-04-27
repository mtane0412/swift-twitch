// BadgeStore.swift
// Twitch バッジ定義の取得・管理サービス
// Twitch Helix API からグローバル・チャンネルバッジ定義をフェッチし、画像URLを解決する

import Foundation

/// バッジ定義の URL マッピング型
/// [バッジ名: [バージョン: 画像URLString]]
typealias BadgeURLMapping = [String: [String: String]]

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

    /// グローバルバッジの TTL（24 時間）
    private static let badgeTTL: TimeInterval = 86400

    // MARK: - 状態

    /// グローバルバッジのURLマッピング
    private var globalBadges: BadgeURLMapping = [:]

    /// チャンネルバッジのURLマッピング
    private var channelBadges: BadgeURLMapping = [:]

    /// グローバルバッジ取得済みフラグ
    private var isGlobalLoaded = false

    /// 進行中のグローバルバッジフェッチタスク（並行重複排除用）
    private var globalBadgesTask: Task<Void, Never>?

    /// Helix API クライアント
    private let apiClient: any HelixAPIClientProtocol

    /// 永続化サービス（seed / write-back に使用）
    private let persistenceService: (any PersistenceService)?

    // MARK: - 初期化

    /// BadgeStore を初期化する
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント（テスト時はモックを注入）
    ///   - persistenceService: 永続化サービス（nil の場合は永続化なし）
    init(apiClient: any HelixAPIClientProtocol, persistenceService: (any PersistenceService)? = nil) {
        self.apiClient = apiClient
        self.persistenceService = persistenceService
    }

    // MARK: - 公開メソッド

    /// 永続化済みグローバルバッジを読み込んでキャッシュを事前充填する
    ///
    /// チャンネル接続時に呼び出す。TTL（24h）以内のデータなら `isGlobalLoaded = true`
    /// にして後続の `fetchGlobalBadges()` による API 呼び出しを抑止する（stale-while-revalidate）。
    /// TTL 超過時は古いデータでキャッシュを充填した上で `isGlobalLoaded = false` のままにし、
    /// 後続の `fetchGlobalBadges()` で再フェッチさせる。
    func seedFromPersistence() async {
        // 既に API フェッチ済みならインメモリデータを上書きしない
        guard !isGlobalLoaded else { return }
        guard let persistence = persistenceService else { return }
        let result = await persistence.loadBadgesWithTimestamp(scope: .global)
        guard !result.snapshots.isEmpty else { return }
        globalBadges = Self.buildMapping(from: result.snapshots)
        if let fetchedAt = result.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.badgeTTL {
            isGlobalLoaded = true
        }
    }

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
            do {
                let response: HelixBadgesResponse = try await self.apiClient.get(
                    url: Self.helixGlobalBadgesURL,
                    queryItems: nil
                )
                self.globalBadges = Self.buildMapping(from: response.data)
                self.isGlobalLoaded = true
                // write-back: 永続化サービスが存在すればバッジを非同期保存する
                self.writeBackBadges(response.data, scope: .global)
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                // 未ログイン時は次回接続時に再取得できるよう isGlobalLoaded を更新しない
            } catch let error as URLError where error.code == .cancelled {
                // タスクキャンセル（アプリ終了・再接続時）は正常系なのでスキップ
                _ = error
            } catch HelixAPIError.unauthorized {
                // Helix API が 401 を返した場合（トークン失効等）は次回接続時に再取得する
            } catch is AuthConfigError {
                // Client ID 未設定（開発環境・テスト実行時）は正常状態のためスキップ
            } catch {
                // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
                assertionFailure("グローバルバッジフェッチ失敗: \(error)")
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
        let scope: BadgeScope = .channel(broadcasterId: channelId)
        // 永続化キャッシュから先読みしてオフライン時の即時表示と API 呼び出し抑止を実現する
        if let persistence = persistenceService {
            let cached = await persistence.loadBadgesWithTimestamp(scope: scope)
            if !cached.snapshots.isEmpty {
                channelBadges = Self.buildMapping(from: cached.snapshots)
                if let fetchedAt = cached.fetchedAt,
                   Date().timeIntervalSince(fetchedAt) < Self.badgeTTL {
                    return
                }
            }
        }
        do {
            let response: HelixBadgesResponse = try await apiClient.get(
                url: Self.helixChannelBadgesURL,
                queryItems: [URLQueryItem(name: "broadcaster_id", value: channelId)]
            )
            channelBadges = Self.buildMapping(from: response.data)
            // write-back: 永続化サービスが存在すればチャンネルスコープで非同期保存する
            writeBackBadges(response.data, scope: scope)
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // 未ログイン時はスキップ
        } catch HelixAPIError.unauthorized {
            // Helix API が 401 を返した場合（トークン失効等）はスキップ
        } catch {
            // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
            assertionFailure("チャンネルバッジフェッチ失敗（channelId: \(channelId)）: \(error)")
        }
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

    // MARK: - プライベートメソッド

    /// バッジを永続化サービスに非同期保存する（fire-and-forget）
    private func writeBackBadges(_ badgeSets: [HelixBadgeSet], scope: BadgeScope) {
        guard let persistence = persistenceService else { return }
        let snapshots = badgeSets.flatMap { Self.badgeVersionSnapshot(from: $0) }
        Task { [persistence] in
            do {
                try await persistence.saveBadges(snapshots, scope: scope)
            } catch {
                #if DEBUG
                print("[BadgeStore] write-back 失敗 scope=\(scope) error=\(error)")
                #endif
            }
        }
    }

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

    /// BadgeVersionSnapshot の配列から URLマッピングを構築する
    ///
    /// 永続化キャッシュから復元する際に使用する。2x URL を採用する。
    ///
    /// - Parameter snapshots: 永続化済みバッジスナップショットの配列
    /// - Returns: [バッジ名: [バージョン: URLString]] のマッピング
    static func buildMapping(from snapshots: [BadgeVersionSnapshot]) -> BadgeURLMapping {
        var mapping: BadgeURLMapping = [:]
        for snapshot in snapshots {
            mapping[snapshot.setId, default: [:]][snapshot.version] = snapshot.imageUrl2x
        }
        return mapping
    }

    /// HelixBadgeSet を BadgeVersionSnapshot の配列に変換する（write-back 用）
    private static func badgeVersionSnapshot(from badgeSet: HelixBadgeSet) -> [BadgeVersionSnapshot] {
        badgeSet.versions.map { version in
            BadgeVersionSnapshot(
                setId: badgeSet.setId,
                version: version.id,
                imageUrl1x: version.imageUrl1x,
                imageUrl2x: version.imageUrl2x,
                imageUrl4x: version.imageUrl4x,
                title: version.title,
                description: version.description
            )
        }
    }
}
