// SchemaV1.swift
// SwiftData スキーマバージョン1の @Model クラス定義とマイグレーション計画
// Twitch チャットアプリのエモート・チャット履歴・バッジ・ユーザー・画像を永続化する

import Foundation
import SwiftData

// MARK: - PersistedEmote

/// エモートの永続化モデル
///
/// key は "<scope>:<emoteId>" 形式で一意性を保証する。
/// scope は "global" / "channel:<broadcasterId>" / "user:<userId>" のいずれか。
@Model
final class PersistedEmote {
    /// 主キー（"<scope>:<emoteId>"）
    @Attribute(.unique) var key: String
    /// スコープ文字列（インデックス対象）
    var scope: String
    /// エモートID（Twitch エモートの一意ID）
    var emoteId: String
    /// エモート名
    var name: String
    /// format 配列をカンマ区切りで保存（例: "static,animated"）
    var formatRaw: String
    /// エモートタイプ（"globals", "subscriptions" 等）
    var emoteType: String?
    /// エモートセットID
    var emoteSetId: String?
    /// エモートオーナーのユーザーID
    var ownerId: String?
    /// 最終更新日時
    var updatedAt: Date

    #Index<PersistedEmote>([\.scope], [\.emoteSetId], [\.ownerId])

    init(
        key: String,
        scope: String,
        emoteId: String,
        name: String,
        formatRaw: String,
        emoteType: String?,
        emoteSetId: String?,
        ownerId: String?,
        updatedAt: Date
    ) {
        self.key = key
        self.scope = scope
        self.emoteId = emoteId
        self.name = name
        self.formatRaw = formatRaw
        self.emoteType = emoteType
        self.emoteSetId = emoteSetId
        self.ownerId = ownerId
        self.updatedAt = updatedAt
    }
}

// MARK: - PersistedChannel

/// チャンネルの永続化モデル（PR-2 では枠確保のみ、PR-3 以降で使用）
@Model
final class PersistedChannel {
    /// 主キー（Twitch の room-id タグ）
    @Attribute(.unique) var roomId: String
    /// 最終更新日時
    var updatedAt: Date

    init(roomId: String, updatedAt: Date) {
        self.roomId = roomId
        self.updatedAt = updatedAt
    }
}

// MARK: - PersistedChatMessage

/// チャットメッセージの永続化モデル
///
/// badges と emotes は JSON 文字列で保存。segments は toDomain() 時に再生成する。
/// tmiSentAt / senderUserId は V1 枠確保のみ（将来の軽量マイグレーション用）。
@Model
final class PersistedChatMessage {
    /// 主キー（Twitch の message id または UUID）
    @Attribute(.unique) var id: String
    var username: String
    var displayName: String
    /// メッセージ本文（全文検索インデックス対象）
    var text: String
    var colorHex: String?
    /// [Badge] を JSONEncoder でエンコードした文字列
    var badgesRaw: String
    /// [EmotePosition] を JSONEncoder でエンコードした文字列
    var emotesRaw: String
    /// チャンネルの room-id（インデックス対象）
    var roomId: String?
    var isAction: Bool
    /// 受信日時（降順ソート・before フィルタ用、インデックス対象）
    var receivedAt: Date
    var replyParentMsgId: String?
    var isOptimistic: Bool
    var replyParentUserLogin: String?
    var replyParentDisplayName: String?
    var replyParentMsgBody: String?
    var isSystemNotice: Bool
    /// V1 枠確保（tmi-sent-ts タグのパース後に充填予定）
    var tmiSentAt: Date?
    /// V1 枠確保（user-id タグのパース後に充填予定）
    var senderUserId: String?

    #Index<PersistedChatMessage>([\.roomId], [\.receivedAt], [\.text])

    init(
        id: String,
        username: String,
        displayName: String,
        text: String,
        colorHex: String?,
        badgesRaw: String,
        emotesRaw: String,
        roomId: String?,
        isAction: Bool,
        receivedAt: Date,
        replyParentMsgId: String?,
        isOptimistic: Bool,
        replyParentUserLogin: String?,
        replyParentDisplayName: String?,
        replyParentMsgBody: String?,
        isSystemNotice: Bool,
        tmiSentAt: Date?,
        senderUserId: String?
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.text = text
        self.colorHex = colorHex
        self.badgesRaw = badgesRaw
        self.emotesRaw = emotesRaw
        self.roomId = roomId
        self.isAction = isAction
        self.receivedAt = receivedAt
        self.replyParentMsgId = replyParentMsgId
        self.isOptimistic = isOptimistic
        self.replyParentUserLogin = replyParentUserLogin
        self.replyParentDisplayName = replyParentDisplayName
        self.replyParentMsgBody = replyParentMsgBody
        self.isSystemNotice = isSystemNotice
        self.tmiSentAt = tmiSentAt
        self.senderUserId = senderUserId
    }
}

// MARK: - PersistedBadgeVersion

/// バッジバージョンの永続化モデル
///
/// compositeKey は "<scopeRaw>|<setId>|<version>" 形式。
/// description はプロトコルメソッドと衝突するため badgeDescription として保存。
@Model
final class PersistedBadgeVersion {
    /// 主キー（"<scopeRaw>|<setId>|<version>"）
    @Attribute(.unique) var compositeKey: String
    /// スコープ文字列（"global" / "channel:<broadcasterId>"）（インデックス対象）
    var scope: String
    var setId: String
    var version: String
    var imageUrl1x: String
    var imageUrl2x: String
    var imageUrl4x: String
    var title: String?
    /// BadgeVersionSnapshot.description に対応（Swift の description と衝突回避のため命名変更）
    var badgeDescription: String?
    var updatedAt: Date

    #Index<PersistedBadgeVersion>([\.scope])

    init(
        compositeKey: String,
        scope: String,
        setId: String,
        version: String,
        imageUrl1x: String,
        imageUrl2x: String,
        imageUrl4x: String,
        title: String?,
        badgeDescription: String?,
        updatedAt: Date
    ) {
        self.compositeKey = compositeKey
        self.scope = scope
        self.setId = setId
        self.version = version
        self.imageUrl1x = imageUrl1x
        self.imageUrl2x = imageUrl2x
        self.imageUrl4x = imageUrl4x
        self.title = title
        self.badgeDescription = badgeDescription
        self.updatedAt = updatedAt
    }
}

// MARK: - PersistedUser

/// ユーザープロフィールの永続化モデル
@Model
final class PersistedUser {
    /// 主キー（Twitch の user-id）
    @Attribute(.unique) var userId: String
    /// ログイン名（インデックス対象）
    var login: String
    var displayName: String
    var profileImageUrl: String?
    var updatedAt: Date

    #Index<PersistedUser>([\.login])

    init(userId: String, login: String, displayName: String, profileImageUrl: String?, updatedAt: Date) {
        self.userId = userId
        self.login = login
        self.displayName = displayName
        self.profileImageUrl = profileImageUrl
        self.updatedAt = updatedAt
    }
}

// MARK: - PersistedImageAsset

/// 画像バイナリの永続化モデル（BLOB は外部ファイルに分離）
///
/// cacheKey は "<kindRaw>:<identifier>" 形式。
/// lastAccessedAt は LRU eviction の軸として使用する。
@Model
final class PersistedImageAsset {
    /// 主キー（"<kindRaw>:<identifier>"）
    @Attribute(.unique) var cacheKey: String
    /// 画像種別文字列（"emote" / "badge" / "profile"）（インデックス対象）
    var kind: String
    var identifier: String
    /// 画像バイナリ（外部ファイルに分離して保存）
    @Attribute(.externalStorage) var data: Data
    var mime: String
    /// 最終アクセス日時（LRU eviction 用、インデックス対象）
    var lastAccessedAt: Date
    var createdAt: Date

    #Index<PersistedImageAsset>([\.kind], [\.lastAccessedAt])

    init(cacheKey: String, kind: String, identifier: String, data: Data, mime: String, lastAccessedAt: Date, createdAt: Date) {
        self.cacheKey = cacheKey
        self.kind = kind
        self.identifier = identifier
        self.data = data
        self.mime = mime
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
    }
}

// MARK: - VersionedSchema

/// SwiftData スキーマバージョン1
///
/// 全 @Model クラスを列挙する。将来のマイグレーションで `stages` に追加する。
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PersistedEmote.self,
            PersistedChannel.self,
            PersistedChatMessage.self,
            PersistedBadgeVersion.self,
            PersistedUser.self,
            PersistedImageAsset.self
        ]
    }
}

// MARK: - SchemaMigrationPlan

/// チャットスキーマのマイグレーション計画
///
/// V1 単独でスタート。V1 → V2 への破壊的変更が発生した際に `stages` に追加する。
enum ChatSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
