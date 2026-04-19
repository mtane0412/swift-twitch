// EmotePickerViewModel.swift
// エモートピッカー用 ViewModel
// EmoteStore からエモート一覧を取得し、チャンネルごとのセクションに分類してフィルタリングする

import Foundation
import Observation

/// エモートピッカー用 ViewModel
///
/// - `loadEmotes()` 呼び出しで EmoteStore から全エモートを取得し、チャンネルごとにセクション分けする
/// - `searchQuery` を変更すると即座に `filteredSections` がフィルタリングされる
/// - フィルタリングは大文字小文字非区別の部分一致（全セクションを横断）
/// - セクション順: このチャンネル → 購読中の他チャンネル（API 取得順）→ HYPE → その他 → グローバル
@Observable
@MainActor
final class EmotePickerViewModel {

    // MARK: - 公開プロパティ

    /// フィルタリング済みセクション一覧（UI へのバインディング用）
    private(set) var filteredSections: [EmotePickerSection] = []

    /// 検索クエリ（空文字の場合は全件表示）
    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            applyFilter()
        }
    }

    // MARK: - プライベートプロパティ

    /// フィルタ前の全セクション一覧
    private var allSections: [EmotePickerSection] = []

    /// エモート定義ストア
    private let emoteStore: EmoteStore

    /// プロフィール画像・表示名ストア（セクションヘッダー用）
    private let profileImageStore: ProfileImageStore

    /// 現在視聴中のチャンネルの broadcaster_id
    private let currentBroadcasterId: String?

    /// ユーザーが使用可能なエモートセット ID のスナップショット
    ///
    /// - `nil`: USERSTATE 未受信（全エモートを使用可能として扱う）
    /// - 空 `Set`: USERSTATE 受信済みだが使用可能セットが空
    private var userEmoteSets: Set<String>?

    /// `/helix/chat/emotes/user` から取得したユーザーエモートの ID セット
    ///
    /// このセットに含まれるエモートは USERSTATE の emoteSetId チェックによらず常に使用可能。
    private var userEmoteIds: Set<String> = []

    // MARK: - 初期化

    /// EmotePickerViewModel を初期化する
    ///
    /// - Parameters:
    ///   - emoteStore: エモート定義ストア
    ///   - profileImageStore: プロフィール画像・表示名ストア
    ///   - currentBroadcasterId: 現在視聴中のチャンネルの broadcaster_id（未接続時は nil）
    init(
        emoteStore: EmoteStore,
        profileImageStore: ProfileImageStore,
        currentBroadcasterId: String?
    ) {
        self.emoteStore = emoteStore
        self.profileImageStore = profileImageStore
        self.currentBroadcasterId = currentBroadcasterId
    }

    // MARK: - 公開メソッド

    /// EmoteStore から全エモートを取得してセクションに分類し、フィルタを適用する
    ///
    /// グローバルエモートのフェッチを待ってからスナップショットを取得することで、
    /// 接続直後にピッカーを開いても「エモートが見つかりません」にならないようにする。
    /// ピッカーが表示されるタイミング（.task モディファイア）で呼び出す。
    func loadEmotes() async {
        await emoteStore.fetchGlobalEmotes()
        let channel = await emoteStore.channelEmotesSnapshot()
        let user    = await emoteStore.userEmotesSnapshot()
        let global  = await emoteStore.globalEmotesSnapshot()
        userEmoteSets = await emoteStore.userAvailableEmoteSets()
        userEmoteIds  = await emoteStore.userEmoteIdSet()

        allSections = buildSections(channel: channel, user: user, global: global)
        applyFilter()
        scheduleOwnerDisplayNameFetch(for: allSections)
    }

    /// ピッカー表示中に USERSTATE が届いた場合にエモートの使用可否をリアルタイムで更新する
    ///
    /// View の `.task` モディファイアから呼び出す。View が消えると `.task` が
    /// このメソッドのタスクをキャンセルし、`waitForNextUserEmoteSetsUpdate` が
    /// resume されてループを抜けるため、Continuation リークは発生しない。
    func observeUserEmoteSetsUpdates() async {
        while !Task.isCancelled {
            await emoteStore.waitForNextUserEmoteSetsUpdate()
            guard !Task.isCancelled else { break }
            userEmoteSets = await emoteStore.userAvailableEmoteSets()
            userEmoteIds  = await emoteStore.userEmoteIdSet()
            // エモート定義が変わった場合のみセクションを再構築（再フィルタコストを抑える）
            let channel = await emoteStore.channelEmotesSnapshot()
            let user    = await emoteStore.userEmotesSnapshot()
            let global  = await emoteStore.globalEmotesSnapshot()
            let newSections = buildSections(channel: channel, user: user, global: global)
            if newSections != allSections {
                allSections = newSections
                // 新規セクションの ownerId に対して表示名・アイコンを解決する
                scheduleOwnerDisplayNameFetch(for: allSections)
            }
            applyFilter()
        }
    }

    /// エモートがユーザーにとって使用可能かどうかを返す
    ///
    /// 判定優先順位:
    /// 1. `/helix/chat/emotes/user` から取得したユーザーエモート ID に含まれる場合は常に true
    /// 2. `userEmoteSets` が `nil`（USERSTATE 未受信）の場合は全て true
    /// 3. `emote.emoteSetId` が nil の場合は安全側に倒して true
    /// 4. それ以外は emoteSetId が userEmoteSets に含まれるか判定する
    ///
    /// - Parameter emote: 判定対象のエモート
    /// - Returns: 使用可能な場合は true
    func isAvailable(_ emote: HelixEmote) -> Bool {
        if userEmoteIds.contains(emote.id) { return true }
        guard let sets = userEmoteSets else { return true }
        guard let emoteSetId = emote.emoteSetId else { return true }
        return sets.contains(emoteSetId)
    }

    // MARK: - プライベートメソッド

    /// セクション内の subscribedChannel / currentChannel の ownerId に対して
    /// ProfileImageStore の表示名・アイコンフェッチを非同期でスケジュールする
    ///
    /// ProfileImageStore は内部でキャッシュ済み ID をスキップするため、
    /// 重複フェッチは発生しない。
    private func scheduleOwnerDisplayNameFetch(for sections: [EmotePickerSection]) {
        let ownerIds = sections.compactMap { section -> String? in
            switch section.kind {
            case .subscribedChannel(let ownerId): return ownerId
            case .currentChannel: return currentBroadcasterId
            default: return nil
            }
        }
        let uniqueOwnerIds = Array(Set(ownerIds))
        guard !uniqueOwnerIds.isEmpty else { return }
        Task { await self.profileImageStore.fetchUsers(userIds: uniqueOwnerIds) }
    }

    /// チャンネル / ユーザー / グローバルエモートからセクション配列を構築する
    ///
    /// - Parameters:
    ///   - channel: チャンネルエモート一覧
    ///   - user: ユーザーエモート一覧
    ///   - global: グローバルエモート一覧
    /// - Returns: 並び順が確定したセクション配列
    private func buildSections(
        channel: [HelixEmote],
        user: [HelixEmote],
        global: [HelixEmote]
    ) -> [EmotePickerSection] {
        var seen = Set<String>()
        let classified = classifyEmotes(channel: channel, user: user, seen: &seen)
        return assembleSections(classified: classified, global: global, seen: &seen)
    }

    /// エモートをセクション種別ごとに分類して中間構造を返す
    ///
    /// 分類ルール（優先順位）:
    /// 1. `emoteType == "hypetrain"` → `hypeTrain` セクション
    /// 2. `ownerId == currentBroadcasterId` → `currentChannel` セクション（channelEmotes 含む）
    /// 3. `ownerId != nil && ownerId != "0"` → `subscribedChannel(ownerId)` セクション（ビッツエモート含む）
    /// 4. それ以外（`ownerId == nil` または `ownerId == "0"` かつ hypetrain 以外）→ global セクションに送る
    ///
    /// - Note: `owner_id: "0"` は Twitch 自身が所有するグローバル系エモートを示すため、
    ///   表示名を解決できないチャンネルセクションを作らず global にまとめる。
    private func classifyEmotes(
        channel: [HelixEmote],
        user: [HelixEmote],
        seen: inout Set<String>
    ) -> (currentChannel: [HelixEmote], hype: [HelixEmote],
          subscribedOwnerIds: [String], subscribedByOwnerId: [String: [HelixEmote]],
          other: [HelixEmote]) {
        var currentChannelEmotes: [HelixEmote] = []
        var hypeEmotes: [HelixEmote] = []
        // ownerId → 出現順を保持するため OrderedDictionary の代わりに配列＋辞書で管理
        var subscribedOwnerIds: [String] = []
        var subscribedByOwnerId: [String: [HelixEmote]] = [:]
        var otherEmotes: [HelixEmote] = []

        for emote in channel where seen.insert(emote.id).inserted {
            currentChannelEmotes.append(emote)
        }
        for emote in user where seen.insert(emote.id).inserted {
            if emote.emoteType == "hypetrain" {
                hypeEmotes.append(emote)
            } else if let ownerId = emote.ownerId, ownerId == currentBroadcasterId {
                currentChannelEmotes.append(emote)
            } else if let ownerId = emote.ownerId, ownerId != "0" {
                if subscribedByOwnerId[ownerId] == nil { subscribedOwnerIds.append(ownerId) }
                subscribedByOwnerId[ownerId, default: []].append(emote)
            } else {
                // ownerId なしエモートは global セクションで処理するため seen から除外する
                // （assembleSections で global スナップショットと合算して dedup する）
                seen.remove(emote.id)
                otherEmotes.append(emote)
            }
        }
        return (currentChannelEmotes, hypeEmotes, subscribedOwnerIds, subscribedByOwnerId, otherEmotes)
    }

    /// 分類済みエモートから EmotePickerSection 配列を組み立てる（空セクションは除外）
    private func assembleSections(
        classified: (currentChannel: [HelixEmote], hype: [HelixEmote],
                     subscribedOwnerIds: [String], subscribedByOwnerId: [String: [HelixEmote]],
                     other: [HelixEmote]),
        global: [HelixEmote],
        seen: inout Set<String>
    ) -> [EmotePickerSection] {
        var sections: [EmotePickerSection] = []

        if !classified.currentChannel.isEmpty {
            sections.append(EmotePickerSection(
                id: "current", kind: .currentChannel, title: "このチャンネル",
                iconUserId: currentBroadcasterId, emotes: classified.currentChannel
            ))
        }
        for ownerId in classified.subscribedOwnerIds {
            let emotes = classified.subscribedByOwnerId[ownerId] ?? []
            guard !emotes.isEmpty else { continue }
            sections.append(EmotePickerSection(
                id: "channel-\(ownerId)", kind: .subscribedChannel(ownerId: ownerId),
                title: profileImageStore.displayName(for: ownerId) ?? ownerId,
                iconUserId: ownerId, emotes: emotes
            ))
        }
        if !classified.hype.isEmpty {
            sections.append(EmotePickerSection(
                id: "hype", kind: .hypeTrain, title: "HYPE", iconUserId: nil, emotes: classified.hype
            ))
        }
        // ownerId なし特殊エモート（リワード・プライム等）は global セクションにまとめて常に末尾に配置する
        let globalEmotes = (classified.other + global).filter { seen.insert($0.id).inserted }
        if !globalEmotes.isEmpty {
            sections.append(EmotePickerSection(
                id: "global", kind: .global, title: "グローバル", iconUserId: nil, emotes: globalEmotes
            ))
        }
        return sections
    }

    /// 現在の searchQuery に基づいて filteredSections を更新する
    ///
    /// - 空クエリの場合は全セクションを返す
    /// - 大文字小文字を区別しない部分一致でエモート名をフィルタする
    /// - ヒットするエモートが 0 件のセクションは除外する
    private func applyFilter() {
        guard !searchQuery.isEmpty else {
            filteredSections = allSections
            return
        }
        filteredSections = allSections.compactMap { section in
            let matched = section.emotes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
            guard !matched.isEmpty else { return nil }
            return EmotePickerSection(
                id: section.id,
                kind: section.kind,
                title: section.title,
                iconUserId: section.iconUserId,
                emotes: matched
            )
        }
    }
}
