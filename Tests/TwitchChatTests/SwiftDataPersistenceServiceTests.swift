// SwiftDataPersistenceServiceTests.swift
// SwiftDataPersistenceService の統合テスト
// ModelConfiguration(isStoredInMemoryOnly: true) を使ってスキーマ・DTO 変換・upsert を検証する

import Foundation
import Testing
@testable import TwitchChat

/// SwiftDataPersistenceService の統合テストスイート
@Suite("SwiftDataPersistenceService テスト")
struct SwiftDataPersistenceServiceTests {

    /// テスト用の in-memory SwiftDataPersistenceService を生成する
    private func makeService() throws -> SwiftDataPersistenceService {
        try SwiftDataPersistenceService(inMemory: true)
    }

    // MARK: - エモート

    @Test("ユーザーエモートを保存して取得できる")
    func ユーザーエモートを保存して取得できる() async throws {
        // 前提: 空の SwiftDataPersistenceService（in-memory）
        let service = try makeService()
        let emotes = [
            HelixEmote(id: "1", name: "ぴえんエモート", format: ["static"], emoteType: "subscriptions"),
            HelixEmote(id: "2", name: "草エモート", format: ["static", "animated"], emoteType: "subscriptions")
        ]

        // 操作: ユーザーID "視聴者ユーザー123" にエモートを保存する
        try await service.saveUserEmotes(emotes, userId: "視聴者ユーザー123")

        // 検証: 同じユーザーIDで取得できる（順序に依存しない方法で確認）
        let loaded = await service.loadUserEmotes(userId: "視聴者ユーザー123")
        #expect(loaded.count == 2)
        #expect(loaded.map(\.name).contains("ぴえんエモート"))
        #expect(loaded.map(\.name).contains("草エモート"))
    }

    @Test("ユーザーエモートはユーザーIDごとに分離される")
    func ユーザーエモートはユーザーIDごとに分離される() async throws {
        // 前提: 2ユーザー分のエモートを別々に保存
        let service = try makeService()
        let emotesA = [HelixEmote(id: "10", name: "ユーザーAエモート", format: ["static"], emoteType: nil)]
        let emotesB = [HelixEmote(id: "20", name: "ユーザーBエモート", format: ["static"], emoteType: nil)]
        try await service.saveUserEmotes(emotesA, userId: "ユーザーA")
        try await service.saveUserEmotes(emotesB, userId: "ユーザーB")

        // 検証: それぞれのユーザーIDで別々のエモートが取得できる
        let loadedA = await service.loadUserEmotes(userId: "ユーザーA")
        let loadedB = await service.loadUserEmotes(userId: "ユーザーB")
        #expect(loadedA.count == 1)
        #expect(loadedA.map(\.name).contains("ユーザーAエモート"))
        #expect(loadedB.count == 1)
        #expect(loadedB.map(\.name).contains("ユーザーBエモート"))
    }

    @Test("グローバルエモートを保存して取得できる")
    func グローバルエモートを保存して取得できる() async throws {
        // 前提: 空のサービス
        let service = try makeService()
        let emotes = [
            HelixEmote(id: "25", name: "LUL", format: ["static"], emoteType: "globals"),
            HelixEmote(id: "1902", name: "PogChamp", format: ["static", "animated"], emoteType: "globals")
        ]

        // 操作: グローバルエモートを保存する
        try await service.saveGlobalEmotes(emotes)

        // 検証: グローバルエモートが取得できる
        let loaded = await service.loadGlobalEmotes()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.name).contains("LUL"))
        #expect(loaded.map(\.name).contains("PogChamp"))
    }

    @Test("チャンネルエモートはチャンネルごとに分離される")
    func チャンネルエモートはチャンネルごとに分離される() async throws {
        // 前提: 2チャンネル分のエモートを保存
        let service = try makeService()
        let emotesA = [HelixEmote(id: "100", name: "チャンネルAエモート", format: ["static"], emoteType: nil)]
        let emotesB = [HelixEmote(id: "200", name: "チャンネルBエモート", format: ["static"], emoteType: nil)]
        try await service.saveChannelEmotes(emotesA, broadcasterId: "チャンネルA配信者ID")
        try await service.saveChannelEmotes(emotesB, broadcasterId: "チャンネルB配信者ID")

        // 検証: チャンネルごとに分離される
        let loadedA = await service.loadChannelEmotes(broadcasterId: "チャンネルA配信者ID")
        let loadedB = await service.loadChannelEmotes(broadcasterId: "チャンネルB配信者ID")
        #expect(loadedA.count == 1)
        #expect(loadedA.map(\.name).contains("チャンネルAエモート"))
        #expect(loadedB.count == 1)
        #expect(loadedB.map(\.name).contains("チャンネルBエモート"))
    }

    @Test("同一スコープでエモートを再保存すると重複せず最新内容に置き換わる")
    func 同一スコープでエモートを再保存すると重複せず最新内容に置き換わる() async throws {
        // 前提: 最初に2件のグローバルエモートを保存
        let service = try makeService()
        let first = [
            HelixEmote(id: "1", name: "ぴえん", format: ["static"], emoteType: nil),
            HelixEmote(id: "2", name: "草", format: ["static"], emoteType: nil)
        ]
        try await service.saveGlobalEmotes(first)

        // 操作: id=1 を別名で上書き、id=3 を新規追加、id=2 は削除（セット差し替え）
        let second = [
            HelixEmote(id: "1", name: "ぴえん改", format: ["animated"], emoteType: nil),
            HelixEmote(id: "3", name: "祝", format: ["static"], emoteType: nil)
        ]
        try await service.saveGlobalEmotes(second)

        // 検証: 2件のみ、id=1 は最新の name と format、id=2 は消えている
        let loaded = await service.loadGlobalEmotes()
        #expect(loaded.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        #expect(byId["1"]?.name == "ぴえん改")
        #expect(byId["1"]?.format == ["animated"])
        #expect(byId["3"]?.name == "祝")
        #expect(byId["2"] == nil)
    }

    @Test("ユーザーエモートを保存してもグローバルエモートは影響を受けない")
    func ユーザーエモートを保存してもグローバルエモートは影響を受けない() async throws {
        // 前提: グローバルエモート1件を事前保存
        let service = try makeService()
        try await service.saveGlobalEmotes([
            HelixEmote(id: "global1", name: "グローバルエモート", format: ["static"], emoteType: "globals")
        ])

        // 操作: 別ユーザーエモートを保存
        try await service.saveUserEmotes([
            HelixEmote(id: "user1", name: "ユーザーエモート", format: ["static"], emoteType: nil)
        ], userId: "ユーザーX")

        // 検証: グローバルエモートは変化しない
        let global = await service.loadGlobalEmotes()
        #expect(global.count == 1)
        #expect(global.first?.name == "グローバルエモート")
    }

    // MARK: - バッジ

    @Test("バッジをスコープごとに保存して取得できる")
    func バッジをスコープごとに保存して取得できる() async throws {
        // 前提: 空のサービス
        let service = try makeService()
        let globalBadges = [
            BadgeVersionSnapshot(setId: "broadcaster", version: "1",
                                 imageUrl1x: "https://example.com/1x",
                                 imageUrl2x: "https://example.com/2x",
                                 imageUrl4x: "https://example.com/4x",
                                 title: "配信者", description: nil)
        ]

        // 操作: グローバルバッジを保存
        try await service.saveBadges(globalBadges, scope: .global)

        // 検証: グローバルスコープで取得できる
        let loaded = await service.loadBadges(scope: .global)
        #expect(loaded.count == 1)
        #expect(loaded.first?.setId == "broadcaster")
        #expect(loaded.first?.title == "配信者")
    }

    @Test("チャンネルバッジはチャンネルごとに分離される")
    func チャンネルバッジはチャンネルごとに分離される() async throws {
        // 前提: 2チャンネルのバッジを保存
        let service = try makeService()
        let badgesA = [BadgeVersionSnapshot(setId: "subscriber", version: "12",
                                            imageUrl1x: "https://a.com/1x",
                                            imageUrl2x: "https://a.com/2x",
                                            imageUrl4x: "https://a.com/4x",
                                            title: "12ヶ月サブ", description: nil)]
        let badgesB = [BadgeVersionSnapshot(setId: "subscriber", version: "6",
                                            imageUrl1x: "https://b.com/1x",
                                            imageUrl2x: "https://b.com/2x",
                                            imageUrl4x: "https://b.com/4x",
                                            title: "6ヶ月サブ", description: nil)]
        try await service.saveBadges(badgesA, scope: .channel(broadcasterId: "チャンネルA"))
        try await service.saveBadges(badgesB, scope: .channel(broadcasterId: "チャンネルB"))

        // 検証: チャンネルごとに分離される
        let loadedA = await service.loadBadges(scope: .channel(broadcasterId: "チャンネルA"))
        let loadedB = await service.loadBadges(scope: .channel(broadcasterId: "チャンネルB"))
        #expect(loadedA.count == 1)
        #expect(loadedA.first?.title == "12ヶ月サブ")
        #expect(loadedB.count == 1)
        #expect(loadedB.first?.title == "6ヶ月サブ")
    }

    // MARK: - プロフィール

    @Test("ユーザープロフィールを保存して複数ID一括取得できる")
    func ユーザープロフィールを保存して複数ID一括取得できる() async throws {
        // 前提: 3ユーザーのプロフィールを保存
        let service = try makeService()
        let profiles = [
            UserProfileSnapshot(userId: "001", login: "yamada_taro", displayName: "山田太郎", profileImageUrl: nil),
            UserProfileSnapshot(userId: "002", login: "sato_hanako", displayName: "佐藤花子", profileImageUrl: "https://example.com/hanako.png"),
            UserProfileSnapshot(userId: "003", login: "suzuki_ichiro", displayName: "鈴木一郎", profileImageUrl: nil)
        ]
        try await service.saveUserProfiles(profiles)

        // 操作: 001 と 003 を一括取得
        let loaded = await service.loadUserProfiles(userIds: ["001", "003"])

        // 検証: 2件取得でき、表示名が正しい
        #expect(loaded.count == 2)
        #expect(loaded.map(\.displayName).contains("山田太郎"))
        #expect(loaded.map(\.displayName).contains("鈴木一郎"))
        #expect(!loaded.map(\.displayName).contains("佐藤花子"))
    }

    @Test("ユーザープロフィールを再保存すると上書きされる")
    func ユーザープロフィールを再保存すると上書きされる() async throws {
        // 前提: 初期プロフィールを保存
        let service = try makeService()
        let original = UserProfileSnapshot(userId: "001", login: "yamada_taro", displayName: "山田太郎", profileImageUrl: nil)
        try await service.saveUserProfiles([original])

        // 操作: 同じユーザーIDで displayName を変更して再保存
        let updated = UserProfileSnapshot(userId: "001", login: "yamada_taro", displayName: "山田太郎（更新後）", profileImageUrl: "https://example.com/icon.png")
        try await service.saveUserProfiles([updated])

        // 検証: 1件のみで最新の displayName に更新されている
        let loaded = await service.loadUserProfiles(userIds: ["001"])
        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "山田太郎（更新後）")
        #expect(loaded.first?.profileImageUrl == "https://example.com/icon.png")
    }

    // MARK: - チャット履歴

    @Test("メッセージを追加してroomIdごとに直近件数を取得できる")
    func メッセージを追加してroomIdごとに直近件数を取得できる() async throws {
        // 前提: 2チャンネルのメッセージを追加
        let service = try makeService()
        let messagesA = (1...3).map { i in
            ChatMessage(systemNotice: "チャンネルAのメッセージ\(i)", roomId: "チャンネルA配信者ID")
        }
        let messagesB = [ChatMessage(systemNotice: "チャンネルBのメッセージ1", roomId: "チャンネルB配信者ID")]
        try await service.appendMessages(messagesA)
        try await service.appendMessages(messagesB)

        // 操作: チャンネルAの直近2件を取得
        let loaded = await service.loadRecentMessages(roomId: "チャンネルA配信者ID", limit: 2, before: nil)

        // 検証: 2件のみ取得され、チャンネルBのメッセージは混入しない
        #expect(loaded.count == 2)
        for msg in loaded {
            #expect(msg.roomId == "チャンネルA配信者ID")
        }
    }

    @Test("メッセージは受信日時降順で返る")
    func メッセージは受信日時降順で返る() async throws {
        // 前提: 3件のメッセージを保存（id で識別するため UUID を固定）
        let service = try makeService()
        let now = Date()
        let messages = [
            ChatMessage(id: "msg_oldest", text: "最古のメッセージ", receivedAt: now.addingTimeInterval(-200)),
            ChatMessage(id: "msg_middle", text: "中間のメッセージ", receivedAt: now.addingTimeInterval(-100)),
            ChatMessage(id: "msg_newest", text: "最新のメッセージ", receivedAt: now)
        ]
        try await service.appendMessages(messages)

        // 操作: 全件取得
        let loaded = await service.loadRecentMessages(roomId: "テストチャンネルID", limit: 10, before: nil)

        // 検証: 降順（最新が先頭）で返る
        #expect(loaded.count == 3)
        #expect(loaded[0].id == "msg_newest")
        #expect(loaded[1].id == "msg_middle")
        #expect(loaded[2].id == "msg_oldest")
    }

    @Test("beforeパラメータで指定日時より前のメッセージのみ取得できる")
    func beforeパラメータで指定日時より前のメッセージのみ取得できる() async throws {
        // 前提: 3件のメッセージを時系列で保存
        let service = try makeService()
        let now = Date()
        let cutoff = now.addingTimeInterval(-100)
        let messages = [
            ChatMessage(id: "msg_old", text: "カットオフ前のメッセージ", receivedAt: now.addingTimeInterval(-200)),
            ChatMessage(id: "msg_cutoff", text: "カットオフ境界のメッセージ", receivedAt: cutoff),
            ChatMessage(id: "msg_new", text: "カットオフ後のメッセージ", receivedAt: now)
        ]
        try await service.appendMessages(messages)

        // 操作: before=cutoff で取得（cutoff 未満のみ）
        let loaded = await service.loadRecentMessages(roomId: "テストチャンネルID", limit: 10, before: cutoff)

        // 検証: cutoff より前のメッセージのみ（msg_old のみ）
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "msg_old")
    }

    @Test("メッセージ検索でクエリにマッチするメッセージのみ返る")
    func メッセージ検索でクエリにマッチするメッセージのみ返る() async throws {
        // 前提: 3件のメッセージを保存
        let service = try makeService()
        let messages = [
            ChatMessage(id: "msg1", text: "今日は良い天気ですね", receivedAt: Date().addingTimeInterval(-2)),
            ChatMessage(id: "msg2", text: "明日は雨の予報です", receivedAt: Date().addingTimeInterval(-1)),
            ChatMessage(id: "msg3", text: "週末は晴れるらしい", receivedAt: Date())
        ]
        try await service.appendMessages(messages)

        // 操作: "天気" を含むメッセージを検索
        let results = await service.searchMessages(query: "天気", roomId: nil, limit: 10)

        // 検証: "今日は良い天気ですね" のみヒット
        #expect(results.count == 1)
        #expect(results.first?.id == "msg1")
    }

    @Test("バッジとエモートを含むメッセージを保存して復元できる")
    func バッジとエモートを含むメッセージを保存して復元できる() async throws {
        // 前提: バッジとエモートを持つメッセージを作成
        let service = try makeService()
        let emotes = [EmotePosition(emoteId: "25", startIndex: 0, endIndex: 4)]
        let badges = [Badge(name: "broadcaster", version: "1"), Badge(name: "subscriber", version: "12")]
        let original = ChatMessage(
            id: "testmsg_001",
            username: "yamada_taro",
            displayName: "山田太郎",
            text: "LUL こんにちは",
            colorHex: "#FF4500",
            badges: badges,
            emotes: emotes,
            roomId: "チャンネルA配信者ID",
            isAction: false,
            receivedAt: Date(),
            replyParentMsgId: nil,
            isOptimistic: false,
            replyParentUserLogin: nil,
            replyParentDisplayName: nil,
            replyParentMsgBody: nil,
            isSystemNotice: false
        )

        // 操作: 保存して取得
        try await service.appendMessages([original])
        let loaded = await service.loadRecentMessages(roomId: "チャンネルA配信者ID", limit: 10, before: nil)

        // 検証: 1件取得でき、badges/emotes が復元されている
        #expect(loaded.count == 1)
        let restored = loaded[0]
        #expect(restored.id == original.id)
        #expect(restored.text == original.text)
        #expect(restored.username == original.username)
        #expect(restored.displayName == original.displayName)
        #expect(restored.colorHex == original.colorHex)
        #expect(restored.badges == original.badges)
        #expect(restored.emotes == original.emotes)
        // segments は text + emotes から再生成されるため等価性を確認
        #expect(restored.segments == original.segments)
    }

    @Test("返信情報を含むメッセージを保存して復元できる")
    func 返信情報を含むメッセージを保存して復元できる() async throws {
        // 前提: 返信情報を持つメッセージを作成
        let service = try makeService()
        let original = ChatMessage(
            id: "reply_msg_001",
            username: "sato_hanako",
            displayName: "佐藤花子",
            text: "返信テスト",
            colorHex: nil,
            badges: [],
            emotes: [],
            roomId: "チャンネルA配信者ID",
            isAction: false,
            receivedAt: Date(),
            replyParentMsgId: "parent_msg_999",
            isOptimistic: false,
            replyParentUserLogin: "yamada_taro",
            replyParentDisplayName: "山田太郎",
            replyParentMsgBody: "元のメッセージ本文",
            isSystemNotice: false
        )

        // 操作: 保存して取得
        try await service.appendMessages([original])
        let loaded = await service.loadRecentMessages(roomId: "チャンネルA配信者ID", limit: 10, before: nil)

        // 検証: 返信情報が正しく復元される
        let restored = try #require(loaded.first)
        #expect(restored.replyParentMsgId == "parent_msg_999")
        #expect(restored.replyParentUserLogin == "yamada_taro")
        #expect(restored.replyParentDisplayName == "山田太郎")
        #expect(restored.replyParentMsgBody == "元のメッセージ本文")
    }

    @Test("ACTIONメッセージとシステム通知メッセージのフラグが復元される")
    func ACTIONメッセージとシステム通知メッセージのフラグが復元される() async throws {
        // 前提: ACTION メッセージとシステム通知メッセージを作成
        let service = try makeService()
        let actionMsg = ChatMessage(
            id: "action_msg_001",
            username: "suzuki_ichiro",
            displayName: "鈴木一郎",
            text: "踊っています",
            colorHex: nil,
            badges: [],
            emotes: [],
            roomId: "チャンネルA配信者ID",
            isAction: true,
            receivedAt: Date().addingTimeInterval(-1),
            replyParentMsgId: nil,
            isOptimistic: false,
            replyParentUserLogin: nil,
            replyParentDisplayName: nil,
            replyParentMsgBody: nil,
            isSystemNotice: false
        )
        let systemMsg = ChatMessage(
            id: "system_msg_001",
            username: "",
            displayName: "",
            text: "モデレーションコマンド成功",
            colorHex: nil,
            badges: [],
            emotes: [],
            roomId: "チャンネルA配信者ID",
            isAction: false,
            receivedAt: Date(),
            replyParentMsgId: nil,
            isOptimistic: false,
            replyParentUserLogin: nil,
            replyParentDisplayName: nil,
            replyParentMsgBody: nil,
            isSystemNotice: true
        )

        // 操作: 保存して取得
        try await service.appendMessages([actionMsg, systemMsg])
        let loaded = await service.loadRecentMessages(roomId: "チャンネルA配信者ID", limit: 10, before: nil)

        // 検証: フラグが正しく復元される
        #expect(loaded.count == 2)
        let loadedById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        #expect(loadedById["action_msg_001"]?.isAction == true)
        #expect(loadedById["action_msg_001"]?.isSystemNotice == false)
        #expect(loadedById["system_msg_001"]?.isSystemNotice == true)
        #expect(loadedById["system_msg_001"]?.isAction == false)
    }

    // MARK: - 画像

    @Test("画像バイナリを保存して取得できる")
    func 画像バイナリを保存して取得できる() async throws {
        // 前提: テスト用の画像データ
        let service = try makeService()
        let imageData = Data("テスト画像バイナリ".utf8)
        let key = ImageCacheKey(kind: .emote, identifier: "emote_001:2x:static")

        // 操作: 保存して取得
        try await service.saveImageData(imageData, key: key, mime: "image/png")
        let loaded = await service.loadImageData(key: key)

        // 検証: 同じデータが取得できる
        #expect(loaded == imageData)
    }

    @Test("画像バイナリを再保存すると最新データで上書きされる")
    func 画像バイナリを再保存すると最新データで上書きされる() async throws {
        // 前提: 初期データを保存
        let service = try makeService()
        let key = ImageCacheKey(kind: .badge, identifier: "broadcaster:1:2x")
        let originalData = Data("元の画像データ".utf8)
        try await service.saveImageData(originalData, key: key, mime: "image/png")

        // 操作: 同じキーで別データを保存
        let updatedData = Data("更新後の画像データ".utf8)
        try await service.saveImageData(updatedData, key: key, mime: "image/webp")

        // 検証: 最新データが取得できる
        let loaded = await service.loadImageData(key: key)
        #expect(loaded == updatedData)
    }

    @Test("画像種別が異なれば同じidentifierでも分離される")
    func 画像種別が異なれば同じidentifierでも分離される() async throws {
        // 前提: 同じ identifier で異なる kind の画像を保存
        let service = try makeService()
        let emoteData = Data("エモート画像".utf8)
        let badgeData = Data("バッジ画像".utf8)
        let sharedIdentifier = "12345:2x:static"
        let emoteKey = ImageCacheKey(kind: .emote, identifier: sharedIdentifier)
        let badgeKey = ImageCacheKey(kind: .badge, identifier: sharedIdentifier)
        try await service.saveImageData(emoteData, key: emoteKey, mime: "image/png")
        try await service.saveImageData(badgeData, key: badgeKey, mime: "image/png")

        // 検証: それぞれ別々に取得できる
        let loadedEmote = await service.loadImageData(key: emoteKey)
        let loadedBadge = await service.loadImageData(key: badgeKey)
        #expect(loadedEmote == emoteData)
        #expect(loadedBadge == badgeData)
    }

    // MARK: - ライフサイクル

    @Test("clearUserScopedでユーザー固有データのみ削除されグローバル_チャンネル_履歴は保持される")
    func clearUserScopedでユーザー固有データのみ削除されグローバル_チャンネル_履歴は保持される() async throws {
        // 前提: 5種類のデータを保存
        let service = try makeService()
        let userId = "削除対象ユーザー001"
        // ユーザーエモート（削除対象）
        try await service.saveUserEmotes([
            HelixEmote(id: "user1", name: "ユーザー固有エモート", format: ["static"], emoteType: nil)
        ], userId: userId)
        // ユーザープロフィール（削除対象）
        try await service.saveUserProfiles([
            UserProfileSnapshot(userId: userId, login: "target_user", displayName: "削除対象ユーザー", profileImageUrl: nil)
        ])
        // グローバルエモート（保持対象）
        try await service.saveGlobalEmotes([
            HelixEmote(id: "global1", name: "グローバルエモート", format: ["static"], emoteType: "globals")
        ])
        // チャンネルエモート（保持対象）
        try await service.saveChannelEmotes([
            HelixEmote(id: "ch1", name: "チャンネルエモート", format: ["static"], emoteType: nil)
        ], broadcasterId: "チャンネルA配信者ID")
        // チャット履歴（保持対象）
        try await service.appendMessages([
            ChatMessage(systemNotice: "残すメッセージ", roomId: "チャンネルA配信者ID")
        ])

        // 操作: ユーザースコープのみクリア
        await service.clearUserScoped(userId: userId)

        // 検証: ユーザーエモートとプロフィールのみ削除される
        let userEmotes = await service.loadUserEmotes(userId: userId)
        let userProfiles = await service.loadUserProfiles(userIds: [userId])
        #expect(userEmotes.isEmpty)
        #expect(userProfiles.isEmpty)

        // グローバル・チャンネル・履歴は保持される
        let globalEmotes = await service.loadGlobalEmotes()
        let channelEmotes = await service.loadChannelEmotes(broadcasterId: "チャンネルA配信者ID")
        let messages = await service.loadRecentMessages(roomId: "チャンネルA配信者ID", limit: 10, before: nil)
        #expect(globalEmotes.count == 1)
        #expect(channelEmotes.count == 1)
        #expect(messages.count == 1)
    }
}

// MARK: - テスト用 ChatMessage イニシャライザ

private extension ChatMessage {
    /// テスト専用: roomId と receivedAt を指定してチャットメッセージを生成する
    init(id: String, text: String, receivedAt: Date) {
        self.init(
            id: id,
            username: "テストユーザー",
            displayName: "テストユーザー",
            text: text,
            colorHex: nil,
            badges: [],
            emotes: [],
            roomId: "テストチャンネルID",
            isAction: false,
            receivedAt: receivedAt,
            replyParentMsgId: nil,
            isOptimistic: false,
            replyParentUserLogin: nil,
            replyParentDisplayName: nil,
            replyParentMsgBody: nil,
            isSystemNotice: false
        )
    }
}
