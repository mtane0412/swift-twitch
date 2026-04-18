// EmoteStoreTests.swift
// EmoteStore の取得・フィルタリングロジックテスト

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// HelixAPIClientProtocol のテスト用モック（EmoteStore テスト専用）
///
/// - `shouldThrowAuthError = true` の場合は未ログイン状態をシミュレート
/// - `stubbedEmotes` にエモート配列を設定するとそれを返す
/// - いずれも未設定の場合はサーバーエラーを throw する
struct MockHelixAPIClientForEmote: HelixAPIClientProtocol {
    var shouldThrowAuthError: Bool = false
    var stubbedEmotes: [HelixEmote]?

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        if let emotes = stubbedEmotes, let response = HelixEmotesResponse(data: emotes) as? T {
            return response
        }
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
        // フェッチ回数を Sendable なクラスで安全に計測する
        final class FetchCounter: @unchecked Sendable {
            var value = 0
        }
        let counter = FetchCounter()

        // フェッチ回数をカウントするモック
        struct CountingMockClient: HelixAPIClientProtocol {
            let counter: FetchCounter

            func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
                counter.value += 1
                if let response = HelixEmotesResponse(data: []) as? T {
                    return response
                }
                throw URLError(.badServerResponse)
            }
        }

        let store = EmoteStore(apiClient: CountingMockClient(counter: counter))

        // 2回呼んでも1回しかフェッチしない
        await store.fetchGlobalEmotes()
        await store.fetchGlobalEmotes()

        #expect(counter.value == 1)
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
}
