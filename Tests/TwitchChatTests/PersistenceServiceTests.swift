// PersistenceServiceTests.swift
// InMemoryPersistenceService の単体テスト
// 各メソッドのデータ保存・取得・分離・削除の振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

/// InMemoryPersistenceService のテストスイート
@Suite("InMemoryPersistenceService テスト")
struct PersistenceServiceTests {

    // MARK: - エモート

    @Test("ユーザーエモートを保存して取得できる")
    func ユーザーエモートを保存して取得できる() async throws {
        // 前提: 空の InMemoryPersistenceService
        let service = InMemoryPersistenceService()
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
        let service = InMemoryPersistenceService()
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
        // 前提: 空の InMemoryPersistenceService
        let service = InMemoryPersistenceService()
        let emotes = [
            HelixEmote(id: "100", name: "LUL", format: ["static"], emoteType: "globals"),
            HelixEmote(id: "101", name: "PogChamp", format: ["static"], emoteType: "globals"),
            HelixEmote(id: "102", name: "Kappa", format: ["static"], emoteType: "globals")
        ]

        // 操作: グローバルエモートを保存する
        try await service.saveGlobalEmotes(emotes)

        // 検証: 全件取得できる
        let loaded = await service.loadGlobalEmotes()
        #expect(loaded.count == 3)
        #expect(loaded.map(\.name).contains("LUL"))
        #expect(loaded.map(\.name).contains("PogChamp"))
    }

    @Test("チャンネルエモートはチャンネルごとに分離される")
    func チャンネルエモートはチャンネルごとに分離される() async throws {
        // 前提: 2チャンネル分のエモートを別々に保存
        let service = InMemoryPersistenceService()
        let channelAEmotes = [HelixEmote(id: "200", name: "チャンネルAサブエモート", format: ["static"], emoteType: "subscriptions")]
        let channelBEmotes = [HelixEmote(id: "300", name: "チャンネルBサブエモート", format: ["static"], emoteType: "subscriptions")]

        try await service.saveChannelEmotes(channelAEmotes, broadcasterId: "チャンネルA配信者ID")
        try await service.saveChannelEmotes(channelBEmotes, broadcasterId: "チャンネルB配信者ID")

        // 検証: チャンネルIDで別々のエモートが取得できる
        let loadedA = await service.loadChannelEmotes(broadcasterId: "チャンネルA配信者ID")
        let loadedB = await service.loadChannelEmotes(broadcasterId: "チャンネルB配信者ID")
        #expect(loadedA.map(\.name).contains("チャンネルAサブエモート"))
        #expect(loadedB.map(\.name).contains("チャンネルBサブエモート"))

        // 検証: 未保存のチャンネルIDは空配列を返す
        let empty = await service.loadChannelEmotes(broadcasterId: "未登録チャンネルID")
        #expect(empty.isEmpty)
    }

    // MARK: - バッジ

    @Test("バッジをスコープごとに保存して取得できる")
    func バッジをスコープごとに保存して取得できる() async throws {
        // 前提: グローバルバッジとチャンネルバッジを別スコープで保存
        let service = InMemoryPersistenceService()
        let globalBadge = BadgeVersionSnapshot(
            setId: "broadcaster",
            version: "1",
            imageUrl1x: "https://cdn.example.com/broadcaster/1/1x.png",
            imageUrl2x: "https://cdn.example.com/broadcaster/1/2x.png",
            imageUrl4x: "https://cdn.example.com/broadcaster/1/4x.png",
            title: "配信者",
            description: nil
        )
        let channelBadge = BadgeVersionSnapshot(
            setId: "subscriber",
            version: "6",
            imageUrl1x: "https://cdn.example.com/sub/6/1x.png",
            imageUrl2x: "https://cdn.example.com/sub/6/2x.png",
            imageUrl4x: "https://cdn.example.com/sub/6/4x.png",
            title: "6ヶ月サブスク",
            description: nil
        )

        try await service.saveBadges([globalBadge], scope: .global)
        try await service.saveBadges([channelBadge], scope: .channel(broadcasterId: "テストチャンネルID"))

        // 検証: スコープごとに独立したバッジが取得できる
        let globalLoaded = await service.loadBadges(scope: .global)
        let channelLoaded = await service.loadBadges(scope: .channel(broadcasterId: "テストチャンネルID"))
        let unknownLoaded = await service.loadBadges(scope: .channel(broadcasterId: "未登録チャンネル"))

        #expect(globalLoaded.map(\.setId).contains("broadcaster"))
        #expect(channelLoaded.map(\.setId).contains("subscriber"))
        #expect(unknownLoaded.isEmpty)
    }

    // MARK: - ユーザープロフィール

    @Test("ユーザープロフィールを複数ID一括取得できる")
    func ユーザープロフィールを複数ID一括取得できる() async throws {
        // 前提: 3人分のプロフィールを保存
        let service = InMemoryPersistenceService()
        let profiles = [
            UserProfileSnapshot(
                userId: "ユーザーID001",
                login: "yamada_taro",
                displayName: "山田太郎",
                profileImageUrl: nil
            ),
            UserProfileSnapshot(
                userId: "ユーザーID002",
                login: "sato_hanako",
                displayName: "佐藤花子",
                profileImageUrl: "https://cdn.example.com/profile/002.png"
            ),
            UserProfileSnapshot(
                userId: "ユーザーID003",
                login: "suzuki_ichiro",
                displayName: "鈴木一郎",
                profileImageUrl: nil
            )
        ]

        try await service.saveUserProfiles(profiles)

        // 検証: 指定したIDのプロフィールのみ返る（指定外の "ユーザーID002" は含まれない）
        let loaded = await service.loadUserProfiles(userIds: ["ユーザーID001", "ユーザーID003"])
        #expect(loaded.count == 2)

        let names = loaded.map(\.displayName)
        #expect(names.contains("山田太郎"))
        #expect(names.contains("鈴木一郎"))
        #expect(!names.contains("佐藤花子"))
    }

    // MARK: - チャット履歴

    @Test("メッセージを追加してroomIdごとに直近件数を取得できる")
    func メッセージを追加してroomIdごとに直近件数を取得できる() async throws {
        // 前提: 2チャンネル分のメッセージを保存
        let service = InMemoryPersistenceService()
        let messageA1 = ChatMessage(localUsername: "テスト視聴者A", text: "チャンネルAのメッセージ1", roomId: "チャンネルAのroomId")
        let messageA2 = ChatMessage(localUsername: "テスト視聴者B", text: "チャンネルAのメッセージ2", roomId: "チャンネルAのroomId")
        let messageB = ChatMessage(localUsername: "テスト視聴者C", text: "チャンネルBのメッセージ", roomId: "チャンネルBのroomId")

        try await service.appendMessages([messageA1, messageA2, messageB])

        // 検証: チャンネルAのメッセージのみ取得できる
        let loadedA = await service.loadRecentMessages(roomId: "チャンネルAのroomId", limit: 10, before: nil)
        let loadedB = await service.loadRecentMessages(roomId: "チャンネルBのroomId", limit: 10, before: nil)
        #expect(loadedA.count == 2)
        #expect(loadedB.count == 1)

        // 検証: limit 件数が正しく制限される
        // receivedAt は Date() で自動設定されるため固定値比較は行わず、
        // 全件取得の中に含まれるメッセージが返ることだけを確認する
        let limited = await service.loadRecentMessages(roomId: "チャンネルAのroomId", limit: 1, before: nil)
        #expect(limited.count == 1)
        if let limitedText = limited.first?.text {
            #expect(loadedA.map(\.text).contains(limitedText))
        }
    }

    @Test("メッセージ検索でクエリにマッチするメッセージのみ返る")
    func メッセージ検索でクエリにマッチするメッセージのみ返る() async throws {
        // 前提: 複数メッセージを保存
        let service = InMemoryPersistenceService()
        let messages = [
            ChatMessage(localUsername: "テスト視聴者A", text: "今日は良い天気ですね", roomId: "テストチャンネルroomId"),
            ChatMessage(localUsername: "テスト視聴者B", text: "スパゲッティ食べました", roomId: "テストチャンネルroomId"),
            ChatMessage(localUsername: "テスト視聴者A", text: "天気雨が降ってきた", roomId: "テストチャンネルroomId")
        ]
        try await service.appendMessages(messages)

        // 検証: "天気" を含むメッセージのみ2件ヒットする
        let results = await service.searchMessages(query: "天気", roomId: "テストチャンネルroomId", limit: 10)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.text.contains("天気") })
    }

    // MARK: - 画像バイナリ

    @Test("画像バイナリを保存して取得できる")
    func 画像バイナリを保存して取得できる() async throws {
        // 前提: ダミーのエモート画像データ
        let service = InMemoryPersistenceService()
        let key = ImageCacheKey(kind: .emote, identifier: "エモートID123:2x:static")
        let imageData = Data("テスト用エモート画像バイナリデータ".utf8)

        // 操作: 保存する
        try await service.saveImageData(imageData, key: key, mime: "image/png")

        // 検証: 同じキーで取得できる
        let loaded = await service.loadImageData(key: key)
        #expect(loaded == imageData)

        // 検証: 存在しないキーは nil を返す
        let missing = await service.loadImageData(key: ImageCacheKey(kind: .badge, identifier: "未登録バッジ"))
        #expect(missing == nil)
    }

    // MARK: - ライフサイクル

    @Test("clearUserScopedでユーザー固有データのみ削除される")
    func clearUserScopedでユーザー固有データのみ削除される() async throws {
        // 前提: ユーザーエモート・プロフィール・グローバルエモートを保存
        let service = InMemoryPersistenceService()
        let userId = "削除対象ユーザーID"

        try await service.saveUserEmotes(
            [HelixEmote(id: "1", name: "削除対象エモート", format: ["static"], emoteType: nil)],
            userId: userId
        )
        try await service.saveUserProfiles([
            UserProfileSnapshot(
                userId: userId,
                login: "削除対象ユーザー",
                displayName: "削除対象ユーザー",
                profileImageUrl: nil
            )
        ])
        try await service.saveGlobalEmotes([
            HelixEmote(id: "999", name: "残るグローバルエモート", format: ["static"], emoteType: "globals")
        ])

        // 操作: ユーザースコープのデータを削除する
        await service.clearUserScoped(userId: userId)

        // 検証: ユーザーエモート・プロフィールは削除されている
        let userEmotes = await service.loadUserEmotes(userId: userId)
        let profiles = await service.loadUserProfiles(userIds: [userId])
        #expect(userEmotes.isEmpty)
        #expect(profiles.isEmpty)

        // 検証: グローバルエモートは残っている
        let globalEmotes = await service.loadGlobalEmotes()
        #expect(globalEmotes.count == 1)
        #expect(globalEmotes.map(\.name).contains("残るグローバルエモート"))
    }
}
