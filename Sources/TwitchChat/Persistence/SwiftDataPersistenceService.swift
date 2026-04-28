// SwiftDataPersistenceService.swift
// PersistenceActor に委譲する薄いラッパー実装
// PersistenceService プロトコルを満たし、TwitchChatApp からの DI 対象となる

import AppKit
import Foundation
import SwiftData

/// SwiftData を使用した永続化サービス
///
/// `PersistenceActor` に全処理を委譲する薄いラッパー struct。
/// 構築失敗時は呼び出し側（`PersistenceContainer.makeOnDisk()`）で catch して
/// `InMemoryPersistenceService` にフォールバックする。
struct SwiftDataPersistenceService: PersistenceService {

    private let actor: PersistenceActor

    /// 既存の ModelContainer から生成する（テスト向けに imageDiskStoreRoot を注入可能）
    ///
    /// - Parameters:
    ///   - container: 構築済み ModelContainer
    ///   - imageDiskStoreRoot: ImageDiskStore のルートディレクトリ（nil の場合は diskStore 無効）
    ///   - attachAppKitTriggers: true の場合、起動 5 秒後 sweep と didResignActive 通知を登録する
    /// - Throws: ImageDiskStore の初期化に失敗した場合
    init(
        container: ModelContainer,
        imageDiskStoreRoot: URL? = nil,
        attachAppKitTriggers: Bool = false
    ) throws {
        if let root = imageDiskStoreRoot {
            let store = try ImageDiskStore(rootDirectory: root)
            // diskStore を init 時に同期注入してレースコンディションを排除する
            let actor = PersistenceActor(modelContainer: container, diskStore: store)
            self.actor = actor

            if attachAppKitTriggers {
                // 起動 5 秒後に reconcile + sweep を実行する
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    await actor.runReconcileAndSweep()
                }
                // バックグラウンド移行時に sweep を実行する（テスト時は登録しない）
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    Task { await actor.runReconcileAndSweep() }
                }
            }
        } else {
            self.actor = PersistenceActor(modelContainer: container)
        }
    }

    /// ModelContainer を新規に構築してサービスを生成する
    ///
    /// - Parameters:
    ///   - inMemory: `true` の場合はディスクに書き込まない（テスト用）
    ///   - imageDiskStoreRoot: ImageDiskStore のルートディレクトリ（nil の場合は diskStore 無効）
    /// - Throws: `ModelContainer` の構築に失敗した場合
    init(inMemory: Bool = false, imageDiskStoreRoot: URL? = nil) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ChatSchemaMigrationPlan.self,
            configurations: config
        )
        try self.init(container: container, imageDiskStoreRoot: imageDiskStoreRoot)
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

    func loadGlobalEmotesWithTimestamp() async -> (emotes: [HelixEmote], fetchedAt: Date?) {
        await actor.loadGlobalEmotesWithTimestamp()
    }

    func loadUserEmotesWithTimestamp(userId: String) async -> (emotes: [HelixEmote], fetchedAt: Date?) {
        await actor.loadUserEmotesWithTimestamp(userId: userId)
    }

    func loadChannelEmotesWithTimestamp(broadcasterId: String) async -> (emotes: [HelixEmote], fetchedAt: Date?) {
        await actor.loadChannelEmotesWithTimestamp(broadcasterId: broadcasterId)
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
