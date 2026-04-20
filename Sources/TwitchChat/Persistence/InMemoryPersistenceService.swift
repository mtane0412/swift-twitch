// InMemoryPersistenceService.swift
// PersistenceService の Dictionary ベーステスト用実装
// 単体テストで外部ストレージ依存なしに PersistenceService を利用するために使用する

import Foundation

/// Dictionary ベースのインメモリ PersistenceService 実装
///
/// テストおよびアプリ起動初期段階で使用する。
/// actor で囲うことで Dictionary へのデータ競合を防ぐ。
actor InMemoryPersistenceService: PersistenceService {

    // MARK: - 定数

    /// roomId が nil のメッセージを格納するための内部キー
    private static let noRoomKey = "__no_room__"

    // MARK: - ストレージ

    private var userEmotes: [String: [HelixEmote]] = [:]
    private var globalEmotes: [HelixEmote] = []
    private var channelEmotes: [String: [HelixEmote]] = [:]
    /// バッジデータとその保存時刻を保持する（TTL 判定に使用）
    private var badges: [BadgeScope: (snapshots: [BadgeVersionSnapshot], savedAt: Date)] = [:]
    private var userProfiles: [String: UserProfileSnapshot] = [:]
    /// roomId をキーにメッセージを格納。roomId が nil のメッセージは `noRoomKey` に格納する
    private var messages: [String: [ChatMessage]] = [:]
    private var imageData: [ImageCacheKey: Data] = [:]
    /// MIME タイプのメタデータ（将来の Content-Type 再現用）
    private var imageMime: [ImageCacheKey: String] = [:]

    // MARK: - PersistenceService

    func loadUserEmotes(userId: String) async -> [HelixEmote] {
        userEmotes[userId] ?? []
    }

    func saveUserEmotes(_ emotes: [HelixEmote], userId: String) async throws {
        userEmotes[userId] = emotes
    }

    func loadGlobalEmotes() async -> [HelixEmote] {
        globalEmotes
    }

    func saveGlobalEmotes(_ emotes: [HelixEmote]) async throws {
        globalEmotes = emotes
    }

    func loadChannelEmotes(broadcasterId: String) async -> [HelixEmote] {
        channelEmotes[broadcasterId] ?? []
    }

    func saveChannelEmotes(_ emotes: [HelixEmote], broadcasterId: String) async throws {
        channelEmotes[broadcasterId] = emotes
    }

    func loadBadges(scope: BadgeScope) async -> [BadgeVersionSnapshot] {
        badges[scope]?.snapshots ?? []
    }

    func saveBadges(_ badgeList: [BadgeVersionSnapshot], scope: BadgeScope) async throws {
        badges[scope] = (snapshots: badgeList, savedAt: Date())
    }

    func loadBadgesWithTimestamp(scope: BadgeScope) async -> (snapshots: [BadgeVersionSnapshot], fetchedAt: Date?) {
        guard let entry = badges[scope] else { return (snapshots: [], fetchedAt: nil) }
        return (snapshots: entry.snapshots, fetchedAt: entry.savedAt)
    }

    func loadUserProfiles(userIds: [String]) async -> [UserProfileSnapshot] {
        userIds.compactMap { userProfiles[$0] }
    }

    func saveUserProfiles(_ profiles: [UserProfileSnapshot]) async throws {
        for profile in profiles {
            userProfiles[profile.userId] = profile
        }
    }

    func loadRecentMessages(roomId: String, limit: Int, before: Date?) async -> [ChatMessage] {
        let safeLimit = max(0, limit)
        let stored = messages[roomId] ?? []
        let filtered: [ChatMessage]
        if let before {
            filtered = stored.filter { $0.receivedAt < before }
        } else {
            filtered = stored
        }
        // 新しい順に並べて上限件数を返す
        return Array(filtered.sorted { $0.receivedAt > $1.receivedAt }.prefix(safeLimit))
    }

    func appendMessages(_ newMessages: [ChatMessage]) async throws {
        for message in newMessages {
            let key = message.roomId ?? Self.noRoomKey
            messages[key, default: []].append(message)
        }
    }

    func searchMessages(query: String, roomId: String?, limit: Int) async -> [ChatMessage] {
        let safeLimit = max(0, limit)
        let source: [ChatMessage]
        if let roomId {
            source = messages[roomId] ?? []
        } else {
            source = messages.values.flatMap { $0 }
        }
        // loadRecentMessages と同様に受信日時降順で返す
        return Array(
            source
                .filter { $0.text.localizedCaseInsensitiveContains(query) }
                .sorted { $0.receivedAt > $1.receivedAt }
                .prefix(safeLimit)
        )
    }

    func loadImageData(key: ImageCacheKey) async -> Data? {
        imageData[key]
    }

    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) async throws {
        imageData[key] = data
        imageMime[key] = mime
    }

    func clearUserScoped(userId: String) async {
        userEmotes.removeValue(forKey: userId)
        userProfiles.removeValue(forKey: userId)
    }

#if DEBUG
    /// テスト用: バッジを任意の保存日時で登録する（TTL 検証用）
    func saveBadgesWithDate(_ badgeList: [BadgeVersionSnapshot], scope: BadgeScope, savedAt: Date) async {
        badges[scope] = (snapshots: badgeList, savedAt: savedAt)
    }
#endif
}
