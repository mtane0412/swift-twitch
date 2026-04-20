// BadgeStorePersistenceTests.swift
// BadgeStore の永続化配線テスト（seed / write-back / TTL / scope 分離）

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// API 呼び出し回数を記録する BadgeAPI クライアント
///
/// fetchGlobalBadges の TTL テストで「API が呼ばれたか」を確認するために使用する
actor MockCountingBadgeAPIClient: HelixAPIClientProtocol {

    /// 成功レスポンスとして返すバッジ定義 JSON（nil の場合はサーバーエラーを返す）
    let badgeJSON: String?

    /// `get` が呼ばれた回数
    private(set) var getCallCount = 0

    init(badgeJSON: String? = nil) {
        self.badgeJSON = badgeJSON
    }

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        getCallCount += 1
        if let json = badgeJSON, let data = json.data(using: .utf8) {
            return try JSONDecoder().decode(T.self, from: data)
        }
        // 成功 JSON 未設定の場合は未認証エラーとして返す（assertionFailure を避けるため）
        throw HelixAPIError.unauthorized
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T {
        throw URLError(.badServerResponse)
    }

    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        throw URLError(.badServerResponse)
    }

    func patch<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        throw URLError(.badServerResponse)
    }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        throw URLError(.badServerResponse)
    }
}

// MARK: - テストスイート

/// BadgeStore の永続化配線（seed / write-back / TTL / scope 分離）テスト
@Suite("BadgeStorePersistenceTests")
struct BadgeStorePersistenceTests {

    // MARK: - ヘルパー

    /// テスト用グローバルバッジスナップショット
    private func makeBroadcasterBadge() -> BadgeVersionSnapshot {
        BadgeVersionSnapshot(
            setId: "broadcaster",
            version: "1",
            imageUrl1x: "https://cdn.example.com/broadcaster/1/1x.png",
            imageUrl2x: "https://cdn.example.com/broadcaster/1/2x.png",
            imageUrl4x: "https://cdn.example.com/broadcaster/1/4x.png",
            title: "配信者",
            description: nil
        )
    }

    /// バッジ成功レスポンス JSON（broadcaster バッジ1件）
    private func broadcasterBadgeJSON() -> String {
        let version = """
            {"id":"1","image_url_1x":"https://cdn.example.com/broadcaster/1/1x.png",\
            "image_url_2x":"https://cdn.example.com/broadcaster/1/2x.png",\
            "image_url_4x":"https://cdn.example.com/broadcaster/1/4x.png",\
            "title":"配信者","description":"配信者バッジ"}
            """
        return """
            {"data":[{"set_id":"broadcaster","versions":[\(version)]}]}
            """
    }

    // MARK: - seed 正常系

    @Test("永続化済みグローバルバッジからseedすると画像URLを解決できる")
    func 永続化済みグローバルバッジからseedすると画像URLを解決できる() async {
        // 前提: InMemoryPersistenceService にグローバルバッジを事前保存する
        let persistence = InMemoryPersistenceService()
        let badge = makeBroadcasterBadge()
        try? await persistence.saveBadges([badge], scope: .global)

        // 操作: 永続化サービスを持つ BadgeStore を作成して seed する
        let store = BadgeStore(apiClient: MockHelixAPIClient(), persistenceService: persistence)
        await store.seedFromPersistence()

        // 検証: seed 後にバッジ画像 URL が解決できる（2x URL を使用）
        let ircBadge = Badge(name: "broadcaster", version: "1")
        let url = await store.imageURL(for: ircBadge)
        #expect(url?.absoluteString == "https://cdn.example.com/broadcaster/1/2x.png")
    }

    @Test("persistenceServiceなしのBadgeStoreはseedFromPersistenceを呼んでも安全")
    func persistenceServiceなしのBadgeStoreはseedFromPersistenceを呼んでも安全() async {
        // 前提: persistenceService なしの BadgeStore（既存コードとの後方互換確認）
        let store = BadgeStore(apiClient: MockHelixAPIClient())

        // 操作: seedFromPersistence を呼んでもクラッシュしない
        await store.seedFromPersistence()

        // 検証: バッジが設定されていない（URL 解決は nil）
        let url = await store.imageURL(for: Badge(name: "broadcaster", version: "1"))
        #expect(url == nil)
    }

    // MARK: - write-back

    @Test("fetchGlobalBadges成功後に永続化サービスにバッジが保存される")
    func fetchGlobalBadges成功後に永続化サービスにバッジが保存される() async {
        // 前提: バッジレスポンスを返す API クライアントと InMemoryPersistenceService
        let apiClient = MockCountingBadgeAPIClient(badgeJSON: broadcasterBadgeJSON())
        let persistence = InMemoryPersistenceService()
        let store = BadgeStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: グローバルバッジをフェッチする
        await store.fetchGlobalBadges()

        // 検証: 永続化サービスにバッジが保存されている
        // write-back は Task で非同期に行うため少し待機する
        try? await Task.sleep(nanoseconds: 100_000_000)
        let saved = await persistence.loadBadges(scope: .global)
        #expect(saved.contains { $0.setId == "broadcaster" })
    }

    @Test("fetchChannelBadges成功後にチャンネルスコープで永続化される")
    func fetchChannelBadges成功後にチャンネルスコープで永続化される() async {
        // 前提: チャンネルバッジ（subscriber）を返す API クライアント
        let subVersion = """
            {"id":"6","image_url_1x":"https://cdn.example.com/sub/6/1x.png",\
            "image_url_2x":"https://cdn.example.com/sub/6/2x.png",\
            "image_url_4x":"https://cdn.example.com/sub/6/4x.png",\
            "title":"6ヶ月サブスク","description":"6ヶ月サブスクバッジ"}
            """
        let subscriberJSON = """
            {"data":[{"set_id":"subscriber","versions":[\(subVersion)]}]}
            """
        let apiClient = MockCountingBadgeAPIClient(badgeJSON: subscriberJSON)
        let persistence = InMemoryPersistenceService()
        // channelId は Twitch room-id 形式（数字のみ）を使用する
        let channelId = "12345678"
        let store = BadgeStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: チャンネルバッジをフェッチする
        await store.fetchChannelBadges(channelId: channelId)

        // 検証: チャンネルスコープで永続化されている
        try? await Task.sleep(nanoseconds: 100_000_000)
        let saved = await persistence.loadBadges(scope: .channel(broadcasterId: channelId))
        #expect(saved.contains { $0.setId == "subscriber" })
    }

    // MARK: - TTL（stale-while-revalidate）

    @Test("TTL24時間以内のseedではisGlobalLoadedがtrueになりAPI呼び出しを抑止する")
    func TTL24時間以内のseedではisGlobalLoadedがtrueになりAPI呼び出しを抑止する() async {
        // 前提: 23h 前に保存したグローバルバッジ（TTL 24h 以内）
        let persistence = InMemoryPersistenceService()
        let badge = makeBroadcasterBadge()
        let twentyThreeHoursAgo = Date().addingTimeInterval(-23 * 3600)
        await persistence.saveBadgesWithDate([badge], scope: .global, savedAt: twentyThreeHoursAgo)

        let apiClient = MockCountingBadgeAPIClient()
        let store = BadgeStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchGlobalBadges を呼ぶ
        await store.seedFromPersistence()
        await store.fetchGlobalBadges()

        // 検証: TTL 以内なので API は呼ばれない（isGlobalLoaded = true で guard を通過しない）
        let callCount = await apiClient.getCallCount
        #expect(callCount == 0)
    }

    @Test("TTL24時間超のseedではAPIを再フェッチする（stale-while-revalidate）")
    func TTL24時間超のseedではAPIを再フェッチする() async {
        // 前提: 25h 前に保存したグローバルバッジ（TTL 24h 超）
        let persistence = InMemoryPersistenceService()
        let badge = makeBroadcasterBadge()
        let twentyFiveHoursAgo = Date().addingTimeInterval(-25 * 3600)
        await persistence.saveBadgesWithDate([badge], scope: .global, savedAt: twentyFiveHoursAgo)

        // API は失敗させて（ネットワーク未接続想定）API が呼ばれたかどうかだけ確認する
        let apiClient = MockCountingBadgeAPIClient()
        let store = BadgeStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchGlobalBadges を呼ぶ
        await store.seedFromPersistence()
        await store.fetchGlobalBadges()

        // 検証: TTL 超過のため isGlobalLoaded = false のまま → API が呼ばれる
        let callCount = await apiClient.getCallCount
        #expect(callCount == 1)
    }

    // MARK: - scope 分離

    @Test("グローバルバッジとチャンネルバッジは別スコープで独立して永続化される")
    func グローバルバッジとチャンネルバッジは別スコープで独立して永続化される() async {
        // 前提: グローバルとチャンネルで異なるバッジを事前保存
        let persistence = InMemoryPersistenceService()
        let globalBadge = BadgeVersionSnapshot(
            setId: "broadcaster",
            version: "1",
            imageUrl1x: "https://cdn.example.com/broadcaster/1/1x.png",
            imageUrl2x: "https://cdn.example.com/broadcaster/1/2x.png",
            imageUrl4x: "https://cdn.example.com/broadcaster/1/4x.png",
            title: "配信者",
            description: nil
        )
        let channelBadge = BadgeVersionSnapshot(
            setId: "subscriber",
            version: "6",
            imageUrl1x: "https://cdn.example.com/sub/6/1x.png",
            imageUrl2x: "https://cdn.example.com/sub/6/2x.png",
            imageUrl4x: "https://cdn.example.com/sub/6/4x.png",
            title: "6ヶ月サブスク",
            description: nil
        )
        try? await persistence.saveBadges([globalBadge], scope: .global)
        try? await persistence.saveBadges([channelBadge], scope: .channel(broadcasterId: "テストチャンネルID"))

        // 操作: それぞれのスコープでタイムスタンプ付きバッジを取得
        let globalResult = await persistence.loadBadgesWithTimestamp(scope: .global)
        let channelResult = await persistence.loadBadgesWithTimestamp(
            scope: .channel(broadcasterId: "テストチャンネルID")
        )
        let unknownResult = await persistence.loadBadgesWithTimestamp(
            scope: .channel(broadcasterId: "未登録チャンネルID")
        )

        // 検証: グローバルスコープには broadcaster バッジのみ
        #expect(globalResult.snapshots.count == 1)
        #expect(globalResult.snapshots.first?.setId == "broadcaster")
        #expect(globalResult.fetchedAt != nil)

        // 検証: チャンネルスコープには subscriber バッジのみ
        #expect(channelResult.snapshots.count == 1)
        #expect(channelResult.snapshots.first?.setId == "subscriber")
        #expect(channelResult.fetchedAt != nil)

        // 検証: 未登録チャンネルは空かつ fetchedAt は nil
        #expect(unknownResult.snapshots.isEmpty)
        #expect(unknownResult.fetchedAt == nil)
    }
}
