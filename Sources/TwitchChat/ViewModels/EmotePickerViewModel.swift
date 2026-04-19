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

    /// 最後にセクションを構築したときのチャンネルエモート ID セット
    ///
    /// `observeUserEmoteSetsUpdates()` がエモートデータの変化を検知するために使用する。
    /// USERSTATE のみの更新ではセクションを再構築しない最適化に使う。
    private var lastBuiltChannelIds: Set<String> = []

    /// 最後にセクションを構築したときのユーザーエモート ID セット
    private var lastBuiltUserIds: Set<String> = []

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
        await refreshSections()
    }

    /// ピッカー表示中にエモートセット更新を監視し、変化に応じてセクションを更新する
    ///
    /// エモートデータ（チャンネル・ユーザーエモート）が変化した場合のみセクションを再構築する。
    /// USERSTATE のみの更新（emote-sets 変化）はセクション再構築をスキップし、
    /// 使用可否の再計算と再フィルタのみを行う。
    /// これにより loadEmotes() との並行実行による表示名消失レースを防ぐ。
    func observeUserEmoteSetsUpdates() async {
        while !Task.isCancelled {
            await emoteStore.waitForNextUserEmoteSetsUpdate()
            guard !Task.isCancelled else { break }

            userEmoteSets = await emoteStore.userAvailableEmoteSets()
            userEmoteIds  = await emoteStore.userEmoteIdSet()

            // エモートデータが変化した場合のみセクションを再構築する（USERSTATE のみの変化はスキップ）
            let channel    = await emoteStore.channelEmotesSnapshot()
            let user       = await emoteStore.userEmotesSnapshot()
            let channelIds = Set(channel.map(\.id))
            let userIds    = Set(user.map(\.id))

            if channelIds != lastBuiltChannelIds || userIds != lastBuiltUserIds {
                let global = await emoteStore.globalEmotesSnapshot()
                await profileImageStore.fetchUsers(userIds: collectOwnerIds(channel: channel, user: user))
                lastBuiltChannelIds = channelIds
                lastBuiltUserIds    = userIds
                allSections = buildSections(channel: channel, user: user, global: global)
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

    /// エモートストアのスナップショットを取得し、表示名を事前フェッチしてからセクションを再構築する
    ///
    /// `loadEmotes()` と `observeUserEmoteSetsUpdates()` の共通ロジック。
    /// 表示名フェッチを await することで、セクション構築時点で displayName が確定し
    /// 初回レンダリングから正しいチャンネル名が表示される。
    private func refreshSections() async {
        let channel = await emoteStore.channelEmotesSnapshot()
        let user    = await emoteStore.userEmotesSnapshot()
        let global  = await emoteStore.globalEmotesSnapshot()
        userEmoteSets = await emoteStore.userAvailableEmoteSets()
        userEmoteIds  = await emoteStore.userEmoteIdSet()
        await profileImageStore.fetchUsers(userIds: collectOwnerIds(channel: channel, user: user))
        lastBuiltChannelIds = Set(channel.map(\.id))
        lastBuiltUserIds    = Set(user.map(\.id))
        allSections = buildSections(channel: channel, user: user, global: global)
        applyFilter()
    }

    /// チャンネル・ユーザーエモートからセクションオーナー ID を収集する
    ///
    /// - Returns: currentBroadcasterId を含む、重複なし・"0" 除外済みの ownerId 配列
    private func collectOwnerIds(channel: [HelixEmote], user: [HelixEmote]) -> [String] {
        var ids = Set<String>()
        if let id = currentBroadcasterId { ids.insert(id) }
        for emote in channel + user {
            if let ownerId = emote.ownerId, ownerId != "0", !ownerId.isEmpty { ids.insert(ownerId) }
        }
        return Array(ids)
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
        // グローバルエンドポイントに存在する ID セットを事前に作成してユーザーエモートの振り分けに使用する
        let globalIdSet = Set(global.map(\.id))
        let classified = classifyEmotes(channel: channel, user: user, globalIdSet: globalIdSet, seen: &seen)
        return assembleSections(classified: classified, global: global, seen: &seen)
    }

    /// エモートをセクション種別ごとに分類して中間構造を返す
    ///
    /// 分類ルール（優先順位）:
    /// 1. `emoteType == "hypetrain"` → `hypeTrain` セクション
    /// 2. グローバル判定（`emoteType == "globals"` または `globalIdSet` に含まれる ID）→ global セクション
    /// 3. `ownerId == currentBroadcasterId` → `currentChannel` セクション（channelEmotes 含む）
    /// 4. `ownerId != nil && ownerId != "0"` → `subscribedChannel(ownerId)` セクション（ビッツエモート含む）
    /// 5. それ以外（`ownerId == nil` または `ownerId == "0"`）→ global セクションに送る
    ///
    /// - Note: `/helix/chat/emotes/user` はグローバルエモート（smilies 等）を ownerId 付きで返すため、
    ///   emoteType だけでなくグローバルエンドポイントの ID セットとも照合して振り分ける。
    private func classifyEmotes(
        channel: [HelixEmote],
        user: [HelixEmote],
        globalIdSet: Set<String>,
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
            } else if emote.emoteType == "globals" || globalIdSet.contains(emote.id) {
                // globals タイプまたはグローバルエンドポイントに存在する ID は global セクションへ送る
                // seen から除外して assembleSections の global 合算処理で拾う
                seen.remove(emote.id)
                otherEmotes.append(emote)
            } else if let ownerId = emote.ownerId, ownerId == currentBroadcasterId {
                currentChannelEmotes.append(emote)
            } else if let ownerId = emote.ownerId, ownerId != "0", !ownerId.isEmpty {
                if subscribedByOwnerId[ownerId] == nil { subscribedOwnerIds.append(ownerId) }
                subscribedByOwnerId[ownerId, default: []].append(emote)
            } else {
                // ownerId なし / "0" / 空文字エモートは global セクションで処理するため seen から除外する
                seen.remove(emote.id)
                otherEmotes.append(emote)
            }
        }
        return (currentChannelEmotes, hypeEmotes, subscribedOwnerIds, subscribedByOwnerId, otherEmotes)
    }

    /// 分類済みエモートから EmotePickerSection 配列を組み立てる（空セクションは除外）
    ///
    /// `fetchUsers()` 完了後に呼ぶことで `displayName` が確定した状態で判定できる。
    /// displayName が取得できない ownerId（API が返さないサービスアカウント等）のエモートは
    /// 数字 ID のセクションを作らず global セクションにまとめる。
    private func assembleSections(
        classified: (currentChannel: [HelixEmote], hype: [HelixEmote],
                     subscribedOwnerIds: [String], subscribedByOwnerId: [String: [HelixEmote]],
                     other: [HelixEmote]),
        global: [HelixEmote],
        seen: inout Set<String>
    ) -> [EmotePickerSection] {
        var sections: [EmotePickerSection] = []
        // displayName が未取得の ownerId のエモートを一時的にここに集めて global に送る
        var unnamedOwnerEmotes: [HelixEmote] = []

        if !classified.currentChannel.isEmpty {
            sections.append(EmotePickerSection(
                id: "current", kind: .currentChannel, title: "このチャンネル",
                iconUserId: currentBroadcasterId, emotes: classified.currentChannel
            ))
        }
        for ownerId in classified.subscribedOwnerIds {
            let emotes = classified.subscribedByOwnerId[ownerId] ?? []
            guard !emotes.isEmpty else { continue }
            guard let name = profileImageStore.displayName(for: ownerId) else {
                // displayName 未取得（サービスアカウント等で API がユーザーを返さない）→ global へ
                for emote in emotes { seen.remove(emote.id) }
                unnamedOwnerEmotes.append(contentsOf: emotes)
                continue
            }
            sections.append(EmotePickerSection(
                id: "channel-\(ownerId)", kind: .subscribedChannel(ownerId: ownerId),
                title: name, iconUserId: ownerId, emotes: emotes
            ))
        }
        if !classified.hype.isEmpty {
            sections.append(EmotePickerSection(
                id: "hype", kind: .hypeTrain, title: "HYPE", iconUserId: nil, emotes: classified.hype
            ))
        }
        // ownerId なし / 空文字 / displayName 未取得エモートは global セクションにまとめて末尾に配置する
        let globalEmotes = (unnamedOwnerEmotes + classified.other + global).filter { seen.insert($0.id).inserted }
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
