// SwiftDataPersistenceService.swift
// PersistenceActor に委譲する薄いラッパー実装
// PersistenceService プロトコルを満たし、TwitchChatApp からの DI 対象となる

import Foundation
import SwiftData

/// SwiftData を使用した永続化サービス
///
/// `PersistenceActor` に全処理を委譲する薄いラッパー struct。
/// 構築失敗時は呼び出し側（`PersistenceContainer.makeOnDisk()`）で catch して
/// `InMemoryPersistenceService` にフォールバックする。
struct SwiftDataPersistenceService: PersistenceService {

    private let actor: PersistenceActor

    /// 既存の ModelContainer からサービスを生成する
    init(container: ModelContainer) {
        self.actor = PersistenceActor(modelContainer: container)
    }

    /// ModelContainer を新規に構築してサービスを生成する
    ///
    /// - Parameter inMemory: `true` の場合はディスクに書き込まない（テスト用）
    /// - Throws: `ModelContainer` の構築に失敗した場合
    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ChatSchemaMigrationPlan.self,
            configurations: config
        )
        self.init(container: container)
    }

    // MARK: - エモート

    func loadUserEmotes(userId: String) async -> [HelixEmote] {
        await actor.loadUserEmotes(userId: userId)
    }

    func saveUserEmotes(_ emotes: [HelixEmote], userId: String) async throws {
        try await actor.saveUserEmotes(emotes, userId: userId)
    }

    func loadGlobalEmotes() async -> [HelixEmote] {
        await actor.loadGlobalEmotes()
    }

    func saveGlobalEmotes(_ emotes: [HelixEmote]) async throws {
        try await actor.saveGlobalEmotes(emotes)
    }

    func loadChannelEmotes(broadcasterId: String) async -> [HelixEmote] {
        await actor.loadChannelEmotes(broadcasterId: broadcasterId)
    }

    func saveChannelEmotes(_ emotes: [HelixEmote], broadcasterId: String) async throws {
        try await actor.saveChannelEmotes(emotes, broadcasterId: broadcasterId)
    }

    // MARK: - バッジ・プロフィール

    func loadBadges(scope: BadgeScope) async -> [BadgeVersionSnapshot] {
        await actor.loadBadges(scope: scope)
    }

    func saveBadges(_ badges: [BadgeVersionSnapshot], scope: BadgeScope) async throws {
        try await actor.saveBadges(badges, scope: scope)
    }

    func loadBadgesWithTimestamp(scope: BadgeScope) async -> (snapshots: [BadgeVersionSnapshot], fetchedAt: Date?) {
        await actor.loadBadgesWithTimestamp(scope: scope)
    }

    func loadUserProfiles(userIds: [String]) async -> [UserProfileSnapshot] {
        await actor.loadUserProfiles(userIds: userIds)
    }

    func saveUserProfiles(_ profiles: [UserProfileSnapshot]) async throws {
        try await actor.saveUserProfiles(profiles)
    }

    // MARK: - チャット履歴

    func loadRecentMessages(roomId: String, limit: Int, before: Date?) async -> [ChatMessage] {
        await actor.loadRecentMessages(roomId: roomId, limit: limit, before: before)
    }

    func appendMessages(_ messages: [ChatMessage]) async throws {
        try await actor.appendMessages(messages)
    }

    func searchMessages(query: String, roomId: String?, limit: Int) async -> [ChatMessage] {
        await actor.searchMessages(query: query, roomId: roomId, limit: limit)
    }

    // MARK: - 画像バイナリ

    func loadImageData(key: ImageCacheKey) async -> Data? {
        await actor.loadImageData(key: key)
    }

    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) async throws {
        try await actor.saveImageData(data, key: key, mime: mime)
    }

    // MARK: - ライフサイクル

    func clearUserScoped(userId: String) async {
        await actor.clearUserScoped(userId: userId)
    }
}
