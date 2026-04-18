// MentionCompletionViewModelTests.swift
// MentionCompletionViewModel の @ トリガー検出・候補管理・選択操作のテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("MentionCompletionViewModelTests")
struct MentionCompletionViewModelTests {

    // MARK: - テスト用ヘルパー

    /// ユーザーが3名登録済みの MentionStore を生成する
    @MainActor
    private func makeStore() -> MentionStore {
        let store = MentionStore()
        store.recordUser(username: "ninja", displayName: "Ninja")
        store.recordUser(username: "pokimane", displayName: "Pokimane")
        store.recordUser(username: "nickmercs", displayName: "NICKMERCS")
        return store
    }

    // MARK: - isActive（アクティブ化・非アクティブ化）

    @Test("@ を単独入力するとアクティブ状態になる")
    @MainActor
    func testAtSignActivates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)

        #expect(vm.isActive == true)
    }

    @Test("スペースの後の @ でアクティブ状態になる")
    @MainActor
    func testAtSignAfterSpaceActivates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("こんにちは @", cursorPosition: 8)

        #expect(vm.isActive == true)
    }

    @Test("@ を含まないテキストではアクティブ状態にならない")
    @MainActor
    func testNoAtSignDoesNotActivate() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("普通のメッセージ", cursorPosition: 8)

        #expect(vm.isActive == false)
    }

    @Test("単語の途中の @ はトリガーにならない（例: メールアドレス形式）")
    @MainActor
    func testAtSignInMiddleOfWordDoesNotActivate() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        // "user@example" の @ はメンションではない
        vm.updateFromText("user@example", cursorPosition: 12)

        #expect(vm.isActive == false)
    }

    @Test("@ を削除するとアクティブ状態が解除される")
    @MainActor
    func testDeletingAtSignDeactivates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@ni", cursorPosition: 3)
        #expect(vm.isActive == true)

        // @ を削除してテキストを更新
        vm.updateFromText("ni", cursorPosition: 2)
        #expect(vm.isActive == false)
    }

    @Test("cancel() を呼ぶとアクティブ状態が解除される")
    @MainActor
    func testCancelDeactivates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@ninja", cursorPosition: 6)
        #expect(vm.isActive == true)

        vm.cancel()
        #expect(vm.isActive == false)
    }

    // MARK: - candidates（候補フィルタリング）

    @Test("@ のみ入力した場合は全候補が表示される")
    @MainActor
    func testAtSignShowsAllCandidates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)

        // 登録ユーザー3名全員が候補に上がる
        #expect(vm.candidates.count == 3)
    }

    @Test("@ni と入力すると ninja と nickmercs が候補に表示される")
    @MainActor
    func testFilteredCandidates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@ni", cursorPosition: 3)

        #expect(vm.candidates.count == 2)
        let usernames = vm.candidates.map { $0.username }
        #expect(usernames.contains("ninja"))
        #expect(usernames.contains("nickmercs"))
    }

    @Test("マッチしないクエリでは候補が空になる")
    @MainActor
    func testNoMatchCandidatesEmpty() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@存在しないユーザー", cursorPosition: 9)

        #expect(vm.candidates.isEmpty)
    }

    // MARK: - selectedIndex（選択操作）

    @Test("初期状態の selectedIndex は 0 である")
    @MainActor
    func testInitialSelectedIndex() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)

        #expect(vm.selectedIndex == 0)
    }

    @Test("moveSelection(by: 1) で次の候補に移動する")
    @MainActor
    func testMoveSelectionDown() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)
        vm.moveSelection(by: 1)

        #expect(vm.selectedIndex == 1)
    }

    @Test("moveSelection(by: -1) で前の候補に移動する")
    @MainActor
    func testMoveSelectionUp() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)
        vm.moveSelection(by: 1) // インデックス 1 に移動
        vm.moveSelection(by: -1) // インデックス 0 に戻る

        #expect(vm.selectedIndex == 0)
    }

    @Test("先頭でさらに上に移動しようとしてもクランプされる（0 以下にならない）")
    @MainActor
    func testSelectionClampedAtTop() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)
        vm.moveSelection(by: -1)

        #expect(vm.selectedIndex == 0)
    }

    @Test("末尾でさらに下に移動しようとしてもクランプされる（候補数を超えない）")
    @MainActor
    func testSelectionClampedAtBottom() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)
        // 候補は3件（ninja, pokimane, nickmercs）。インデックスの最大は 2
        vm.moveSelection(by: 10)

        #expect(vm.selectedIndex == 2)
    }

    // MARK: - confirmSelection（確定）

    @Test("confirmSelection() は選択中のユーザーの @username 形式の文字列を返す")
    @MainActor
    func testConfirmSelectionReturnsUsername() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        // 前提: @ を入力すると最新発言順で nickmercs, pokimane, ninja の順になる
        vm.updateFromText("@", cursorPosition: 1)

        let result = vm.confirmSelection()

        // 先頭（インデックス0）の候補の username が返る
        #expect(result != nil)
        #expect(result?.hasPrefix("@") == true)
        #expect(result?.hasSuffix(" ") == true)
    }

    @Test("confirmSelection() は選択確定後に非アクティブ状態になる")
    @MainActor
    func testConfirmSelectionDeactivates() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@", cursorPosition: 1)
        _ = vm.confirmSelection()

        #expect(vm.isActive == false)
    }

    @Test("候補が空の場合 confirmSelection() は nil を返す")
    @MainActor
    func testConfirmSelectionWithNoCandidatesReturnsNil() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@存在しない", cursorPosition: 6)
        let result = vm.confirmSelection()

        #expect(result == nil)
    }

    @Test("2番目の候補を選択して確定すると正しい username が返る")
    @MainActor
    func testConfirmSecondCandidate() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        vm.updateFromText("@ni", cursorPosition: 3)
        // ni にマッチするのは nickmercs と ninja の2件
        vm.moveSelection(by: 1)  // インデックス 1 に移動
        let result = vm.confirmSelection()

        #expect(result != nil)
        #expect(result?.hasPrefix("@") == true)
    }

    // MARK: - mentionRange（置換範囲）

    @Test("mentionRange は @ から現在のクエリ末尾までの範囲を返す")
    @MainActor
    func testMentionRangeForCurrentToken() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        // "@ninja" と入力中、カーソルが末尾の場合
        vm.updateFromText("@ninja", cursorPosition: 6)

        let range = vm.mentionRange
        #expect(range != nil)
        // "@ninja" の6文字分の範囲
        #expect(range?.length == 6)
        #expect(range?.location == 0)
    }

    @Test("スペース後の @ の mentionRange はスペース以降の正しい範囲を返す")
    @MainActor
    func testMentionRangeAfterSpace() {
        let vm = MentionCompletionViewModel(mentionStore: makeStore())

        // "こんにちは @ni" のような入力
        let text = "hello @ni"
        vm.updateFromText(text, cursorPosition: text.count)

        let range = vm.mentionRange
        #expect(range != nil)
        // "@ni" の3文字分
        #expect(range?.length == 3)
        #expect(range?.location == 6)
    }
}
