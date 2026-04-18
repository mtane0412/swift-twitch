// MentionStoreTests.swift
// MentionStore のユーザー記録・候補フィルタリングのテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("MentionStoreTests")
struct MentionStoreTests {

    // MARK: - recordUser

    @Test("ユーザーを記録すると candidates に追加される")
    @MainActor
    func testRecordUserAddsCandidate() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")

        let result = store.candidates(matching: "")
        #expect(result.count == 1)
        #expect(result[0].username == "ninja")
        #expect(result[0].displayName == "Ninja")
    }

    @Test("同じユーザーを複数回記録しても重複しない")
    @MainActor
    func testRecordUserDeduplicated() {
        let store = MentionStore()

        store.recordUser(username: "shroud", displayName: "shroud")
        store.recordUser(username: "shroud", displayName: "shroud")
        store.recordUser(username: "shroud", displayName: "shroud")

        let result = store.candidates(matching: "")
        #expect(result.count == 1)
    }

    @Test("複数のユーザーを記録できる")
    @MainActor
    func testRecordMultipleUsers() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")
        store.recordUser(username: "shroud", displayName: "shroud")

        let result = store.candidates(matching: "")
        #expect(result.count == 3)
    }

    @Test("最新発言者が先頭に来る順序になる")
    @MainActor
    func testRecentUserComesFirst() {
        let store = MentionStore()

        // 前提: 先に ninja を記録してから pokimane を記録する
        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")

        let result = store.candidates(matching: "")
        // 最後に記録した pokimane が先頭
        #expect(result[0].username == "pokimane")
        #expect(result[1].username == "ninja")
    }

    @Test("既存ユーザーを再度記録すると先頭に移動する")
    @MainActor
    func testRerecordedUserMovesToFront() {
        let store = MentionStore()

        // 前提: ninja → pokimane → shroud の順に記録
        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")
        store.recordUser(username: "shroud", displayName: "shroud")

        // ninja が再発言
        store.recordUser(username: "ninja", displayName: "Ninja")

        let result = store.candidates(matching: "")
        // ninja が先頭に移動している
        #expect(result[0].username == "ninja")
    }

    // MARK: - candidates(matching:)

    @Test("空クエリで全件が返る")
    @MainActor
    func testEmptyQueryReturnsAll() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")

        let result = store.candidates(matching: "")
        #expect(result.count == 2)
    }

    @Test("前方一致でフィルタリングできる")
    @MainActor
    func testPrefixMatchFilter() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")
        store.recordUser(username: "nickmercs", displayName: "NICKMERCS")

        // "ni" で ninja と nickmercs がヒット
        let result = store.candidates(matching: "ni")
        #expect(result.count == 2)
        let usernames = result.map { $0.username }
        #expect(usernames.contains("ninja"))
        #expect(usernames.contains("nickmercs"))
    }

    @Test("フィルタは大文字小文字を区別しない")
    @MainActor
    func testCaseInsensitiveFilter() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")

        // 大文字でも検索できる
        let result = store.candidates(matching: "NIN")
        #expect(result.count == 1)
        #expect(result[0].username == "ninja")
    }

    @Test("displayName でもフィルタリングできる")
    @MainActor
    func testFilterByDisplayName() {
        let store = MentionStore()

        // username: vtuber_jp, displayName: 日本語VTuber
        store.recordUser(username: "vtuber_jp", displayName: "日本語VTuber")
        store.recordUser(username: "englishstreamer", displayName: "EnglishStreamer")

        // displayName で検索
        let result = store.candidates(matching: "日本語")
        #expect(result.count == 1)
        #expect(result[0].username == "vtuber_jp")
    }

    @Test("該当なしの場合は空配列が返る")
    @MainActor
    func testNoMatchReturnsEmpty() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")

        let result = store.candidates(matching: "存在しないユーザー")
        #expect(result.isEmpty)
    }

    @Test("ユーザーが0件の状態でも空配列が返る")
    @MainActor
    func testEmptyStoreReturnsEmpty() {
        let store = MentionStore()

        let result = store.candidates(matching: "")
        #expect(result.isEmpty)
    }
}
