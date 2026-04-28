// MockPersistenceService.swift
// 3 段ルックアップ（L1→L2→L3）の検証用モック PersistenceService
// loadImageData / saveImageData の呼び出し回数とデータを記録する

import Foundation
@testable import TwitchChat

/// 画像 I/O の呼び出し追跡に特化したモック永続化サービス
///
/// - `loadImageDataCallCount` で L2 参照回数を検証できる
/// - `saveImageDataCallCount` で L2 書き込み回数を検証できる
/// - `seedImageData(_:key:)` でテスト用 L2 データを事前投入できる
actor MockPersistenceService: PersistenceService {

    // MARK: - 追跡カウンタ

    var loadImageDataCallCount = 0
    var saveImageDataCallCount = 0

    // MARK: - ストレージ

    private var storage: [ImageCacheKey: Data] = [:]

    // MARK: - テスト用ヘルパー

    /// 指定キーの画像データを L2 として事前投入する
    func seedImageData(_ data: Data, key: ImageCacheKey) {
        storage[key] = data
    }

    // MARK: - 画像 I/O

    func loadImageData(key: ImageCacheKey) async -> Data? {
        loadImageDataCallCount += 1
        return storage[key]
    }

    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) async throws {
        saveImageDataCallCount += 1
        storage[key] = data
    }

    // MARK: - スタブ実装（テスト対象外）

    func loadUserEmotes(userId: String) async -> [HelixEmote] { [] }
    func saveUserEmotes(_ emotes: [HelixEmote], userId: String) async throws {}
    func loadGlobalEmotes() async -> [HelixEmote] { [] }
    func saveGlobalEmotes(_ emotes: [HelixEmote]) async throws {}
    func loadChannelEmotes(broadcasterId: String) async -> [HelixEmote] { [] }
    func saveChannelEmotes(_ emotes: [HelixEmote], broadcasterId: String) async throws {}
    func loadGlobalEmotesWithTimestamp() async -> (emotes: [HelixEmote], fetchedAt: Date?) { ([], nil) }
    func loadUserEmotesWithTimestamp(userId: String) async -> (emotes: [HelixEmote], fetchedAt: Date?) { ([], nil) }
    func loadChannelEmotesWithTimestamp(broadcasterId: String) async -> (emotes: [HelixEmote], fetchedAt: Date?) { ([], nil) }
    func loadBadges(scope: BadgeScope) async -> [BadgeVersionSnapshot] { [] }
    func saveBadges(_ badges: [BadgeVersionSnapshot], scope: BadgeScope) async throws {}
    func loadBadgesWithTimestamp(scope: BadgeScope) async -> (snapshots: [BadgeVersionSnapshot], fetchedAt: Date?) { ([], nil) }
    func loadUserProfiles(userIds: [String]) async -> [UserProfileSnapshot] { [] }
    func saveUserProfiles(_ profiles: [UserProfileSnapshot]) async throws {}
    func loadRecentMessages(roomId: String, limit: Int, before: Date?) async -> [ChatMessage] { [] }
    func appendMessages(_ messages: [ChatMessage]) async throws {}
    func searchMessages(query: String, roomId: String?, limit: Int) async -> [ChatMessage] { [] }
    func clearUserScoped(userId: String) async {}
}
