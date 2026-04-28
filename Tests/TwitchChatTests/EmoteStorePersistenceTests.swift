// EmoteStorePersistenceTests.swift
// EmoteStore の永続化配線テスト（seed / write-back / TTL / scope 分離）

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// API 呼び出し回数を記録するエモート API クライアント
///
/// fetchGlobalEmotes / fetchChannelEmotes / fetchUserEmotes の TTL テストで
/// 「API が呼ばれたか」を確認するために使用する
actor MockCountingEmoteAPIClient: HelixAPIClientProtocol {

    /// 成功レスポンスとして返す JSON（nil の場合は未認証エラーを返す）
    let emoteJSON: String?

    /// `get` が呼ばれた回数
    private(set) var getCallCount = 0

    init(emoteJSON: String? = nil) {
        self.emoteJSON = emoteJSON
    }

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        getCallCount += 1
        if let json = emoteJSON, let data = json.data(using: .utf8) {
            return try JSONDecoder().decode(T.self, from: data)
        }
        // 成功 JSON 未設定の場合は未認証エラー（assertionFailure を避けるため）
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

/// 複数ページを順に返すエモート API クライアント（ページネーションテスト用）
actor MockPaginatingEmoteAPIClient: HelixAPIClientProtocol {

    /// ページ順のレスポンス JSON 配列
    let pages: [String]
    private var callIndex = 0

    init(pages: [String]) {
        self.pages = pages
    }

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        let json = callIndex < pages.count ? pages[callIndex] : "{\"data\":[]}"
        callIndex += 1
        guard let data = json.data(using: .utf8) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
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

/// EmoteStore の永続化配線（seed / write-back / TTL / scope 分離）テスト
@Suite("EmoteStorePersistenceTests")
struct EmoteStorePersistenceTests {

    // MARK: - ヘルパー

    /// グローバルエモート（LUL）を生成する
    private func makeGlobalEmote() -> HelixEmote {
        HelixEmote(
            id: "304486245",
            name: "LUL",
            format: ["static"],
            emoteType: "globals",
            emoteSetId: "0",
            ownerId: nil
        )
    }

    /// ユーザーエモート（PogChamp）を生成する
    private func makeUserEmote(id: String = "115234", name: String = "PogChamp") -> HelixEmote {
        HelixEmote(
            id: id,
            name: name,
            format: ["static"],
            emoteType: "subscriptions",
            emoteSetId: "300374452",
            ownerId: "987654321"
        )
    }

    /// チャンネルエモート（Kappa）を生成する
    private func makeChannelEmote() -> HelixEmote {
        HelixEmote(
            id: "25",
            name: "Kappa",
            format: ["static"],
            emoteType: "subscriptions",
            emoteSetId: "999999",
            ownerId: "12345678"
        )
    }

    /// グローバル / チャンネルエモート用 JSON を生成する（HelixEmotesResponse 形式）
    private func globalEmoteJSON() -> String {
        """
        {"data":[{"id":"304486245","name":"LUL","format":["static"],\
        "emote_type":"globals","emote_set_id":"0"}]}
        """
    }

    /// チャンネルエモート用 JSON を生成する
    private func channelEmoteJSON() -> String {
        """
        {"data":[{"id":"25","name":"Kappa","format":["static"],\
        "emote_type":"subscriptions","emote_set_id":"999999","owner_id":"12345678"}]}
        """
    }

    /// ユーザーエモートの1ページ目 JSON（cursor あり）
    private func userEmotePage1JSON() -> String {
        """
        {"data":[{"id":"115234","name":"PogChamp","format":["static"],\
        "emote_type":"subscriptions","emote_set_id":"300374452","owner_id":"987654321"}],\
        "pagination":{"cursor":"abc123"}}
        """
    }

    /// ユーザーエモートの2ページ目 JSON（cursor なし = 最終ページ）
    private func userEmotePage2JSON() -> String {
        """
        {"data":[{"id":"88634","name":"EleGiggle","format":["static"],\
        "emote_type":"subscriptions","emote_set_id":"300374453","owner_id":"987654321"}],\
        "pagination":{}}
        """
    }

    /// 永続化サービスにグローバルエモートが保存されるまでポーリング待機する
    private func waitForSavedGlobalEmotes(
        in persistence: InMemoryPersistenceService,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> [HelixEmote] {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let saved = await persistence.loadGlobalEmotes()
            if !saved.isEmpty { return saved }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await persistence.loadGlobalEmotes()
    }

    /// 永続化サービスにユーザーエモートが保存されるまでポーリング待機する
    private func waitForSavedUserEmotes(
        in persistence: InMemoryPersistenceService,
        userId: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> [HelixEmote] {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let saved = await persistence.loadUserEmotes(userId: userId)
            if !saved.isEmpty { return saved }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await persistence.loadUserEmotes(userId: userId)
    }

    /// 永続化サービスにチャンネルエモートが保存されるまでポーリング待機する
    private func waitForSavedChannelEmotes(
        in persistence: InMemoryPersistenceService,
        broadcasterId: String,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> [HelixEmote] {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            let saved = await persistence.loadChannelEmotes(broadcasterId: broadcasterId)
            if !saved.isEmpty { return saved }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await persistence.loadChannelEmotes(broadcasterId: broadcasterId)
    }

    // MARK: - seed 正常系

    @Test("永続化済みグローバルエモートからseedするとallEmotesに含まれる")
    func 永続化済みグローバルエモートからseedするとallEmotesに含まれる() async throws {
        // 前提: InMemoryPersistenceService にグローバルエモートを事前保存する
        let persistence = InMemoryPersistenceService()
        let emote = makeGlobalEmote()
        try await persistence.saveGlobalEmotes([emote])

        // 操作: 永続化サービスを持つ EmoteStore を作成して seed する
        let store = EmoteStore(apiClient: MockHelixAPIClient(), persistenceService: persistence)
        await store.seedFromPersistence()

        // 検証: seed 後に allEmotes に LUL が含まれる
        let all = await store.allEmotes()
        #expect(all.contains { $0.name == "LUL" })
    }

    @Test("永続化済みユーザーエモートをseedするとuserEmotesSnapshotに含まれる")
    func 永続化済みユーザーエモートをseedするとuserEmotesSnapshotに含まれる() async throws {
        // 前提: InMemoryPersistenceService にユーザーエモートを事前保存する
        let persistence = InMemoryPersistenceService()
        let emote = makeUserEmote()
        let userId = "123456789"
        try await persistence.saveUserEmotes([emote], userId: userId)

        // 操作: seedUserEmotes を呼ぶ（isUserEmotesLoaded は立てない）
        let store = EmoteStore(apiClient: MockHelixAPIClient(), persistenceService: persistence)
        await store.seedUserEmotes(userId: userId)

        // 検証: seed 後に userEmotesSnapshot に PogChamp が含まれる
        let snapshot = await store.userEmotesSnapshot()
        #expect(snapshot.contains { $0.name == "PogChamp" })
    }

    @Test("永続化済みチャンネルエモートをseedするとchannelEmotesSnapshotに含まれる")
    func 永続化済みチャンネルエモートをseedするとchannelEmotesSnapshotに含まれる() async throws {
        // 前提: InMemoryPersistenceService にチャンネルエモートを事前保存する
        let persistence = InMemoryPersistenceService()
        let emote = makeChannelEmote()
        let broadcasterId = "12345678"
        try await persistence.saveChannelEmotes([emote], broadcasterId: broadcasterId)

        // 操作: seedChannelEmotes を呼ぶ
        let store = EmoteStore(apiClient: MockHelixAPIClient(), persistenceService: persistence)
        await store.seedChannelEmotes(broadcasterId: broadcasterId)

        // 検証: seed 後に channelEmotesSnapshot に Kappa が含まれる
        let snapshot = await store.channelEmotesSnapshot()
        #expect(snapshot.contains { $0.name == "Kappa" })
    }

    @Test("persistenceServiceなしのEmoteStoreはseedを呼んでも安全")
    func persistenceServiceなしのEmoteStoreはseedを呼んでも安全() async {
        // 前提: persistenceService なしの EmoteStore（既存コードとの後方互換確認）
        let store = EmoteStore(apiClient: MockHelixAPIClient())

        // 操作: 各 seed メソッドを呼んでもクラッシュしない
        await store.seedFromPersistence()
        await store.seedUserEmotes(userId: "123456789")
        await store.seedChannelEmotes(broadcasterId: "12345678")

        // 検証: エモートが設定されていない（空の状態）
        let all = await store.allEmotes()
        #expect(all.isEmpty)
    }

    // MARK: - TTL 内なら isXxxLoaded が立ち API を抑止する

    @Test("TTL24時間以内のグローバルseedでAPI呼び出しをスキップする")
    func TTL24時間以内のグローバルseedでAPI呼び出しをスキップする() async {
        // 前提: 23h 前に保存したグローバルエモート（TTL 24h 以内）
        let persistence = InMemoryPersistenceService()
        let emote = makeGlobalEmote()
        let twentyThreeHoursAgo = Date().addingTimeInterval(-23 * 3600)
        await persistence.saveGlobalEmotesWithDate([emote], savedAt: twentyThreeHoursAgo)

        let apiClient = MockCountingEmoteAPIClient()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchGlobalEmotes を呼ぶ
        await store.seedFromPersistence()
        await store.fetchGlobalEmotes()

        // 検証: TTL 以内なので API は呼ばれない（isGlobalLoaded = true で guard を通過しない）
        let callCount = await apiClient.getCallCount
        #expect(callCount == 0)
    }

    @Test("TTL24時間超のグローバルseedでAPIを再フェッチする")
    func TTL24時間超のグローバルseedでAPIを再フェッチする() async {
        // 前提: 25h 前に保存したグローバルエモート（TTL 24h 超）
        let persistence = InMemoryPersistenceService()
        let emote = makeGlobalEmote()
        let twentyFiveHoursAgo = Date().addingTimeInterval(-25 * 3600)
        await persistence.saveGlobalEmotesWithDate([emote], savedAt: twentyFiveHoursAgo)

        // API は失敗させて（ネットワーク未接続想定）API が呼ばれたかどうかだけ確認する
        let apiClient = MockCountingEmoteAPIClient()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchGlobalEmotes を呼ぶ
        await store.seedFromPersistence()
        await store.fetchGlobalEmotes()

        // 検証: TTL 超過のため isGlobalLoaded = false のまま → API が呼ばれる
        let callCount = await apiClient.getCallCount
        #expect(callCount == 1)
    }

    @Test("TTL24時間以内のユーザーseedでAPI呼び出しをスキップする")
    func TTL24時間以内のユーザーseedでAPI呼び出しをスキップする() async {
        // 前提: 23h 前に保存したユーザーエモート（TTL 24h 以内）
        let persistence = InMemoryPersistenceService()
        let emote = makeUserEmote()
        let userId = "123456789"
        let twentyThreeHoursAgo = Date().addingTimeInterval(-23 * 3600)
        await persistence.saveUserEmotesWithDate([emote], userId: userId, savedAt: twentyThreeHoursAgo)

        let apiClient = MockCountingEmoteAPIClient()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchUserEmotes を呼ぶ
        await store.seedUserEmotes(userId: userId)
        await store.fetchUserEmotes(userId: userId)

        // 検証: TTL 以内なので API は呼ばれない（isUserEmotesLoaded = true で guard を通過しない）
        let callCount = await apiClient.getCallCount
        #expect(callCount == 0)
    }

    @Test("TTL24時間超のユーザーseedでAPIを再フェッチする")
    func TTL24時間超のユーザーseedでAPIを再フェッチする() async {
        // 前提: 25h 前に保存したユーザーエモート（TTL 24h 超）
        let persistence = InMemoryPersistenceService()
        let emote = makeUserEmote()
        let userId = "123456789"
        let twentyFiveHoursAgo = Date().addingTimeInterval(-25 * 3600)
        await persistence.saveUserEmotesWithDate([emote], userId: userId, savedAt: twentyFiveHoursAgo)

        let apiClient = MockCountingEmoteAPIClient()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: seed してから fetchUserEmotes を呼ぶ
        await store.seedUserEmotes(userId: userId)
        await store.fetchUserEmotes(userId: userId)

        // 検証: TTL 超過のため isUserEmotesLoaded = false のまま → API が呼ばれる
        let callCount = await apiClient.getCallCount
        #expect(callCount == 1)
    }

    // MARK: - write-back（fetch 成功後に永続化される）

    @Test("fetchGlobalEmotes成功後にグローバルスコープで永続化される")
    func fetchGlobalEmotes成功後にグローバルスコープで永続化される() async {
        // 前提: グローバルエモートレスポンスを返す API クライアントと InMemoryPersistenceService
        let apiClient = MockCountingEmoteAPIClient(emoteJSON: globalEmoteJSON())
        let persistence = InMemoryPersistenceService()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: グローバルエモートをフェッチする
        await store.fetchGlobalEmotes()

        // 検証: 永続化サービスにエモートが保存されている（write-back の完了を bounded poll で待機）
        let saved = await waitForSavedGlobalEmotes(in: persistence)
        #expect(saved.contains { $0.name == "LUL" })
    }

    @Test("fetchChannelEmotes成功後にチャンネルスコープで永続化される")
    func fetchChannelEmotes成功後にチャンネルスコープで永続化される() async {
        // 前提: チャンネルエモートレスポンスを返す API クライアント
        // broadcasterId は Twitch room-id 形式（数字のみ）を使用する
        let broadcasterId = "12345678"
        let apiClient = MockCountingEmoteAPIClient(emoteJSON: channelEmoteJSON())
        let persistence = InMemoryPersistenceService()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: チャンネルエモートをフェッチする
        await store.fetchChannelEmotes(broadcasterId: broadcasterId)

        // 検証: チャンネルスコープで永続化されている（write-back の完了を bounded poll で待機）
        let saved = await waitForSavedChannelEmotes(in: persistence, broadcasterId: broadcasterId)
        #expect(saved.contains { $0.name == "Kappa" })
    }

    @Test("fetchUserEmotes全ページ完了後にユーザースコープで永続化される")
    func fetchUserEmotes全ページ完了後にユーザースコープで永続化される() async {
        // 前提: 2 ページ分のユーザーエモートを返す API クライアント（cursor 付き → cursor なし）
        let userId = "123456789"
        let apiClient = MockPaginatingEmoteAPIClient(pages: [
            userEmotePage1JSON(),
            userEmotePage2JSON()
        ])
        let persistence = InMemoryPersistenceService()
        let store = EmoteStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: ユーザーエモートをフェッチする（全ページ完了後に write-back される）
        await store.fetchUserEmotes(userId: userId)

        // 検証: 両ページのエモートが永続化されている
        let saved = await waitForSavedUserEmotes(in: persistence, userId: userId)
        #expect(saved.contains { $0.name == "PogChamp" })
        #expect(saved.contains { $0.name == "EleGiggle" })
    }

    // MARK: - scope 分離

    @Test("clearUserScopedはユーザースコープのみ削除しグローバルとチャンネルは残る")
    func clearUserScopedはユーザースコープのみ削除しグローバルとチャンネルは残る() async throws {
        // 前提: グローバル・チャンネル・ユーザーの 3 スコープにエモートを保存する
        let persistence = InMemoryPersistenceService()
        let userId = "123456789"
        let broadcasterId = "12345678"

        try await persistence.saveGlobalEmotes([makeGlobalEmote()])
        try await persistence.saveChannelEmotes([makeChannelEmote()], broadcasterId: broadcasterId)
        try await persistence.saveUserEmotes([makeUserEmote()], userId: userId)

        // 操作: ユーザースコープをクリアする
        await persistence.clearUserScoped(userId: userId)

        // 検証: グローバルとチャンネルは残り、ユーザースコープのみ削除される
        let global = await persistence.loadGlobalEmotes()
        let channel = await persistence.loadChannelEmotes(broadcasterId: broadcasterId)
        let user = await persistence.loadUserEmotes(userId: userId)

        #expect(global.contains { $0.name == "LUL" })
        #expect(channel.contains { $0.name == "Kappa" })
        #expect(user.isEmpty)
    }

    @Test("グローバル_ユーザー_チャンネルのエモートは別スコープで独立して永続化される")
    func グローバル_ユーザー_チャンネルのエモートは別スコープで独立して永続化される() async throws {
        // 前提: 3 スコープにそれぞれ異なるエモートを保存する
        let persistence = InMemoryPersistenceService()
        let userId = "123456789"
        let broadcasterId = "12345678"

        try await persistence.saveGlobalEmotes([makeGlobalEmote()])
        try await persistence.saveUserEmotes([makeUserEmote()], userId: userId)
        try await persistence.saveChannelEmotes([makeChannelEmote()], broadcasterId: broadcasterId)

        // 操作: 各スコープのタイムスタンプ付きロードを実行する
        let globalResult = await persistence.loadGlobalEmotesWithTimestamp()
        let userResult = await persistence.loadUserEmotesWithTimestamp(userId: userId)
        let channelResult = await persistence.loadChannelEmotesWithTimestamp(broadcasterId: broadcasterId)
        let unknownResult = await persistence.loadUserEmotesWithTimestamp(userId: "未登録ユーザーID")

        // 検証: 各スコープのエモートが独立している
        #expect(globalResult.emotes.count == 1)
        #expect(globalResult.emotes.first?.name == "LUL")
        #expect(globalResult.fetchedAt != nil)

        #expect(userResult.emotes.count == 1)
        #expect(userResult.emotes.first?.name == "PogChamp")
        #expect(userResult.fetchedAt != nil)

        #expect(channelResult.emotes.count == 1)
        #expect(channelResult.emotes.first?.name == "Kappa")
        #expect(channelResult.fetchedAt != nil)

        // 検証: 未登録スコープは空かつ fetchedAt は nil
        #expect(unknownResult.emotes.isEmpty)
        #expect(unknownResult.fetchedAt == nil)
    }
}
