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
        // 前提: API がエモートを 0 件返す状態（stubbedEmotes: []）
        // loadEmotes() 内で fetchGlobalEmotes() を await するため stubbedEmotes を設定する
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: エモートが存在しない場合 filteredEmotes は空
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

    // MARK: - isAvailable エモート使用可否判定

    @Test("userEmoteSets が空の場合（USERSTATE 未受信）は全エモートが使用可能")
    @MainActor
    func testIsAvailableWhenUserEmoteSetsEmpty() async {
        // 前提: USERSTATE を受信していない状態（userEmoteSets 空）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setGlobalEmotes([
            HelixEmote(id: "1", name: "LUL", format: ["static"], emoteType: "globals", emoteSetId: "0"),
            HelixEmote(id: "2", name: "サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: USERSTATE 未受信時は全エモートが使用可能
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[0]) == true)
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[1]) == true)
    }

    @Test("グローバルエモート（emoteSetId: '0'）は使用可能セットに含まれる場合 true を返す")
    @MainActor
    func testIsAvailableGlobalEmote() async {
        // 前提: USERSTATE を受信しグローバルセット "0" が含まれている
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmoteSets(Set(["0"]))
        await store.setGlobalEmotes([
            HelixEmote(id: "1", name: "LUL", format: ["static"], emoteType: "globals", emoteSetId: "0")
        ])

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: グローバルエモートは使用可能
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[0]) == true)
    }

    @Test("サブスクエモートのセットIDがユーザーのセットに含まれない場合は false を返す")
    @MainActor
    func testIsAvailableSubscriptionEmoteNotSubscribed() async {
        // 前提: グローバルセット "0" のみ保持している（未サブスク視聴者）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmoteSets(Set(["0"]))
        await store.setChannelEmotes([
            HelixEmote(id: "2", name: "配信者サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: サブスクしていないチャンネルのエモートは使用不可
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[0]) == false)
    }

    @Test("サブスクエモートのセットIDがユーザーのセットに含まれる場合は true を返す")
    @MainActor
    func testIsAvailableSubscriptionEmoteSubscribed() async {
        // 前提: チャンネルのエモートセット "12345" を保持している（サブスク済み視聴者）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmoteSets(Set(["0", "12345"]))
        await store.setChannelEmotes([
            HelixEmote(id: "2", name: "配信者サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: サブスクしているチャンネルのエモートは使用可能
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[0]) == true)
    }

    @Test("emoteSetId が nil のエモートは常に使用可能を返す")
    @MainActor
    func testIsAvailableEmoteWithNilEmoteSetId() async {
        // 前提: emoteSetId が nil のエモート（API レスポンスに emote_set_id が含まれない場合）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote())
        await store.setUserEmoteSets(Set(["0"]))
        await store.setGlobalEmotes([
            HelixEmote(id: "3", name: "emoteSetIdなし", format: ["static"], emoteType: nil, emoteSetId: nil)
        ])

        let viewModel = EmotePickerViewModel(emoteStore: store)
        await viewModel.loadEmotes()

        // 検証: emoteSetId 不明なエモートは安全側に倒して使用可能
        #expect(viewModel.isAvailable(viewModel.filteredEmotes[0]) == true)
    }
}
