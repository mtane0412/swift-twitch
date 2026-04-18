// SlashCommandCompletionViewModelTests.swift
// SlashCommandCompletionViewModel の / トリガー検出・候補管理・選択操作のテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("SlashCommandCompletionViewModelTests")
struct SlashCommandCompletionViewModelTests {

    // MARK: - isActive（アクティブ化・非アクティブ化）

    @Test("/ を単独入力するとアクティブ状態になる")
    @MainActor
    func testSlashAloneActivates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)

        #expect(vm.isActive == true)
    }

    @Test("/ban と入力するとアクティブ状態になる")
    @MainActor
    func testSlashCommandActivates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/ban", cursorPosition: 4)

        #expect(vm.isActive == true)
    }

    @Test("テキスト途中の / はトリガーにならない（例: hello /ban）")
    @MainActor
    func testSlashInMiddleDoesNotActivate() {
        let vm = SlashCommandCompletionViewModel()

        // テキストの先頭でない / はコマンドとして認識しない
        vm.updateFromText("hello /ban", cursorPosition: 10)

        #expect(vm.isActive == false)
    }

    @Test("スラッシュのないテキストではアクティブ状態にならない")
    @MainActor
    func testNoSlashDoesNotActivate() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("普通のメッセージ", cursorPosition: 8)

        #expect(vm.isActive == false)
    }

    @Test("/ の後にスペースが入ると補完が終了する")
    @MainActor
    func testSlashFollowedBySpaceDeactivates() {
        let vm = SlashCommandCompletionViewModel()

        // "/ban " のようにスペースが入った場合は補完終了
        vm.updateFromText("/ban ", cursorPosition: 5)

        #expect(vm.isActive == false)
    }

    @Test("/ を削除するとアクティブ状態が解除される")
    @MainActor
    func testDeletingSlashDeactivates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/ba", cursorPosition: 3)
        #expect(vm.isActive == true)

        // / を削除してテキストを更新
        vm.updateFromText("ba", cursorPosition: 2)
        #expect(vm.isActive == false)
    }

    @Test("cancel() を呼ぶとアクティブ状態が解除される")
    @MainActor
    func testCancelDeactivates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/ban", cursorPosition: 4)
        #expect(vm.isActive == true)

        vm.cancel()
        #expect(vm.isActive == false)
    }

    // MARK: - candidates（候補フィルタリング）

    @Test("/ のみ入力した場合は全コマンドが候補に表示される")
    @MainActor
    func testSlashAloneShowsAllCandidates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)

        #expect(vm.candidates.count == SlashCommandDefinition.allCommands.count)
    }

    @Test("/ba と入力すると ban が候補に表示される")
    @MainActor
    func testFilteredCandidatesBan() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/ba", cursorPosition: 3)

        let names = vm.candidates.map { $0.name }
        #expect(names.contains("ban"))
    }

    @Test("/em と入力すると emoteonly と emoteonlyoff が候補に表示される")
    @MainActor
    func testFilteredCandidatesEmote() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/em", cursorPosition: 3)

        let names = vm.candidates.map { $0.name }
        #expect(names.contains("emoteonly"))
        #expect(names.contains("emoteonlyoff"))
    }

    @Test("マッチしないクエリでは候補が空になる")
    @MainActor
    func testNoMatchCandidatesEmpty() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/存在しないコマンド", cursorPosition: 9)

        #expect(vm.candidates.isEmpty)
    }

    // MARK: - selectedIndex（選択操作）

    @Test("初期状態の selectedIndex は 0 である")
    @MainActor
    func testInitialSelectedIndex() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)

        #expect(vm.selectedIndex == 0)
    }

    @Test("moveSelection(by: 1) で次の候補に移動する")
    @MainActor
    func testMoveSelectionDown() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.moveSelection(by: 1)

        #expect(vm.selectedIndex == 1)
    }

    @Test("moveSelection(by: -1) で前の候補に移動する")
    @MainActor
    func testMoveSelectionUp() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.moveSelection(by: 1) // インデックス 1 に移動
        vm.moveSelection(by: -1) // インデックス 0 に戻る

        #expect(vm.selectedIndex == 0)
    }

    @Test("先頭でさらに上に移動しようとしてもクランプされる（0 以下にならない）")
    @MainActor
    func testSelectionClampedAtTop() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.moveSelection(by: -1)

        #expect(vm.selectedIndex == 0)
    }

    @Test("末尾でさらに下に移動しようとしてもクランプされる（候補数を超えない）")
    @MainActor
    func testSelectionClampedAtBottom() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.moveSelection(by: 1000)

        #expect(vm.selectedIndex == SlashCommandDefinition.allCommands.count - 1)
    }

    @Test("setSelection(to:) で直接インデックスを指定できる")
    @MainActor
    func testSetSelectionDirectly() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.setSelection(to: 2)

        #expect(vm.selectedIndex == 2)
    }

    @Test("setSelection(to:) は範囲外の値をクランプする")
    @MainActor
    func testSetSelectionClamped() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        vm.setSelection(to: 1000)

        #expect(vm.selectedIndex == SlashCommandDefinition.allCommands.count - 1)
    }

    // MARK: - confirmSelection（確定）

    @Test("confirmSelection() は選択中の候補の /command 形式の文字列を返す")
    @MainActor
    func testConfirmSelectionReturnsCommand() {
        let vm = SlashCommandCompletionViewModel()

        // "/me" でフィルタリングしてme コマンドを先頭に
        vm.updateFromText("/me", cursorPosition: 3)
        // me コマンドが先頭（インデックス0）に来るはず
        vm.setSelection(to: 0)

        let result = vm.confirmSelection()

        // 先頭の候補（me）が "/me " の形式で返る
        #expect(result == "/me ")
    }

    @Test("confirmSelection() は選択確定後に非アクティブ状態になる")
    @MainActor
    func testConfirmSelectionDeactivates() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)
        _ = vm.confirmSelection()

        #expect(vm.isActive == false)
    }

    @Test("候補が空の場合 confirmSelection() は nil を返す")
    @MainActor
    func testConfirmSelectionWithNoCandidatesReturnsNil() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/存在しないコマンド", cursorPosition: 9)
        let result = vm.confirmSelection()

        #expect(result == nil)
    }

    @Test("2番目の候補を選択して確定すると正しいコマンドが返る")
    @MainActor
    func testConfirmSecondCandidate() {
        let vm = SlashCommandCompletionViewModel()

        // "/ban" にマッチするコマンドは ban のみ
        vm.updateFromText("/ban", cursorPosition: 4)

        let result = vm.confirmSelection()

        #expect(result == "/ban ")
    }

    // MARK: - commandRange（置換範囲）

    @Test("commandRange は / から現在のクエリ末尾までの範囲を返す")
    @MainActor
    func testCommandRangeForCurrentToken() {
        let vm = SlashCommandCompletionViewModel()

        // "/ban" と入力中、カーソルが末尾の場合
        vm.updateFromText("/ban", cursorPosition: 4)

        let range = vm.commandRange
        #expect(range != nil)
        // "/ban" の4文字分の範囲
        #expect(range?.length == 4)
        #expect(range?.location == 0)
    }

    @Test("/ のみ入力時の commandRange は length が 1 である")
    @MainActor
    func testCommandRangeForSlashOnly() {
        let vm = SlashCommandCompletionViewModel()

        vm.updateFromText("/", cursorPosition: 1)

        let range = vm.commandRange
        #expect(range != nil)
        #expect(range?.length == 1)
        #expect(range?.location == 0)
    }
}
