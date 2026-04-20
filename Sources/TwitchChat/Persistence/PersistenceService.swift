// PersistenceService.swift
// 永続化層の抽象境界を定義する protocol
// テスト用 InMemoryPersistenceService と本番用 SwiftDataPersistenceService の共通インタフェース

import Foundation

/// 永続化サービスの抽象境界
///
/// エモート・バッジ・チャット履歴・画像バイナリの CRUD を提供する。
/// 引数・戻り値は既存の Sendable 型と DTOs.swift の Sendable struct のみを使用し、
/// @Model / ModelContext を外部に公開しない。
///
/// - Important: Swift 6 strict concurrency の要件を満たすため `Sendable` 制約を付与している。
///   実装クラスは `actor` または `@MainActor` クラスとすること。
protocol PersistenceService: Sendable {

    // MARK: - エモート

    /// 指定ユーザーのエモートをロードする
    func loadUserEmotes(userId: String) async -> [HelixEmote]

    /// 指定ユーザーのエモートを保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveUserEmotes(_ emotes: [HelixEmote], userId: String) async throws

    /// グローバルエモートをロードする
    func loadGlobalEmotes() async -> [HelixEmote]

    /// グローバルエモートを保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveGlobalEmotes(_ emotes: [HelixEmote]) async throws

    /// 指定チャンネルのエモートをロードする
    func loadChannelEmotes(broadcasterId: String) async -> [HelixEmote]

    /// 指定チャンネルのエモートを保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveChannelEmotes(_ emotes: [HelixEmote], broadcasterId: String) async throws

    // MARK: - バッジ・プロフィール

    /// 指定スコープのバッジ一覧をロードする
    func loadBadges(scope: BadgeScope) async -> [BadgeVersionSnapshot]

    /// 指定スコープのバッジ一覧を保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveBadges(_ badges: [BadgeVersionSnapshot], scope: BadgeScope) async throws

    /// 指定ユーザーID 一覧のプロフィールをロードする
    ///
    /// 取得できたプロフィールのみを返す。指定した ID が存在しない場合はその要素を省略する。
    func loadUserProfiles(userIds: [String]) async -> [UserProfileSnapshot]

    /// ユーザープロフィール一覧を保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveUserProfiles(_ profiles: [UserProfileSnapshot]) async throws

    // MARK: - チャット履歴

    /// 指定チャンネルの直近メッセージをロードする
    ///
    /// - Parameters:
    ///   - roomId: チャンネルの Twitch ユーザー ID
    ///   - limit: 取得上限件数（1 以上を指定すること）。受信日時降順（新しい順）で返す。
    ///   - before: この Date より前に受信したメッセージのみ返す（nil の場合は最新から）
    func loadRecentMessages(roomId: String, limit: Int, before: Date?) async -> [ChatMessage]

    /// メッセージを追加保存する
    ///
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func appendMessages(_ messages: [ChatMessage]) async throws

    /// メッセージを全文検索する
    ///
    /// - Parameters:
    ///   - query: 検索クエリ文字列
    ///   - roomId: 対象チャンネル（nil の場合は全チャンネルを対象にする）
    ///   - limit: 取得上限件数（1 以上を指定すること）。受信日時降順（新しい順）で返す。
    func searchMessages(query: String, roomId: String?, limit: Int) async -> [ChatMessage]

    // MARK: - 画像バイナリ

    /// 指定キーの画像バイナリをロードする（存在しない場合は nil）
    func loadImageData(key: ImageCacheKey) async -> Data?

    /// 画像バイナリを保存する
    ///
    /// - Parameters:
    ///   - data: 保存するバイナリデータ
    ///   - key: キャッシュキー
    ///   - mime: MIME タイプ文字列（例: "image/png", "image/gif"）。メタデータとして保存し、
    ///     将来の HTTP レスポンスや Content-Type ヘッダー再現に使用する。
    /// - Throws: ディスクまたはデータベース書き込みに失敗した場合
    func saveImageData(_ data: Data, key: ImageCacheKey, mime: String) async throws

    // MARK: - ライフサイクル

    /// ユーザースコープのデータ（ユーザーエモート・プロフィール）を削除する
    ///
    /// ログアウト時に呼び出す。グローバル・チャンネルエモート・チャット履歴は削除しない。
    func clearUserScoped(userId: String) async
}
