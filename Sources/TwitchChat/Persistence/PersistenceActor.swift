// PersistenceActor.swift
// SwiftData を使った永続化処理の actor 実装
// @ModelActor により ModelContext へのアクセスを actor 境界に閉じ、Swift 6 strict concurrency を保証する

import Foundation
import SwiftData

// MARK: - PersistenceActor

/// SwiftData の永続化処理を担う actor
///
/// `@ModelActor` マクロが `init(modelContainer:)` / `modelContext` / `modelExecutor` を自動生成する。
/// `@Model` / `ModelContext` は actor 外部に絶対に漏らさない。戻り値は常に Sendable DTO。
@ModelActor
actor PersistenceActor {

    // MARK: - エモート

    /// 指定ユーザーのエモートを取得する
    func loadUserEmotes(userId: String) -> [HelixEmote] {
        let scopeRaw = EmoteScope.user(userId: userId).rawValue
        return fetchEmotes(scopeRaw: scopeRaw)
    }

    /// 指定ユーザーのエモートを保存する（全件 upsert）
    func saveUserEmotes(_ emotes: [HelixEmote], userId: String) throws {
        try upsertEmotes(emotes, scope: .user(userId: userId))
    }

    /// グローバルエモートを取得する
    func loadGlobalEmotes() -> [HelixEmote] {
        fetchEmotes(scopeRaw: EmoteScope.global.rawValue)
    }

    /// グローバルエモートを保存する（全件 upsert）
    func saveGlobalEmotes(_ emotes: [HelixEmote]) throws {
        try upsertEmotes(emotes, scope: .global)
    }

    /// 指定チャンネルのエモートを取得する
    func loadChannelEmotes(broadcasterId: String) -> [HelixEmote] {
        let scopeRaw = EmoteScope.channel(broadcasterId: broadcasterId).rawValue
        return fetchEmotes(scopeRaw: scopeRaw)
    }

    /// 指定チャンネルのエモートを保存する（全件 upsert）
    func saveChannelEmotes(_ emotes: [HelixEmote], broadcasterId: String) throws {
        try upsertEmotes(emotes, scope: .channel(broadcasterId: broadcasterId))
    }

    // MARK: - バッジ

    /// 指定スコープのバッジを取得する
    func loadBadges(scope: BadgeScope) -> [BadgeVersionSnapshot] {
        let scopeRaw = badgeScopeRaw(scope)
        let descriptor = FetchDescriptor<PersistedBadgeVersion>(
            predicate: #Predicate { $0.scope == scopeRaw }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    /// 指定スコープのバッジを保存する（全件 upsert）
    func saveBadges(_ badges: [BadgeVersionSnapshot], scope: BadgeScope) throws {
        try upsertBadges(badges, scope: scope)
    }

    // MARK: - プロフィール

    /// 指定ユーザーIDのプロフィールを一括取得する
    func loadUserProfiles(userIds: [String]) -> [UserProfileSnapshot] {
        let descriptor = FetchDescriptor<PersistedUser>(
            predicate: #Predicate { userIds.contains($0.userId) }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    /// ユーザープロフィールを保存する（一括 upsert）
    func saveUserProfiles(_ profiles: [UserProfileSnapshot]) throws {
        guard !profiles.isEmpty else { return }
        let userIds = profiles.map { $0.userId }
        let descriptor = FetchDescriptor<PersistedUser>(
            predicate: #Predicate { userIds.contains($0.userId) }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingByUserId = Dictionary(uniqueKeysWithValues: existing.map { ($0.userId, $0) })
        let now = Date()
        for profile in profiles {
            if let row = existingByUserId[profile.userId] {
                row.login = profile.login
                row.displayName = profile.displayName
                row.profileImageUrl = profile.profileImageUrl
                row.updatedAt = now
            } else {
                modelContext.insert(PersistedUser(from: profile))
            }
        }
        try modelContext.save()
    }

    // MARK: - チャット履歴

    /// 指定 roomId の直近メッセージを受信日時降順で取得する
    func loadRecentMessages(roomId: String, limit: Int, before: Date?) -> [ChatMessage] {
        let safeLimit = max(0, limit)
        var descriptor: FetchDescriptor<PersistedChatMessage>
        if let before {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.roomId == roomId && $0.receivedAt < before },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.roomId == roomId },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = safeLimit
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { $0.toDomain() }
    }

    /// チャットメッセージを追加する（既存 id は skip、一括 fetch で N+1 を回避）
    func appendMessages(_ messages: [ChatMessage]) throws {
        guard !messages.isEmpty else { return }
        let newIds = messages.map { $0.id }
        let descriptor = FetchDescriptor<PersistedChatMessage>(
            predicate: #Predicate { newIds.contains($0.id) }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingIds = Set(existing.map { $0.id })
        for message in messages where !existingIds.contains(message.id) {
            modelContext.insert(PersistedChatMessage(from: message))
        }
        try modelContext.save()
    }

    /// テキスト内容でメッセージを検索する
    func searchMessages(query: String, roomId: String?, limit: Int) -> [ChatMessage] {
        let safeLimit = max(0, limit)
        var descriptor: FetchDescriptor<PersistedChatMessage>
        if let roomId {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.roomId == roomId && $0.text.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.text.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = safeLimit
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { $0.toDomain() }
    }

    // MARK: - 画像バイナリ

    /// キャッシュキーで画像バイナリを取得する
    func loadImageData(key: ImageCacheKey) -> Data? {
        let cacheKeyStr = imageCacheKeyRaw(key)
        let descriptor = FetchDescriptor<PersistedImageAsset>(
            predicate: #Predicate { $0.cacheKey == cacheKeyStr }
        )
        guard let asset = (try? modelContext.fetch(descriptor))?.first else { return nil }
        // LRU 更新（失敗しても無視）
        asset.lastAccessedAt = Date()
        try? modelContext.save()
        return asset.data
    }

    /// 画像バイナリを保存する（upsert）
    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) throws {
        let cacheKeyStr = imageCacheKeyRaw(key)
        let descriptor = FetchDescriptor<PersistedImageAsset>(
            predicate: #Predicate { $0.cacheKey == cacheKeyStr }
        )
        let now = Date()
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.data = data
            existing.mime = mime
            existing.lastAccessedAt = now
        } else {
            modelContext.insert(PersistedImageAsset(
                cacheKey: cacheKeyStr,
                kind: key.kind.rawValue,
                identifier: key.identifier,
                data: data,
                mime: mime,
                lastAccessedAt: now,
                createdAt: now
            ))
        }
        try modelContext.save()
    }

    // MARK: - ライフサイクル

    /// ユーザー固有データを削除する（グローバル/チャンネル/バッジ/履歴/画像は保持）
    func clearUserScoped(userId: String) {
        let userScopeRaw = EmoteScope.user(userId: userId).rawValue
        let emoteDescriptor = FetchDescriptor<PersistedEmote>(
            predicate: #Predicate { $0.scope == userScopeRaw }
        )
        do {
            let rows = try modelContext.fetch(emoteDescriptor)
            for row in rows { modelContext.delete(row) }
        } catch {
            print("[PersistenceActor] clearUserScoped: ユーザーエモート fetch 失敗 error=\(error)")
        }
        let userDescriptor = FetchDescriptor<PersistedUser>(
            predicate: #Predicate { $0.userId == userId }
        )
        do {
            let rows = try modelContext.fetch(userDescriptor)
            for row in rows { modelContext.delete(row) }
        } catch {
            print("[PersistenceActor] clearUserScoped: ユーザープロフィール fetch 失敗 error=\(error)")
        }
        do {
            try modelContext.save()
        } catch {
            print("[PersistenceActor] clearUserScoped: save 失敗 error=\(error)")
        }
    }
}

// MARK: - Private Helpers

private extension PersistenceActor {

    /// スコープ別エモートを fetch して HelixEmote 配列に変換する
    func fetchEmotes(scopeRaw: String) -> [HelixEmote] {
        let descriptor = FetchDescriptor<PersistedEmote>(
            predicate: #Predicate { $0.scope == scopeRaw }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    /// エモートをスコープ単位で upsert する（既存を全件差し替え）
    func upsertEmotes(_ emotes: [HelixEmote], scope: EmoteScope) throws {
        let scopeRaw = scope.rawValue
        let descriptor = FetchDescriptor<PersistedEmote>(
            predicate: #Predicate { $0.scope == scopeRaw }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let newIds = Set(emotes.map { $0.id })
        // 新セットに含まれない既存行を削除
        for row in existing where !newIds.contains(row.emoteId) {
            modelContext.delete(row)
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.emoteId, $0) })
        let now = Date()
        for emote in emotes {
            let key = scope.makeKey(emoteId: emote.id)
            if let row = existingById[emote.id] {
                row.name = emote.name
                row.formatRaw = emote.format.joined(separator: ",")
                row.emoteType = emote.emoteType
                row.emoteSetId = emote.emoteSetId
                row.ownerId = emote.ownerId
                row.updatedAt = now
            } else {
                modelContext.insert(PersistedEmote(
                    key: key,
                    scope: scopeRaw,
                    emoteId: emote.id,
                    name: emote.name,
                    formatRaw: emote.format.joined(separator: ","),
                    emoteType: emote.emoteType,
                    emoteSetId: emote.emoteSetId,
                    ownerId: emote.ownerId,
                    updatedAt: now
                ))
            }
        }
        try modelContext.save()
    }

    /// バッジをスコープ単位で upsert する（既存を全件差し替え）
    func upsertBadges(_ badges: [BadgeVersionSnapshot], scope: BadgeScope) throws {
        let scopeRaw = badgeScopeRaw(scope)
        let descriptor = FetchDescriptor<PersistedBadgeVersion>(
            predicate: #Predicate { $0.scope == scopeRaw }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let newKeys = Set(badges.map { "\(scopeRaw)|\($0.setId)|\($0.version)" })
        for row in existing where !newKeys.contains(row.compositeKey) {
            modelContext.delete(row)
        }
        let existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.compositeKey, $0) })
        let now = Date()
        for badge in badges {
            let compositeKey = "\(scopeRaw)|\(badge.setId)|\(badge.version)"
            if let row = existingByKey[compositeKey] {
                row.imageUrl1x = badge.imageUrl1x
                row.imageUrl2x = badge.imageUrl2x
                row.imageUrl4x = badge.imageUrl4x
                row.title = badge.title
                row.badgeDescription = badge.description
                row.updatedAt = now
            } else {
                modelContext.insert(PersistedBadgeVersion(
                    compositeKey: compositeKey,
                    scope: scopeRaw,
                    setId: badge.setId,
                    version: badge.version,
                    imageUrl1x: badge.imageUrl1x,
                    imageUrl2x: badge.imageUrl2x,
                    imageUrl4x: badge.imageUrl4x,
                    title: badge.title,
                    badgeDescription: badge.description,
                    updatedAt: now
                ))
            }
        }
        try modelContext.save()
    }

    /// BadgeScope をスコープ文字列に変換する
    func badgeScopeRaw(_ scope: BadgeScope) -> String {
        switch scope {
        case .global:
            return "global"
        case .channel(let broadcasterId):
            return "channel:\(broadcasterId)"
        }
    }

    /// ImageCacheKey をキャッシュキー文字列に変換する
    func imageCacheKeyRaw(_ key: ImageCacheKey) -> String {
        "\(key.kind.rawValue):\(key.identifier)"
    }
}

// MARK: - EmoteScope

/// エモートのスコープを表す列挙型（PersistenceActor 内部で使用）
enum EmoteScope {
    case global
    case channel(broadcasterId: String)
    case user(userId: String)

    /// スコープの文字列表現
    var rawValue: String {
        switch self {
        case .global:
            return "global"
        case .channel(let broadcasterId):
            return "channel:\(broadcasterId)"
        case .user(let userId):
            return "user:\(userId)"
        }
    }

    /// スコープとエモートIDを結合した主キーを生成する
    func makeKey(emoteId: String) -> String {
        "\(rawValue):\(emoteId)"
    }
}

// MARK: - ImageCacheKey.Kind Extension

extension ImageCacheKey.Kind {
    /// SwiftData 保存用の文字列表現
    var rawValue: String {
        switch self {
        case .emote: return "emote"
        case .badge: return "badge"
        case .profile: return "profile"
        }
    }
}

// MARK: - DTO 変換: PersistedEmote

extension PersistedEmote {
    /// HelixEmote とスコープから PersistedEmote を生成する
    convenience init(key: String, scope: String, from emote: HelixEmote, updatedAt: Date) {
        self.init(
            key: key,
            scope: scope,
            emoteId: emote.id,
            name: emote.name,
            formatRaw: emote.format.joined(separator: ","),
            emoteType: emote.emoteType,
            emoteSetId: emote.emoteSetId,
            ownerId: emote.ownerId,
            updatedAt: updatedAt
        )
    }

    /// HelixEmote に変換する
    func toDomain() -> HelixEmote {
        let format = formatRaw.isEmpty ? [] : formatRaw.split(separator: ",").map(String.init)
        return HelixEmote(
            id: emoteId,
            name: name,
            format: format,
            emoteType: emoteType,
            emoteSetId: emoteSetId,
            ownerId: ownerId
        )
    }
}

// MARK: - DTO 変換: PersistedBadgeVersion

extension PersistedBadgeVersion {
    /// BadgeVersionSnapshot から PersistedBadgeVersion を生成する
    convenience init(compositeKey: String, scope: String, from badge: BadgeVersionSnapshot, updatedAt: Date) {
        self.init(
            compositeKey: compositeKey,
            scope: scope,
            setId: badge.setId,
            version: badge.version,
            imageUrl1x: badge.imageUrl1x,
            imageUrl2x: badge.imageUrl2x,
            imageUrl4x: badge.imageUrl4x,
            title: badge.title,
            badgeDescription: badge.description,
            updatedAt: updatedAt
        )
    }

    /// BadgeVersionSnapshot に変換する
    func toDomain() -> BadgeVersionSnapshot {
        BadgeVersionSnapshot(
            setId: setId,
            version: version,
            imageUrl1x: imageUrl1x,
            imageUrl2x: imageUrl2x,
            imageUrl4x: imageUrl4x,
            title: title,
            description: badgeDescription
        )
    }
}

// MARK: - DTO 変換: PersistedUser

extension PersistedUser {
    /// UserProfileSnapshot から PersistedUser を生成する
    convenience init(from profile: UserProfileSnapshot) {
        self.init(
            userId: profile.userId,
            login: profile.login,
            displayName: profile.displayName,
            profileImageUrl: profile.profileImageUrl,
            updatedAt: Date()
        )
    }

    /// UserProfileSnapshot に変換する
    func toDomain() -> UserProfileSnapshot {
        UserProfileSnapshot(
            userId: userId,
            login: login,
            displayName: displayName,
            profileImageUrl: profileImageUrl
        )
    }
}

// MARK: - DTO 変換: PersistedChatMessage

// Badge と EmotePosition への Codable 適合（永続化層限定）
// ドメイン層には漏らさない
extension Badge: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case version
    }
}

extension EmotePosition: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoteId = try container.decode(String.self, forKey: .emoteId)
        startIndex = try container.decode(Int.self, forKey: .startIndex)
        endIndex = try container.decode(Int.self, forKey: .endIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emoteId, forKey: .emoteId)
        try container.encode(startIndex, forKey: .startIndex)
        try container.encode(endIndex, forKey: .endIndex)
    }

    enum CodingKeys: String, CodingKey {
        case emoteId
        case startIndex
        case endIndex
    }
}

extension PersistedChatMessage {
    /// ChatMessage から PersistedChatMessage を生成する
    convenience init(from message: ChatMessage) {
        let encoder = JSONEncoder()
        let badgesRaw: String
        do {
            badgesRaw = String(data: try encoder.encode(message.badges), encoding: .utf8) ?? "[]"
        } catch {
            print("[PersistenceActor] badges JSON エンコード失敗 id=\(message.id) error=\(error)")
            badgesRaw = "[]"
        }
        let emotesRaw: String
        do {
            emotesRaw = String(data: try encoder.encode(message.emotes), encoding: .utf8) ?? "[]"
        } catch {
            print("[PersistenceActor] emotes JSON エンコード失敗 id=\(message.id) error=\(error)")
            emotesRaw = "[]"
        }
        self.init(
            id: message.id,
            username: message.username,
            displayName: message.displayName,
            text: message.text,
            colorHex: message.colorHex,
            badgesRaw: badgesRaw,
            emotesRaw: emotesRaw,
            roomId: message.roomId,
            isAction: message.isAction,
            receivedAt: message.receivedAt,
            replyParentMsgId: message.replyParentMsgId,
            isOptimistic: message.isOptimistic,
            replyParentUserLogin: message.replyParentUserLogin,
            replyParentDisplayName: message.replyParentDisplayName,
            replyParentMsgBody: message.replyParentMsgBody,
            isSystemNotice: message.isSystemNotice,
            tmiSentAt: nil,
            senderUserId: nil
        )
    }

    /// ChatMessage に変換する（segments は text と emotes から再生成する）
    func toDomain() -> ChatMessage? {
        let decoder = JSONDecoder()
        let badges = (try? decoder.decode([Badge].self, from: Data(badgesRaw.utf8))) ?? []
        let emotes = (try? decoder.decode([EmotePosition].self, from: Data(emotesRaw.utf8))) ?? []
        return ChatMessage(
            id: id,
            username: username,
            displayName: displayName,
            text: text,
            colorHex: colorHex,
            badges: badges,
            emotePositions: emotes,
            roomId: roomId,
            isAction: isAction,
            receivedAt: receivedAt,
            replyParentMsgId: replyParentMsgId,
            isOptimistic: isOptimistic,
            replyParentUserLogin: replyParentUserLogin,
            replyParentDisplayName: replyParentDisplayName,
            replyParentMsgBody: replyParentMsgBody,
            isSystemNotice: isSystemNotice
        )
    }
}

// MARK: - ChatMessage.toPersistent

extension ChatMessage {
    /// PersistedChatMessage に変換する（PersistenceActor 内部でのみ使用）
    func toPersistent() -> PersistedChatMessage {
        PersistedChatMessage(from: self)
    }
}
