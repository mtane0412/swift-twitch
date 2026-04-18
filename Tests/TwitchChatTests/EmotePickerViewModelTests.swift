// EmotePickerViewModelTests.swift
// EmotePickerViewModel のフィルタリングロジックテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("EmotePickerViewModelTests")
struct EmotePickerViewModelTests {

    // MARK: - テスト用エモートデータ

    /// テスト用エモートセット（3件）
    private func makeTestEmotes() -> [HelixEmote] {
        [
            HelixEmote(id: "1", name: "LUL",        format: ["static", "animated"], emoteType: "globals"),
            HelixEmote(id: "2", name: "PogChamp",    format: ["static"],             emoteType: "globals"),
            HelixEmote(id: "3", name: "配信者エモート", format: ["static"],             emoteType: "subscriptions")
        ]
    }

    // MARK: - loadEmotes

    @Test("loadEmotes を呼ぶと全件が filteredEmotes に反映される")
    @MainActor
    func testLoadEmotesSetsAllEmotes() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        #expect(viewModel.filteredEmotes.count == 3)
    }

    @Test("エモートが空の場合は filteredEmotes も空になる")
    @MainActor
    func testLoadEmotesEmpty() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        #expect(viewModel.filteredEmotes.isEmpty)
    }

    // MARK: - searchQuery フィルタリング

    @Test("searchQuery を設定すると名前で絞り込まれる")
    @MainActor
    func testSearchQueryFiltersEmotes() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // "Pog" で検索すると PogChamp のみ返る
        viewModel.searchQuery = "Pog"

        #expect(viewModel.filteredEmotes.count == 1)
        #expect(viewModel.filteredEmotes.first?.name == "PogChamp")
    }

    @Test("searchQuery が大文字小文字を区別しない")
    @MainActor
    func testSearchQueryCaseInsensitive() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 小文字の "lul" でも "LUL" がヒットする
        viewModel.searchQuery = "lul"

        #expect(viewModel.filteredEmotes.count == 1)
        #expect(viewModel.filteredEmotes.first?.name == "LUL")
    }

    @Test("searchQuery を空文字にすると全件に戻る")
    @MainActor
    func testClearSearchQueryReturnsAllEmotes() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 絞り込んだあと空にすると全件に戻る
        viewModel.searchQuery = "LUL"
        #expect(viewModel.filteredEmotes.count == 1)

        viewModel.searchQuery = ""
        #expect(viewModel.filteredEmotes.count == 3)
    }

    @Test("日本語のエモート名でも検索できる")
    @MainActor
    func testSearchQueryWithJapanese() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        viewModel.searchQuery = "配信者"

        #expect(viewModel.filteredEmotes.count == 1)
        #expect(viewModel.filteredEmotes.first?.name == "配信者エモート")
    }

    @Test("マッチしない searchQuery では filteredEmotes が空になる")
    @MainActor
    func testSearchQueryNoMatch() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes(makeTestEmotes())

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        viewModel.searchQuery = "存在しないエモート名"

        #expect(viewModel.filteredEmotes.isEmpty)
    }
}
