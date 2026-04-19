// EmotePickerViewModelTests.swift
// EmotePickerViewModel のセクション構築・フィルタリングロジックテスト

import Foundation
import Testing
@testable import TwitchChat

@Suite("EmotePickerViewModelTests")
struct EmotePickerViewModelTests {

    // MARK: - テストヘルパー

    /// テスト用エモートストアと ProfileImageStore を含む環境を生成する
    ///
    /// - Parameter profileImageUsers: ProfileImageStore モックが返すユーザーデータ（subscribedChannel セクションに displayName が必要な場合に指定）
    @MainActor
    private func makeEnvironment(
        channelEmotes: [HelixEmote] = [],
        userEmotes: [HelixEmote] = [],
        globalEmotes: [HelixEmote] = [],
        currentBroadcasterId: String? = nil,
        profileImageUsers: [HelixUserData] = []
    ) async -> (store: EmoteStore, profileImageStore: ProfileImageStore, viewModel: EmotePickerViewModel) {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setChannelEmotes(channelEmotes)
        await store.setUserEmotes(userEmotes)
        await store.setGlobalEmotes(globalEmotes)

        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers(profileImageUsers)
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: currentBroadcasterId
        )
        return (store, profileImageStore, viewModel)
    }

    // MARK: - loadEmotes / セクション構築

    @Test("loadEmotes はセクション構築前にオーナーIDの表示名をフェッチしてセクションタイトルに反映する")
    @MainActor
    func testLoadEmotesPrefetchesDisplayNames() async {
        // 前提: ownerId "12345" を持つユーザーエモート、モック API が displayName "テストチャンネル" を返す
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            HelixUserData(id: "12345", login: "test_ch", displayName: "テストチャンネル", profileImageUrl: nil)
        ])
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setUserEmotes([
            HelixEmote(id: "emote1", name: "testEmote", format: ["static"], emoteType: "subscriptions", emoteSetId: "999", ownerId: "12345")
        ])
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )

        await viewModel.loadEmotes()

        // 検証: subscribedChannel セクションのタイトルが ownerId でなく displayName になっている
        let subscribedSection = viewModel.filteredSections.first { $0.kind == .subscribedChannel(ownerId: "12345") }
        #expect(subscribedSection?.title == "テストチャンネル")
    }

    @Test("エモートセット更新後にセクションタイトルが displayName に更新される")
    @MainActor
    func testRefreshSectionsUpdatesDisplayNamesOnEmoteSetUpdate() async throws {
        // 前提: ownerId "99999" を持つユーザーエモート、モック API が displayName "更新チャンネル" を返す
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            HelixUserData(id: "99999", login: "update_ch", displayName: "更新チャンネル", profileImageUrl: nil)
        ])
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )

        // 初回ロード（ユーザーエモートなし）
        await viewModel.loadEmotes()
        #expect(viewModel.filteredSections.isEmpty)

        // observer タスクを開始し、waitForNextUserEmoteSetsUpdate() に到達するまで yield する
        let observeTask = Task { await viewModel.observeUserEmoteSetsUpdates() }
        for _ in 0..<5 { await Task.yield() }

        // エモートセット更新をシミュレート（新たにユーザーエモートが追加される）
        await store.setUserEmotes([
            HelixEmote(id: "new_emote", name: "newEmote", format: ["static"], emoteType: "subscriptions", emoteSetId: "888", ownerId: "99999")
        ])
        await store.notifyUserEmoteSetsUpdatedForTest()

        // 更新処理（refreshSections + displayName fetch）が完了するまで待つ
        try await Task.sleep(for: .milliseconds(100))
        observeTask.cancel()

        // 検証: 新しい subscribedChannel セクションが displayName で表示される
        let subscribedSection = viewModel.filteredSections.first { $0.kind == .subscribedChannel(ownerId: "99999") }
        #expect(subscribedSection?.title == "更新チャンネル")
    }

    @Test("USERSTATE のみ更新されてもセクションは再構築されない（エモートデータが変わっていない場合）")
    @MainActor
    func testUserStateOnlyUpdateDoesNotRebuildSections() async throws {
        // 前提: subscribedChannel セクションが 1 つある状態（ownerId "11111" の displayName を設定）
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            HelixUserData(id: "11111", login: "sub_ch", displayName: "サブチャンネル11111", profileImageUrl: nil)
        ])
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )
        await store.setUserEmotes([
            HelixEmote(id: "sub1", name: "Sub1", format: ["static"], emoteType: "subscriptions", emoteSetId: "111", ownerId: "11111")
        ])
        await viewModel.loadEmotes()
        let initialSectionCount = viewModel.filteredSections.count

        // observer 起動して待機状態にする
        let observeTask = Task { await viewModel.observeUserEmoteSetsUpdates() }
        for _ in 0..<5 { await Task.yield() }

        // USERSTATE のみ更新（エモートデータは変えずに userEmoteSets を更新）
        await store.updateUserEmoteSets(Set(["111"]))
        try await Task.sleep(for: .milliseconds(50))
        observeTask.cancel()

        // 検証: セクション数に変化なし（再構築されていない）、可用性判定には反映されている
        #expect(viewModel.filteredSections.count == initialSectionCount)
    }

    @Test("ユーザーエモートが増えた場合はセクションが再構築されて displayName が反映される")
    @MainActor
    func testUserEmoteIncreaseRebuildsSectionsWithDisplayName() async throws {
        // 前提: 初回は空
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            HelixUserData(id: "22222", login: "new_ch", displayName: "新しいチャンネル", profileImageUrl: nil)
        ])
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )
        await viewModel.loadEmotes()
        #expect(viewModel.filteredSections.isEmpty)

        // observer 起動
        let observeTask = Task { await viewModel.observeUserEmoteSetsUpdates() }
        for _ in 0..<5 { await Task.yield() }

        // ユーザーエモートを追加（count が増える）
        await store.setUserEmotes([
            HelixEmote(id: "new1", name: "New1", format: ["static"], emoteType: "subscriptions", emoteSetId: "222", ownerId: "22222")
        ])
        await store.notifyUserEmoteSetsUpdatedForTest()
        try await Task.sleep(for: .milliseconds(100))
        observeTask.cancel()

        // 検証: セクションが追加され displayName が正しく設定されている
        let section = viewModel.filteredSections.first { $0.kind == .subscribedChannel(ownerId: "22222") }
        #expect(section?.title == "新しいチャンネル")
    }

    @Test("並行する古い refreshSections が新しい refreshSections の結果を上書きしない")
    @MainActor
    func testStaleRefreshDoesNotOverwriteNewerResult() async throws {
        // 前提: 初回は空、その後エモートが追加される
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        let mockClient = MockProfileImageAPIClient()
        // ownerId "77777" の displayName を設定して subscribedChannel セクションが作られるようにする
        await mockClient.setUsers([
            HelixUserData(id: "77777", login: "レースチャンネル", displayName: "レースチャンネル", profileImageUrl: nil)
        ])
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )

        // observer タスクを先に起動して待機状態にする
        let observeTask = Task { await viewModel.observeUserEmoteSetsUpdates() }
        for _ in 0..<5 { await Task.yield() }

        // ユーザーエモートを追加して通知（observer が新しいスナップショットで sections を構築）
        await store.setUserEmotes([
            HelixEmote(id: "race_emote", name: "raceEmote", format: ["static"], emoteType: "subscriptions", emoteSetId: "777", ownerId: "77777")
        ])
        await store.notifyUserEmoteSetsUpdatedForTest()

        // loadEmotes も並行して呼ぶ（古いスナップショットで sections を上書きしようとする）
        await viewModel.loadEmotes()

        // 更新が落ち着くまで待つ
        try await Task.sleep(for: .milliseconds(100))
        observeTask.cancel()

        // 検証: subscribedChannel セクションが消えていない（古いスナップショットで上書きされていない）
        let hasSubscribedSection = viewModel.filteredSections.contains { $0.kind == .subscribedChannel(ownerId: "77777") }
        #expect(hasSubscribedSection)
    }

    @Test("グローバルエモートのみのとき global セクションだけが返る")
    @MainActor
    func testLoadEmotesGlobalOnly() async {
        // 前提: グローバルエモートが 2 件のみ
        let (_, _, viewModel) = await makeEnvironment(
            globalEmotes: [.グローバルエモートLUL, .グローバルエモートPogChamp]
        )

        await viewModel.loadEmotes()

        // 検証: global セクション 1 つ、エモート 2 件
        #expect(viewModel.filteredSections.count == 1)
        #expect(viewModel.filteredSections.first?.kind == .global)
        #expect(viewModel.filteredSections.first?.emotes.count == 2)
    }

    @Test("エモートが空の場合は filteredSections も空になる")
    @MainActor
    func testLoadEmotesEmpty() async {
        // 前提: すべてのエモートが空
        let (_, _, viewModel) = await makeEnvironment()

        await viewModel.loadEmotes()

        // 検証: セクションが空
        #expect(viewModel.filteredSections.isEmpty)
    }

    @Test("currentBroadcasterId 指定時にチャンネルエモートが currentChannel セクションに入る")
    @MainActor
    func testLoadEmotesChannelEmotesInCurrentChannelSection() async {
        // 前提: currentBroadcasterId 設定済み・チャンネルエモートあり
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            globalEmotes: [.グローバルエモートLUL],
            currentBroadcasterId: "123456"
        )

        await viewModel.loadEmotes()

        // 検証: currentChannel セクションにチャンネルエモートが入る
        let currentSection = viewModel.filteredSections.first(where: { $0.kind == .currentChannel })
        #expect(currentSection != nil)
        #expect(currentSection?.emotes.contains(where: { $0.id == HelixEmote.チャンネルエモートHype.id }) == true)
    }

    @Test("ownerId が currentBroadcasterId と一致するユーザーエモートは currentChannel セクションに合流する")
    @MainActor
    func testUserEmotesWithMatchingOwnerIdMergeIntoCurrentChannel() async {
        // 前提: ユーザーエモートの ownerId が現在のチャンネルと同じ
        let currentBroadcasterId = "777777"
        let channelUserEmote = HelixEmote(
            id: "user_ch_emote",
            name: "チャンネルユーザーエモート",
            format: ["static"],
            emoteType: "subscriptions",
            emoteSetId: "77777",
            ownerId: currentBroadcasterId
        )
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            userEmotes: [channelUserEmote],
            currentBroadcasterId: currentBroadcasterId
        )

        await viewModel.loadEmotes()

        // 検証: currentChannel セクションに両方のエモートが含まれ、他にチャンネルセクションはない
        let currentSection = viewModel.filteredSections.first(where: { $0.kind == .currentChannel })
        #expect(currentSection?.emotes.contains(where: { $0.id == HelixEmote.チャンネルエモートHype.id }) == true)
        #expect(currentSection?.emotes.contains(where: { $0.id == channelUserEmote.id }) == true)

        // subscribedChannel セクションは生成されないこと
        let subChannelSections = viewModel.filteredSections.filter {
            if case .subscribedChannel = $0.kind { return true }
            return false
        }
        #expect(subChannelSections.isEmpty)
    }

    @Test("異なる ownerId の複数ユーザーエモートはそれぞれ subscribedChannel セクションに分類される")
    @MainActor
    func testUserEmotesGroupedByOwnerId() async {
        // 前提: 3 つの異なるチャンネルのユーザーエモート
        let emoteA1 = HelixEmote(id: "a1", name: "チャンネルAエモート1", format: ["static"], emoteType: "subscriptions", emoteSetId: "1", ownerId: "aaaa")
        let emoteA2 = HelixEmote(id: "a2", name: "チャンネルAエモート2", format: ["static"], emoteType: "subscriptions", emoteSetId: "1", ownerId: "aaaa")
        let emoteB1 = HelixEmote(id: "b1", name: "チャンネルBエモート1", format: ["static"], emoteType: "subscriptions", emoteSetId: "2", ownerId: "bbbb")
        let (_, _, viewModel) = await makeEnvironment(
            userEmotes: [emoteA1, emoteA2, emoteB1],
            profileImageUsers: [
                HelixUserData(id: "aaaa", login: "channel_a", displayName: "チャンネルA", profileImageUrl: nil),
                HelixUserData(id: "bbbb", login: "channel_b", displayName: "チャンネルB", profileImageUrl: nil)
            ]
        )

        await viewModel.loadEmotes()

        // 検証: チャンネル A と B で 2 つの subscribedChannel セクションが生成される
        let subChannelSections = viewModel.filteredSections.filter {
            if case .subscribedChannel = $0.kind { return true }
            return false
        }
        #expect(subChannelSections.count == 2)

        let sectionA = subChannelSections.first(where: {
            if case .subscribedChannel(let id) = $0.kind { return id == "aaaa" }
            return false
        })
        #expect(sectionA?.emotes.count == 2)

        let sectionB = subChannelSections.first(where: {
            if case .subscribedChannel(let id) = $0.kind { return id == "bbbb" }
            return false
        })
        #expect(sectionB?.emotes.count == 1)
    }

    @Test("emoteType が hypetrain のエモートは hypeTrain セクションに分類される")
    @MainActor
    func testHypeTrainEmotesGoToHypeTrainSection() async {
        // 前提: ハイプトレインエモートが含まれる
        let hypeEmote = HelixEmote(
            id: "hype_1",
            name: "ハイプトレインエモート",
            format: ["static"],
            emoteType: "hypetrain",
            ownerId: "some_channel"
        )
        let (_, _, viewModel) = await makeEnvironment(
            userEmotes: [hypeEmote, .ユーザーエモート別チャンネルSub]
        )

        await viewModel.loadEmotes()

        // 検証: hypeTrain セクションにハイプトレインエモートが入る
        let hypeSection = viewModel.filteredSections.first(where: { $0.kind == .hypeTrain })
        #expect(hypeSection != nil)
        #expect(hypeSection?.emotes.contains(where: { $0.id == hypeEmote.id }) == true)

        // subscribedChannel セクションにハイプトレインエモートは含まれない
        let subSections = viewModel.filteredSections.filter {
            if case .subscribedChannel = $0.kind { return true }
            return false
        }
        #expect(subSections.allSatisfy { !$0.emotes.contains(where: { $0.id == hypeEmote.id }) })
    }

    @Test("ownerId が nil かつ hypetrain でないエモートは global セクションにまとめられる")
    @MainActor
    func testEmotesWithNilOwnerIdGoToGlobalSection() async {
        // 前提: ownerId なしのエモート（リワード等）
        let rewardEmote = HelixEmote(
            id: "reward_1",
            name: "チャンネルポイントエモート",
            format: ["static"],
            emoteType: "rewards",
            ownerId: nil
        )
        let (_, _, viewModel) = await makeEnvironment(userEmotes: [rewardEmote])

        await viewModel.loadEmotes()

        // 検証: global セクションに ownerId なしエモートがまとめられる（other セクションは生成されない）
        let globalSection = viewModel.filteredSections.first(where: { $0.kind == .global })
        #expect(globalSection != nil)
        #expect(globalSection?.emotes.contains(where: { $0.id == rewardEmote.id }) == true)
        #expect(viewModel.filteredSections.count == 1)
    }

    @Test("セクションの並び順は currentChannel → subscribedChannel → hypeTrain → global")
    @MainActor
    func testSectionOrdering() async {
        // 前提: 全種類のセクションが生成される組み合わせ
        let currentBroadcasterId = "111"
        let hypeEmote = HelixEmote(id: "hype_1", name: "ハイプ1", format: ["static"], emoteType: "hypetrain", ownerId: "hype_ch")
        let rewardEmote = HelixEmote(id: "reward_1", name: "リワード1", format: ["static"], emoteType: "rewards", ownerId: nil)
        let subEmote = HelixEmote(id: "sub_1", name: "サブ1", format: ["static"], emoteType: "subscriptions", emoteSetId: "s1", ownerId: "222")
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            userEmotes: [hypeEmote, rewardEmote, subEmote],
            globalEmotes: [.グローバルエモートLUL],
            currentBroadcasterId: currentBroadcasterId,
            profileImageUsers: [
                HelixUserData(id: "222", login: "sub_channel", displayName: "サブチャンネル", profileImageUrl: nil)
            ]
        )

        await viewModel.loadEmotes()

        // 検証: セクションが正しい順序で並ぶ（currentChannel → subscribedChannel → hypeTrain → global）
        // ownerId なしエモートは global セクションにまとめられる
        let kinds = viewModel.filteredSections.map(\.kind)
        guard kinds.count == 4 else {
            Issue.record("セクション数が期待値と異なります（期待: 4, 実際: \(kinds.count)）")
            return
        }
        #expect(kinds[0] == .currentChannel)
        if case .subscribedChannel = kinds[1] { } else {
            Issue.record("2番目のセクションが subscribedChannel ではありません: \(kinds[1])")
        }
        #expect(kinds[2] == .hypeTrain)
        #expect(kinds[3] == .global)
    }

    @Test("同じ ID のエモートはセクション間で重複しない")
    @MainActor
    func testNoDuplicatesAcrossSections() async {
        // 前提: channelEmotes と userEmotes に同じ ID のエモートが含まれる
        let duplicateEmote = HelixEmote(
            id: "dup_emote",
            name: "重複エモート",
            format: ["static"],
            emoteType: "subscriptions",
            emoteSetId: "1234",
            ownerId: "other_channel"
        )
        let channelDuplicate = HelixEmote(
            id: "dup_emote",  // 同じ ID
            name: "重複エモート",
            format: ["static"],
            emoteType: "subscriptions"
        )
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [channelDuplicate],
            userEmotes: [duplicateEmote],
            currentBroadcasterId: "999"
        )

        await viewModel.loadEmotes()

        // 検証: 全セクションを通じてエモートIDが重複しない
        let allEmoteIds = viewModel.filteredSections.flatMap(\.emotes).map(\.id)
        let uniqueIds = Set(allEmoteIds)
        #expect(allEmoteIds.count == uniqueIds.count)
    }

    // MARK: - searchQuery フィルタリング

    @Test("searchQuery を設定するとすべてのセクションを横断的に絞り込める")
    @MainActor
    func testSearchQueryFiltersAcrossSections() async {
        // 前提: チャンネルエモートとグローバルエモートが混在
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            globalEmotes: [.グローバルエモートLUL, .グローバルエモートPogChamp],
            currentBroadcasterId: "111"
        )
        await viewModel.loadEmotes()

        // "LUL" で検索するとグローバルセクションのみ残る
        viewModel.searchQuery = "LUL"

        #expect(viewModel.filteredSections.count == 1)
        #expect(viewModel.filteredSections.first?.kind == .global)
        #expect(viewModel.filteredSections.first?.emotes.count == 1)
    }

    @Test("searchQuery が大文字小文字を区別しない")
    @MainActor
    func testSearchQueryCaseInsensitive() async {
        let (_, _, viewModel) = await makeEnvironment(
            globalEmotes: [.グローバルエモートLUL]
        )
        await viewModel.loadEmotes()

        // 小文字の "lul" でも "LUL" がヒットする
        viewModel.searchQuery = "lul"

        #expect(viewModel.filteredSections.count == 1)
        #expect(viewModel.filteredSections.first?.emotes.first?.name == "LUL")
    }

    @Test("searchQuery を空文字にすると全セクションに戻る")
    @MainActor
    func testClearSearchQueryReturnsAllSections() async {
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            globalEmotes: [.グローバルエモートLUL],
            currentBroadcasterId: "111"
        )
        await viewModel.loadEmotes()

        viewModel.searchQuery = "LUL"
        #expect(viewModel.filteredSections.count == 1)

        viewModel.searchQuery = ""
        #expect(viewModel.filteredSections.count == 2)
    }

    @Test("マッチしない searchQuery では filteredSections が空になる")
    @MainActor
    func testSearchQueryNoMatch() async {
        let (_, _, viewModel) = await makeEnvironment(
            globalEmotes: [.グローバルエモートLUL]
        )
        await viewModel.loadEmotes()

        viewModel.searchQuery = "存在しないエモート名"

        #expect(viewModel.filteredSections.isEmpty)
    }

    @Test("searchQuery でヒットしたエモートがないセクションは除外される")
    @MainActor
    func testEmptySectionsAreExcludedFromFilter() async {
        // 前提: チャンネルセクションと global セクション
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            globalEmotes: [.グローバルエモートLUL],
            currentBroadcasterId: "111"
        )
        await viewModel.loadEmotes()

        // "配信者" で検索するとチャンネルエモートのみヒット
        viewModel.searchQuery = "配信者"

        // 検証: global セクションは除外される
        #expect(viewModel.filteredSections.count == 1)
        #expect(viewModel.filteredSections.first?.kind == .currentChannel)
    }

    @Test("日本語のエモート名でも検索できる")
    @MainActor
    func testSearchQueryWithJapanese() async {
        let (_, _, viewModel) = await makeEnvironment(
            channelEmotes: [.チャンネルエモートHype],
            currentBroadcasterId: "111"
        )
        await viewModel.loadEmotes()

        viewModel.searchQuery = "配信者"

        #expect(viewModel.filteredSections.count == 1)
        #expect(viewModel.filteredSections.first?.emotes.first?.name == HelixEmote.チャンネルエモートHype.name)
    }

    // MARK: - isAvailable エモート使用可否判定

    @Test("userEmoteSets が nil の場合（USERSTATE 未受信）は全エモートが使用可能")
    @MainActor
    func testIsAvailableWhenUserEmoteSetsNil() async {
        // 前提: USERSTATE を受信していない状態
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setGlobalEmotes([
            HelixEmote(id: "1", name: "LUL", format: ["static"], emoteType: "globals", emoteSetId: "0"),
            HelixEmote(id: "2", name: "サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        // 検証: USERSTATE 未受信のため全エモートが使用可能
        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        #expect(allEmotes.allSatisfy { viewModel.isAvailable($0) })
    }

    @Test("グローバルエモート（emoteSetId: '0'）は使用可能セットに含まれる場合 true を返す")
    @MainActor
    func testIsAvailableGlobalEmote() async {
        // 前提: USERSTATE でグローバルセット "0" が含まれている
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setUserEmoteSets(Set(["0"]))
        await store.setGlobalEmotes([
            HelixEmote(id: "1", name: "LUL", format: ["static"], emoteType: "globals", emoteSetId: "0")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let globalSection = viewModel.filteredSections.first(where: { $0.kind == .global })
        let lul = globalSection?.emotes.first
        #expect(lul.map { viewModel.isAvailable($0) } == true)
    }

    @Test("サブスクエモートのセットIDがユーザーのセットに含まれない場合は false を返す")
    @MainActor
    func testIsAvailableSubscriptionEmoteNotSubscribed() async {
        // 前提: グローバルセット "0" のみ保持（未サブスク視聴者）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setGlobalEmotes([])
        await store.setUserEmoteSets(Set(["0"]))
        await store.setChannelEmotes([
            HelixEmote(id: "2", name: "配信者サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        let subEmote = allEmotes.first(where: { $0.name == "配信者サブスクエモート" })
        #expect(subEmote.map { viewModel.isAvailable($0) } == false)
    }

    @Test("サブスクエモートのセットIDがユーザーのセットに含まれる場合は true を返す")
    @MainActor
    func testIsAvailableSubscriptionEmoteSubscribed() async {
        // 前提: チャンネルのエモートセット "12345" を保持（サブスク済み視聴者）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setGlobalEmotes([])
        await store.setUserEmoteSets(Set(["0", "12345"]))
        await store.setChannelEmotes([
            HelixEmote(id: "2", name: "配信者サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "12345")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        let subEmote = allEmotes.first(where: { $0.name == "配信者サブスクエモート" })
        #expect(subEmote.map { viewModel.isAvailable($0) } == true)
    }

    @Test("emoteSetId が nil のエモートは常に使用可能を返す")
    @MainActor
    func testIsAvailableEmoteWithNilEmoteSetId() async {
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setUserEmoteSets(Set(["0"]))
        await store.setGlobalEmotes([
            HelixEmote(id: "3", name: "emoteSetIdなし", format: ["static"], emoteType: nil, emoteSetId: nil)
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        let emote = allEmotes.first(where: { $0.name == "emoteSetIdなし" })
        #expect(emote.map { viewModel.isAvailable($0) } == true)
    }

    @Test("ユーザーエモートは emoteSetId が userEmoteSets に含まれなくても常に使用可能")
    @MainActor
    func testUserEmoteIsAlwaysAvailable() async throws {
        // 前提: USERSTATE はグローバルセット "0" のみ、/helix/chat/emotes/user から取得済み
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setGlobalEmotes([])
        await store.setUserEmoteSets(Set(["0"]))
        await store.setUserEmotes([
            HelixEmote(id: "user_sub_1", name: "別チャンネルSub", format: ["static"], emoteType: "subscriptions", emoteSetId: "999999", ownerId: "other")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        let targetEmote = try #require(
            allEmotes.first(where: { $0.name == "別チャンネルSub" }),
            "テスト対象エモートが filteredSections に見つかりません"
        )
        // 検証: userEmoteIds に含まれるため使用可能
        #expect(viewModel.isAvailable(targetEmote) == true)
    }

    @Test("ユーザーエモートでないチャンネルエモートは従来通り emoteSetId で判定する")
    @MainActor
    func testNonUserEmoteUsesEmoteSetIdCheck() async throws {
        // 前提: チャンネルエモートだが userEmotes に含まれていない（未サブスク）
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setGlobalEmotes([])
        await store.setUserEmoteSets(Set(["0"]))
        await store.setChannelEmotes([
            HelixEmote(id: "ch_unsub", name: "未サブスクエモート", format: ["static"], emoteType: "subscriptions", emoteSetId: "55555")
        ])
        let profileImageStore = ProfileImageStore(apiClient: MockProfileImageAPIClient())
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil,
        )

        await viewModel.loadEmotes()

        let allEmotes = viewModel.filteredSections.flatMap(\.emotes)
        let targetEmote = try #require(
            allEmotes.first(where: { $0.name == "未サブスクエモート" }),
            "テスト対象エモートが filteredSections に見つかりません"
        )
        // 検証: ユーザーエモートでないためemoteSetId チェックが適用される
        #expect(viewModel.isAvailable(targetEmote) == false)
    }

    // MARK: - ownerId の異常値ハンドリング

    @Test("ownerId が空文字のユーザーエモートは global セクションに分類され subscribedChannel セクションは作成されない")
    @MainActor
    func testEmptyOwnerIdEmoteGoesToGlobalSection() async {
        // 前提: ownerId が空文字（Twitch API が "" を返す場合）のエモート
        let emptyOwnerEmote = HelixEmote(
            id: "emote_empty_owner",
            name: "空オーナーエモート",
            format: ["static"],
            emoteType: "subscriptions",
            emoteSetId: "999",
            ownerId: ""
        )
        let (_, _, viewModel) = await makeEnvironment(userEmotes: [emptyOwnerEmote])

        await viewModel.loadEmotes()

        // 検証: subscribedChannel セクションが作成されないこと（空文字 ownerId で named section を作らない）
        let subscribedSection = viewModel.filteredSections.first {
            if case .subscribedChannel = $0.kind { return true }
            return false
        }
        #expect(subscribedSection == nil)

        // 検証: emote が global セクションに含まれること
        let globalSection = viewModel.filteredSections.first(where: { $0.kind == .global })
        #expect(globalSection?.emotes.contains(where: { $0.id == emptyOwnerEmote.id }) == true)
    }

    @Test("API にユーザーが存在しない ownerId のエモートは global セクションに分類される（数字 ID のセクションを作らない）")
    @MainActor
    func testUnresolvableOwnerIdGoesToGlobalSection() async {
        // 前提: ownerId "784555479" を持つエモート、モック API がユーザーを返さない
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([]) // API はユーザーを返さない（存在しない broadcaster ID）

        // stubbedEmotes: [] でグローバルエモートエンドポイントが空配列を返すように設定
        let store = EmoteStore(apiClient: MockHelixAPIClientForEmote(stubbedEmotes: []))
        await store.setUserEmotes([
            HelixEmote(
                id: "emote_unknown_owner",
                name: "不明オーナーエモート",
                format: ["static"],
                emoteType: "subscriptions",
                emoteSetId: "777",
                ownerId: "784555479"
            )
        ])
        let profileImageStore = ProfileImageStore(apiClient: mockClient)
        let viewModel = EmotePickerViewModel(
            emoteStore: store,
            profileImageStore: profileImageStore,
            currentBroadcasterId: nil
        )

        await viewModel.loadEmotes()

        // 検証: subscribedChannel セクションが作成されないこと
        let subscribedSection = viewModel.filteredSections.first {
            if case .subscribedChannel = $0.kind { return true }
            return false
        }
        #expect(subscribedSection == nil)

        // 検証: emote が global セクションに含まれること（数字 ID のセクションに隔離されない）
        let globalSection = viewModel.filteredSections.first(where: { $0.kind == .global })
        #expect(globalSection?.emotes.contains(where: { $0.id == "emote_unknown_owner" }) == true)
    }
}
