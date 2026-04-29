// EmoteStoreTests.swift
// EmoteStore の取得・フィルタリングロジックテスト

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// フェッチ回数をデータレースなく計測するカウンター
actor FetchCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

/// 特定エンドポイントへのフェッチ回数をカウントするモッククライアント
///
/// - `countedEndpoint` に含まれる URL パターンへのリクエスト数のみを計測する
/// - `/emotes/user` URL の場合は `HelixUserEmotesResponse`、それ以外は `HelixEmotesResponse` を返す
struct CountingMockClient: HelixAPIClientProtocol {
    let counter: FetchCounter
    /// カウント対象とする URL パターン（例: "/emotes/user", "/emotes/global"）
    let countedEndpoint: String

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if url.absoluteString.contains(countedEndpoint) {
            await counter.increment()
        }
        if url.absoluteString.contains("/emotes/user") {
            if let response = HelixUserEmotesResponse(data: [], cursor: nil) as? T {
                return response
            }
        } else {
            if let response = HelixEmotesResponse(data: []) as? T {
                return response
            }
        }
        throw URLError(.badServerResponse)
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T { throw URLError(.badServerResponse) }

    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws { throw URLError(.badServerResponse) }

    func patch<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws { throw URLError(.badServerResponse) }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws { throw URLError(.badServerResponse) }
}

/// HelixAPIClientProtocol のテスト用モック（EmoteStore テスト専用）
///
/// - `shouldThrowAuthError = true` の場合は未ログイン状態をシミュレート
/// - `stubbedEmotes` にエモート配列を設定するとグローバル・チャンネルエモートエンドポイントで返す
/// - `stubbedUserEmotesPages` にページ配列を設定するとユーザーエモートエンドポイントでページネーション返す
/// - いずれも未設定の場合はサーバーエラーを throw する
struct MockHelixAPIClientForEmote: HelixAPIClientProtocol {
    var shouldThrowAuthError: Bool = false
    var stubbedEmotes: [HelixEmote]?

    /// ユーザーエモートのページ配列。index 0 が 1 ページ目、index 1 が 2 ページ目...
    /// cursor は次ページのインデックス文字列（"1", "2", ...）として返す
    var stubbedUserEmotesPages: [[HelixEmote]] = []

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        // ユーザーエモートエンドポイント（/helix/chat/emotes/user）
        if url.absoluteString.contains("/emotes/user") {
            let afterCursor = queryItems?.first(where: { $0.name == "after" })?.value
            let pageIndex = afterCursor.flatMap(Int.init) ?? 0
            let pageData = pageIndex < stubbedUserEmotesPages.count ? stubbedUserEmotesPages[pageIndex] : []
            let hasNextPage = (pageIndex + 1) < stubbedUserEmotesPages.count
            let nextCursor = hasNextPage ? String(pageIndex + 1) : nil
            if let response = HelixUserEmotesResponse(data: pageData, cursor: nextCursor) as? T {
                return response
            }
        }
        // グローバル・チャンネルエモートエンドポイント
        if let emotes = stubbedEmotes, let response = HelixEmotesResponse(data: emotes) as? T {
            return response
        }
        throw URLError(.badServerResponse)
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws -> T {
        throw URLError(.badServerResponse)
    }

    func postNoContent<Body: Encodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws {
        throw URLError(.badServerResponse)
    }

    func patch<Body: Encodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws {
        throw URLError(.badServerResponse)
    }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        throw URLError(.badServerResponse)
    }
}

// MARK: - テスト用エモートデータ

extension HelixEmote {
    /// テスト用グローバルエモート（LUL）
    static let グローバルエモートLUL = HelixEmote(id: "425618", name: "LUL", format: ["static", "animated"], emoteType: "globals")
    /// テスト用グローバルエモート（PogChamp）
    static let グローバルエモートPogChamp = HelixEmote(id: "305954156", name: "PogChamp", format: ["static"], emoteType: "globals")
    /// テスト用チャンネルエモート（サブスク）
    static let チャンネルエモートHype = HelixEmote(id: "emotesv2_abc", name: "配信者Hype", format: ["static"], emoteType: "subscriptions")
    /// テスト用ユーザーエモート（別チャンネルサブスク）
    static let ユーザーエモート別チャンネルSub = HelixEmote(
        id: "emotesv2_user_sub", name: "別チャンネルSub", format: ["static"],
        emoteType: "subscriptions", emoteSetId: "99999"
    )
    /// テスト用ユーザーエモート（ビッツ）
    static let ユーザーエモートBits = HelixEmote(
        id: "emotesv2_bits_test", name: "ビッツ応援エモート", format: ["static", "animated"],
        emoteType: "bitstier", emoteSetId: "88888"
    )
}

@Suite("EmoteStoreTests")
struct EmoteStoreTests {

    // MARK: - グローバルエモート取得

    @Test("グローバルエモートをテスト用セッターで設定して取得できる")
    func testSetAndGetGlobalEmotes() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // グローバルエモートを直接設定（テスト用）
        await store.setGlobalEmotes([.グローバルエモートLUL, .グローバルエモートPogChamp])
        let emotes = await store.allEmotes()

        guard emotes.count == 2 else {
            Issue.record("エモート件数が期待値と異なります: \(emotes.count)")
            return
        }
        #expect(emotes.first?.name == "LUL")
        #expect(emotes.last?.name == "PogChamp")
    }

    @Test("チャンネルエモートはグローバルエモートの前に返される")
    func testChannelEmotesComesFirst() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        await store.setGlobalEmotes([.グローバルエモートLUL])
        await store.setChannelEmotes([.チャンネルエモートHype])
        let emotes = await store.allEmotes()

        // チャンネルエモートが先頭、グローバルエモートが後尾
        guard emotes.count == 2 else {
            Issue.record("エモート件数が期待値と異なります: \(emotes.count)")
            return
        }
        #expect(emotes.first?.name == "配信者Hype")
        #expect(emotes.last?.name == "LUL")
    }

    // MARK: - チャンネルエモートリセット

    @Test("resetChannelEmotes でチャンネルエモートがクリアされる")
    func testResetChannelEmotes() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        await store.setGlobalEmotes([.グローバルエモートLUL])
        await store.setChannelEmotes([.チャンネルエモートHype])
        await store.resetChannelEmotes()
        let emotes = await store.allEmotes()

        // チャンネルエモートがなくなりグローバルのみ残る
        #expect(emotes.count == 1)
        #expect(emotes.first?.name == "LUL")
    }

    // MARK: - 未ログイン時スキップ

    @Test("未ログイン状態ではグローバルエモートフェッチをスキップする")
    func testFetchGlobalEmotesSkipsWhenNotLoggedIn() async {
        let mockClient = MockHelixAPIClientForEmote(shouldThrowAuthError: true)
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchGlobalEmotes()
        let emotes = await store.allEmotes()

        // 認証エラー時はエモートが空のまま（クラッシュしない）
        #expect(emotes.isEmpty)
    }

    @Test("未ログイン状態ではチャンネルエモートフェッチをスキップする")
    func testFetchChannelEmotesSkipsWhenNotLoggedIn() async {
        let mockClient = MockHelixAPIClientForEmote(shouldThrowAuthError: true)
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchChannelEmotes(broadcasterId: "123456")
        let emotes = await store.allEmotes()

        // 認証エラー時はエモートが空のまま（クラッシュしない）
        #expect(emotes.isEmpty)
    }

    // MARK: - 入力バリデーション

    @Test("broadcasterId が空文字の場合はフェッチをスキップする")
    func testFetchChannelEmotesSkipsEmptyBroadcasterId() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // 空文字でクラッシュしないことを確認
        await store.fetchChannelEmotes(broadcasterId: "")
        let emotes = await store.allEmotes()

        #expect(emotes.isEmpty)
    }

    @Test("broadcasterId が数字以外を含む場合はフェッチをスキップする")
    func testFetchChannelEmotesSkipsInvalidBroadcasterId() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // インジェクション防止のためのバリデーション
        await store.fetchChannelEmotes(broadcasterId: "invalid_id")
        let emotes = await store.allEmotes()

        #expect(emotes.isEmpty)
    }

    // MARK: - グローバルエモート1回のみ取得

    @Test("グローバルエモートは1回だけフェッチされる（isGlobalLoaded フラグ）")
    func testGlobalEmotesFetchedOnce() async {
        let counter = FetchCounter()
        let store = EmoteStore(apiClient: CountingMockClient(counter: counter, countedEndpoint: "/emotes/global"))

        // 2回呼んでも1回しかフェッチしない
        await store.fetchGlobalEmotes()
        await store.fetchGlobalEmotes()

        #expect(await counter.value == 1)
    }

    // MARK: - エモート名逆引き

    @Test("emote(byName:) でグローバルエモートを名前で検索できる")
    func testEmoteByNameFindsGlobalEmote() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL, .グローバルエモートPogChamp])

        let result = await store.emote(byName: "LUL")
        #expect(result?.id == "425618")
        #expect(result?.name == "LUL")
    }

    @Test("emote(byName:) でチャンネルエモートはグローバルエモートより優先される")
    func testEmoteByNamePrefersChannelEmote() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        // チャンネルエモートとグローバルエモートで同名の場合、チャンネルエモートが返る
        let globalLUL = HelixEmote(id: "グローバルID", name: "LUL", format: ["static"], emoteType: "globals")
        let channelLUL = HelixEmote(id: "チャンネルID", name: "LUL", format: ["static"], emoteType: "subscriptions")
        await store.setGlobalEmotes([globalLUL])
        await store.setChannelEmotes([channelLUL])

        let result = await store.emote(byName: "LUL")
        #expect(result?.id == "チャンネルID")
    }

    @Test("emote(byName:) で存在しない名前は nil を返す")
    func testEmoteByNameReturnsNilForUnknown() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL])

        let result = await store.emote(byName: "存在しないエモート")
        #expect(result == nil)
    }

    // MARK: - テキスト内エモート位置解決

    @Test("emotePositions(in:) でテキスト先頭のエモートを検出できる")
    func testEmotePositionsAtStart() async {
        // 前提: "LUL こんにちは" — LUL は先頭（UTF-16 オフセット 0〜2）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL])

        let positions = await store.emotePositions(in: "LUL こんにちは")

        #expect(positions.count == 1)
        #expect(positions.first?.emoteId == "425618")
        #expect(positions.first?.startIndex == 0)
        #expect(positions.first?.endIndex == 2) // "LUL" は 3 文字 → 0〜2 (inclusive)
    }

    @Test("emotePositions(in:) でテキスト中間のエモートを検出できる")
    func testEmotePositionsInMiddle() async {
        // 前提: "Hello PogChamp World" — PogChamp は 6 文字目から（UTF-16 オフセット 6〜13）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートPogChamp])

        let positions = await store.emotePositions(in: "Hello PogChamp World")

        #expect(positions.count == 1)
        #expect(positions.first?.emoteId == "305954156")
        #expect(positions.first?.startIndex == 6)
        #expect(positions.first?.endIndex == 13) // "PogChamp" は 8 文字 → 6〜13 (inclusive)
    }

    @Test("emotePositions(in:) で複数エモートをすべて検出できる")
    func testEmotePositionsMultiple() async {
        // 前提: "LUL PogChamp" — LUL は 0〜2、PogChamp は 4〜11
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL, .グローバルエモートPogChamp])

        let positions = await store.emotePositions(in: "LUL PogChamp")

        #expect(positions.count == 2)
        #expect(positions[0].emoteId == "425618")
        #expect(positions[0].startIndex == 0)
        #expect(positions[0].endIndex == 2)
        #expect(positions[1].emoteId == "305954156")
        #expect(positions[1].startIndex == 4)
        #expect(positions[1].endIndex == 11)
    }

    @Test("emotePositions(in:) でエモートが含まれないテキストは空配列を返す")
    func testEmotePositionsNoEmotes() async {
        // 前提: エモートが含まれない通常テキスト
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL])

        let positions = await store.emotePositions(in: "こんにちは、世界！")

        #expect(positions.isEmpty)
    }

    @Test("emotePositions(in:) で空文字列は空配列を返す")
    func testEmotePositionsEmptyString() async {
        // 前提: 空文字列
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL])

        let positions = await store.emotePositions(in: "")

        #expect(positions.isEmpty)
    }

    // MARK: - ユーザーエモートセット管理

    @Test("updateUserEmoteSets で設定した値が userAvailableEmoteSets で取得できる")
    func testUpdateUserEmoteSets() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // 操作: サブスクユーザーのエモートセットを設定する
        await store.updateUserEmoteSets(Set(["0", "33", "50"]))

        // 検証: 設定したエモートセットが取得できる
        let emoteSets = await store.userAvailableEmoteSets()
        #expect(emoteSets == Set(["0", "33", "50"]))
    }

    @Test("updateUserEmoteSets を複数回呼ぶと上書きされる")
    func testUpdateUserEmoteSetsOverwrite() async {
        // 前提: 最初は一般ユーザー、その後サブスクでエモートセットが増える
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        await store.updateUserEmoteSets(Set(["0"]))
        await store.updateUserEmoteSets(Set(["0", "793"]))

        // 検証: 最後に設定した値が返される
        let emoteSets = await store.userAvailableEmoteSets()
        #expect(emoteSets == Set(["0", "793"]))
    }

    @Test("USERSTATE 未受信の場合は userAvailableEmoteSets が nil を返す")
    func testUserAvailableEmoteSetsNilBeforeUserState() async {
        // 前提: updateUserEmoteSets を一度も呼んでいない初期状態
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // 検証: USERSTATE 未受信は nil（全エモート使用可能として扱う）
        let emoteSets = await store.userAvailableEmoteSets()
        #expect(emoteSets == nil)
    }

    @Test("resetChannelEmotes を呼んでも userEmoteSets はリセットされない")
    func testResetChannelEmotesDoesNotResetUserEmoteSets() async {
        // 前提: エモートセットを設定してからチャンネルリセットを呼ぶ
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.updateUserEmoteSets(Set(["0", "33"]))

        // チャンネル切替時のリセット
        await store.resetChannelEmotes()

        // 検証: ユーザーのエモートセットは保持される
        let emoteSets = await store.userAvailableEmoteSets()
        #expect(emoteSets == Set(["0", "33"]))
    }

    // MARK: - ユーザーエモート取得

    @Test("fetchUserEmotes で1ページのユーザーエモートを取得できる")
    func testFetchUserEmotesSinglePage() async {
        // 前提: /helix/chat/emotes/user が1ページ分のエモートを返す
        let mockClient = MockHelixAPIClientForEmote(
            stubbedUserEmotesPages: [[.ユーザーエモート別チャンネルSub]]
        )
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchUserEmotes(userId: "123456789")
        let emotes = await store.allEmotes()

        // 検証: ユーザーエモートが取得されて allEmotes に含まれる
        #expect(emotes.contains(where: { $0.name == "別チャンネルSub" }))
    }

    @Test("fetchUserEmotes が2ページにわたるエモートをすべて取得する")
    func testFetchUserEmotesPagination() async {
        // 前提: /helix/chat/emotes/user が2ページに分かれて返す
        let page1 = [HelixEmote(id: "emotesv2_p1", name: "サブスクエモートページ1", format: ["static"], emoteType: "subscriptions")]
        let page2 = [HelixEmote(id: "emotesv2_p2", name: "サブスクエモートページ2", format: ["static"], emoteType: "subscriptions")]
        let mockClient = MockHelixAPIClientForEmote(stubbedUserEmotesPages: [page1, page2])
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchUserEmotes(userId: "123456789")
        let emotes = await store.allEmotes()

        // 検証: 両ページのエモートがすべて取得される
        #expect(emotes.contains(where: { $0.name == "サブスクエモートページ1" }))
        #expect(emotes.contains(where: { $0.name == "サブスクエモートページ2" }))
    }

    @Test("未ログイン状態ではユーザーエモートフェッチをスキップする")
    func testFetchUserEmotesSkipsWhenNotLoggedIn() async {
        // 前提: 認証エラーが発生する状態（未ログイン）
        let mockClient = MockHelixAPIClientForEmote(shouldThrowAuthError: true)
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchUserEmotes(userId: "123456789")
        let emotes = await store.allEmotes()

        // 検証: 認証エラー時はエモートが空のまま
        #expect(emotes.isEmpty)
    }

    @Test("userId が空文字の場合はユーザーエモートフェッチをスキップする")
    func testFetchUserEmotesSkipsEmptyUserId() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // 空文字でクラッシュしないことを確認
        await store.fetchUserEmotes(userId: "")
        let emotes = await store.allEmotes()

        #expect(emotes.isEmpty)
    }

    @Test("userId が数字以外を含む場合はユーザーエモートフェッチをスキップする")
    func testFetchUserEmotesSkipsInvalidUserId() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        // インジェクション防止のためのバリデーション
        await store.fetchUserEmotes(userId: "invalid_user_id")
        let emotes = await store.allEmotes()

        #expect(emotes.isEmpty)
    }

    @Test("ユーザーエモートは1回だけフェッチされる")
    func testUserEmotesFetchedOnce() async {
        let counter = FetchCounter()
        let store = EmoteStore(apiClient: CountingMockClient(counter: counter, countedEndpoint: "/emotes/user"))

        // 2回呼んでも1回しかフェッチしない
        await store.fetchUserEmotes(userId: "123456789")
        await store.fetchUserEmotes(userId: "123456789")

        #expect(await counter.value == 1)
    }

    // MARK: - ユーザーエモート重複排除・優先順位

    @Test("allEmotes の順序はチャンネル → ユーザー → グローバルになる")
    func testAllEmotesOrdering() async {
        // 前提: 3種類のエモートを設定
        let channelEmote = HelixEmote(id: "ch_1", name: "チャンネルエモート", format: ["static"], emoteType: "subscriptions")
        let userEmote = HelixEmote(id: "user_1", name: "他チャンネルサブスクエモート", format: ["static"], emoteType: "subscriptions")
        let globalEmote = HelixEmote(id: "global_1", name: "グローバルエモートLUL", format: ["static"], emoteType: "globals")

        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setChannelEmotes([channelEmote])
        await store.setUserEmotes([userEmote])
        await store.setGlobalEmotes([globalEmote])

        let emotes = await store.allEmotes()

        // 検証: チャンネル → ユーザー → グローバルの順
        guard emotes.count == 3 else {
            Issue.record("エモート件数が期待値と異なります: \(emotes.count)")
            return
        }
        #expect(emotes[0].id == "ch_1")
        #expect(emotes[1].id == "user_1")
        #expect(emotes[2].id == "global_1")
    }

    @Test("allEmotes でチャンネルとユーザーエモートが同じ ID の場合は重複排除される")
    func testAllEmotesDedupesChannelAndUserEmotes() async {
        // 前提: チャンネルエモートとユーザーエモートで同じIDが重複する
        let sharedEmote = HelixEmote(id: "emotesv2_shared", name: "共有エモート", format: ["static"], emoteType: "subscriptions")

        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setChannelEmotes([sharedEmote])
        await store.setUserEmotes([sharedEmote])

        let emotes = await store.allEmotes()

        // 検証: 同じIDのエモートは1件のみ
        let duplicates = emotes.filter { $0.id == "emotesv2_shared" }
        #expect(duplicates.count == 1)
    }

    @Test("allEmotes でグローバルとユーザーエモートが同じ ID の場合は重複排除される")
    func testAllEmotesDedupesGlobalAndUserEmotes() async {
        // 前提: ユーザーエモートAPIがグローバルエモートも返す場合
        let globalEmote = HelixEmote(id: "425618", name: "LUL", format: ["static"], emoteType: "globals")

        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([globalEmote])
        await store.setUserEmotes([globalEmote])

        let emotes = await store.allEmotes()

        // 検証: 同じIDのグローバルエモートは1件のみ
        let duplicates = emotes.filter { $0.id == "425618" }
        #expect(duplicates.count == 1)
    }

    // MARK: - ユーザーエモート名前逆引き

    @Test("emote(byName:) でユーザーエモートを名前で検索できる")
    func testEmoteByNameFindsUserEmote() async {
        // 前提: ユーザーエモートのみ設定
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub])

        let found = await store.emote(byName: "別チャンネルSub")

        // 検証: ユーザーエモートが名前で検索できる
        #expect(found?.id == "emotesv2_user_sub")
    }

    @Test("emote(byName:) でチャンネルエモートはユーザーエモートより優先される")
    func testEmoteByNamePrefersChannelOverUserEmote() async {
        // 前提: 同名のエモートがチャンネルとユーザー両方に存在
        let channelEmote = HelixEmote(id: "channel_id", name: "重複エモート", format: ["static"], emoteType: "subscriptions")
        let userEmote = HelixEmote(id: "user_id", name: "重複エモート", format: ["static"], emoteType: "subscriptions")

        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setChannelEmotes([channelEmote])
        await store.setUserEmotes([userEmote])

        let found = await store.emote(byName: "重複エモート")

        // 検証: チャンネルエモートが優先される
        #expect(found?.id == "channel_id")
    }

    // MARK: - ユーザーエモートリセット

    @Test("resetUserEmotes でユーザーエモートがクリアされる")
    func testResetUserEmotes() async {
        // 前提: ユーザーエモートを設定した後リセット
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub])

        await store.resetUserEmotes()
        let emotes = await store.allEmotes()

        // 検証: リセット後はユーザーエモートが消える
        #expect(emotes.isEmpty)
    }

    @Test("resetUserEmotes 後に fetchUserEmotes を呼ぶと再取得できる")
    func testFetchUserEmotesAfterReset() async {
        // 前提: フェッチ → リセット → 再フェッチの流れ
        let mockClient = MockHelixAPIClientForEmote(
            stubbedUserEmotesPages: [[.ユーザーエモートBits]]
        )
        let store = EmoteStore(apiClient: mockClient)

        await store.fetchUserEmotes(userId: "123456789")
        await store.resetUserEmotes()

        // リセット後は再フェッチ可能
        await store.fetchUserEmotes(userId: "123456789")
        let emotes = await store.allEmotes()

        #expect(emotes.contains(where: { $0.name == "ビッツ応援エモート" }))
    }

    // MARK: - userEmoteIdSet

    @Test("userEmoteIdSet はユーザーエモートのIDセットを返す")
    func testUserEmoteIdSet() async {
        // 前提: 複数のユーザーエモートを設定
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub, .ユーザーエモートBits])

        let ids = await store.userEmoteIdSet()

        // 検証: 設定したエモートのIDセットが返る
        #expect(ids == Set(["emotesv2_user_sub", "emotesv2_bits_test"]))
    }

    @Test("userEmoteIdSet はユーザーエモートが空の場合に空セットを返す")
    func testUserEmoteIdSetEmpty() async {
        // 前提: ユーザーエモート未設定
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        let ids = await store.userEmoteIdSet()

        #expect(ids.isEmpty)
    }

    // MARK: - userEmotesSnapshot

    @Test("userEmotesSnapshot はユーザーエモートが未設定の場合に空配列を返す")
    func testUserEmotesSnapshotEmpty() async {
        // 前提: ユーザーエモートが設定されていない
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        let snapshot = await store.userEmotesSnapshot()

        // 検証: ユーザーエモート未設定のため空配列
        #expect(snapshot.isEmpty)
    }

    @Test("userEmotesSnapshot は現在のユーザーエモート一覧を返す")
    func testUserEmotesSnapshotReturnsCurrentEmotes() async {
        // 前提: ユーザーエモートを直接設定済み
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub, .ユーザーエモートBits])

        let snapshot = await store.userEmotesSnapshot()

        // 検証: 設定したユーザーエモートが全件返る
        #expect(snapshot.count == 2)
        #expect(snapshot.contains(where: { $0.id == HelixEmote.ユーザーエモート別チャンネルSub.id }))
        #expect(snapshot.contains(where: { $0.id == HelixEmote.ユーザーエモートBits.id }))
    }

    @Test("userEmotesSnapshot は resetUserEmotes 後に空配列を返す")
    func testUserEmotesSnapshotAfterReset() async {
        // 前提: ユーザーエモートを設定してからリセット
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub])
        await store.resetUserEmotes()

        let snapshot = await store.userEmotesSnapshot()

        // 検証: リセット後はスナップショットが空
        #expect(snapshot.isEmpty)
    }

    // MARK: - channelEmotesSnapshot

    @Test("channelEmotesSnapshot は設定済みチャンネルエモートを返す")
    func testChannelEmotesSnapshotReturnsCurrentEmotes() async {
        // 前提: チャンネルエモートを直接設定済み
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setChannelEmotes([.チャンネルエモートHype])

        let snapshot = await store.channelEmotesSnapshot()

        // 検証: 設定したチャンネルエモートが全件返る
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.id == HelixEmote.チャンネルエモートHype.id)
    }

    @Test("channelEmotesSnapshot はチャンネルエモートが未設定の場合に空配列を返す")
    func testChannelEmotesSnapshotEmpty() async {
        // 前提: チャンネルエモートが設定されていない
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        let snapshot = await store.channelEmotesSnapshot()

        // 検証: チャンネルエモート未設定のため空配列
        #expect(snapshot.isEmpty)
    }

    @Test("channelEmotesSnapshot は resetChannelEmotes 後に空配列を返す")
    func testChannelEmotesSnapshotAfterReset() async {
        // 前提: チャンネルエモートを設定してからリセット
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setChannelEmotes([.チャンネルエモートHype])
        await store.resetChannelEmotes()

        let snapshot = await store.channelEmotesSnapshot()

        // 検証: リセット後はスナップショットが空
        #expect(snapshot.isEmpty)
    }

    // MARK: - globalEmotesSnapshot

    @Test("globalEmotesSnapshot は設定済みグローバルエモートを返す")
    func testGlobalEmotesSnapshotReturnsCurrentEmotes() async {
        // 前提: グローバルエモートを直接設定済み
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([.グローバルエモートLUL, .グローバルエモートPogChamp])

        let snapshot = await store.globalEmotesSnapshot()

        // 検証: 設定したグローバルエモートが全件返る
        #expect(snapshot.count == 2)
        #expect(snapshot.contains(where: { $0.id == HelixEmote.グローバルエモートLUL.id }))
        #expect(snapshot.contains(where: { $0.id == HelixEmote.グローバルエモートPogChamp.id }))
    }

    @Test("globalEmotesSnapshot はグローバルエモートが未設定の場合に空配列を返す")
    func testGlobalEmotesSnapshotEmpty() async {
        // 前提: グローバルエモートが設定されていない
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        let snapshot = await store.globalEmotesSnapshot()

        // 検証: グローバルエモート未設定のため空配列
        #expect(snapshot.isEmpty)
    }

    // MARK: - プリロード競合対策

    @Test("isUserEmotesFullyLoaded は初期状態で false を返す")
    func testIsUserEmotesFullyLoadedInitiallyFalse() async {
        // 前提: エモートが設定されていない初期状態
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        // 検証: 初期状態では false
        let loaded = await store.isUserEmotesFullyLoaded()
        #expect(loaded == false)
    }

    @Test("isUserEmotesFullyLoaded は setUserEmotes 後に true を返す")
    func testIsUserEmotesFullyLoadedTrueAfterSetUserEmotes() async {
        // 前提: ユーザーエモートを直接セット（プリロード完了をシミュレート）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmotes([.ユーザーエモート別チャンネルSub])
        // 検証: setUserEmotes 後は fully loaded
        let loaded = await store.isUserEmotesFullyLoaded()
        #expect(loaded == true)
    }

    @Test("seedUserEmotesFromPreload はエモートをセットするが isUserEmotesFullyLoaded フラグを立てない")
    func testSeedUserEmotesFromPreloadDoesNotSetLoadedFlag() async {
        // 前提: プリロード途中のスナップショット（ページ 1 のみ取得済み）をシミュレート
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())

        await store.seedUserEmotesFromPreload([.ユーザーエモート別チャンネルSub])

        // 検証: エモートはセットされているが isUserEmotesLoaded は false のまま
        let snapshot = await store.userEmotesSnapshot()
        let loaded = await store.isUserEmotesFullyLoaded()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.id == HelixEmote.ユーザーエモート別チャンネルSub.id)
        #expect(loaded == false)
    }

    @Test("seedUserEmotesFromPreload 後の fetchUserEmotes は新規フェッチを実行する")
    func testFetchUserEmotesRunsAfterSeedFromPreload() async {
        // 前提: fetchUserEmotes のカウントを計測するモッククライアント
        let counter = FetchCounter()
        let store = EmoteStore(apiClient: CountingMockClient(counter: counter, countedEndpoint: "/emotes/user"))

        // プリロード途中データをシードしてから fetchUserEmotes を呼ぶ
        await store.seedUserEmotesFromPreload([.ユーザーエモート別チャンネルSub])
        await store.fetchUserEmotes(userId: "123456")

        // 検証: fetchUserEmotes が実際に API を呼んだこと（loaded フラグで弾かれていない）
        let count = await counter.value
        #expect(count == 1)
    }

    @Test("setUserEmotes 後の fetchUserEmotes はフェッチをスキップする（最適化パス）")
    func testFetchUserEmotesSkipsAfterSetUserEmotes() async {
        // 前提: プリロード完了済み（setUserEmotes で isLoaded=true）をシミュレート
        let counter = FetchCounter()
        let store = EmoteStore(apiClient: CountingMockClient(counter: counter, countedEndpoint: "/emotes/user"))

        await store.setUserEmotes([.ユーザーエモート別チャンネルSub])
        await store.fetchUserEmotes(userId: "123456")

        // 検証: setUserEmotes 後は fetchUserEmotes が API を呼ばない（isLoaded=true でガード）
        let count = await counter.value
        #expect(count == 0)
    }
}
