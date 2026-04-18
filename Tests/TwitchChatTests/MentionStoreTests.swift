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

        // 安全なアクセス: 先に件数を確認してから first で取得する
        let result = store.candidates(matching: "")
        guard let first = result.first else {
            Issue.record("candidates に1件追加されているはずだが、空だった")
            return
        }
        #expect(result.count == 1)
        #expect(first.username == "ninja")
        #expect(first.displayName == "Ninja")
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
        // 配列アクセス前に件数を確認
        #expect(result.count >= 2)
        guard result.count >= 2 else { return }
        // 最後に記録した pokimane が先頭
        #expect(result[0].username == "pokimane")
        #expect(result[1].username == "ninja")
    }

    @Test("既存ユーザーを再度記録すると先頭に移動し、順序全体が正しい")
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
        // 配列アクセス前に件数を確認
        #expect(result.count == 3)
        guard result.count == 3 else { return }
        // ninja が先頭に移動し、残りは記録順が維持される
        #expect(result[0].username == "ninja")
        #expect(result[1].username == "shroud")
        #expect(result[2].username == "pokimane")
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

    @Test("前方一致でフィルタリングできる（非マッチユーザーは除外される）")
    @MainActor
    func testPrefixMatchFilter() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")
        store.recordUser(username: "nickmercs", displayName: "NICKMERCS")

        // "ni" で ninja と nickmercs がヒット。pokimane はヒットしない
        let result = store.candidates(matching: "ni")
        #expect(result.count == 2)
        let usernames = result.map { $0.username }
        #expect(usernames.contains("ninja"))
        #expect(usernames.contains("nickmercs"))
        // 否定チェック: pokimane は除外される
        #expect(!usernames.contains("pokimane"))
    }

    @Test("フィルタは大文字小文字を区別しない")
    @MainActor
    func testCaseInsensitiveFilter() {
        let store = MentionStore()

        store.recordUser(username: "ninja", displayName: "Ninja")

        // 大文字でも検索できる
        let result = store.candidates(matching: "NIN")
        guard let first = result.first else {
            Issue.record("'NIN' で ninja がヒットするはずだが、結果が空だった")
            return
        }
        #expect(result.count == 1)
        #expect(first.username == "ninja")
    }

    @Test("displayName でもフィルタリングできる")
    @MainActor
    func testFilterByDisplayName() {
        let store = MentionStore()

        // username: vtuber_jp, displayName: 日本語VTuber
        store.recordUser(username: "vtuber_jp", displayName: "日本語VTuber")
        store.recordUser(username: "englishstreamer", displayName: "EnglishStreamer")

        // displayName の先頭で検索
        let result = store.candidates(matching: "日本語")
        guard let first = result.first else {
            Issue.record("'日本語' で vtuber_jp がヒットするはずだが、結果が空だった")
            return
        }
        #expect(result.count == 1)
        #expect(first.username == "vtuber_jp")
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

    // MARK: - メモリ上限

    @Test("maxMentionsCount を超えると古いユーザーが削除される")
    @MainActor
    func testMaxMentionsCountTrimsOldUsers() {
        let store = MentionStore()
        let max = MentionStore.maxMentionsCount

        // max 件を超えるユーザーを記録する
        for i in 0..<(max + 10) {
            store.recordUser(username: "user\(i)", displayName: "ユーザー\(i)")
        }

        // 検証: max 件以下に収まっている
        let result = store.candidates(matching: "")
        #expect(result.count == max)
    }

    @Test("上限超過時に最も古いユーザーが削除される")
    @MainActor
    func testOldestUserRemovedWhenExceedingLimit() {
        let store = MentionStore()
        let max = MentionStore.maxMentionsCount

        // "最古ユーザー" を最初に記録する
        store.recordUser(username: "最古ユーザー", displayName: "最古ユーザー表示名")

        // max 件分を追加して上限を超えさせる
        for i in 1..<max {
            store.recordUser(username: "user\(i)", displayName: "ユーザー\(i)")
        }

        // 検証: 最古ユーザーは削除されている（上限に達した後の追加で押し出される）
        // ここで1件追加すると max+1 件になるため最古が削除される
        store.recordUser(username: "追加ユーザー", displayName: "追加ユーザー表示名")

        let result = store.candidates(matching: "最古ユーザー")
        #expect(result.isEmpty, "上限超過により最古ユーザーは削除されているはずだが、まだ存在している")
    }
}
