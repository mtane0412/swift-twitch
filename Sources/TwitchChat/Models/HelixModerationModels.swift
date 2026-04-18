// HelixModerationModels.swift
// Twitch Helix API モデレーション関連のリクエスト/レスポンス型
// POST /moderation/bans, PATCH /chat/settings, DELETE /chat/messages で使用する

import Foundation

// MARK: - BAN 関連

/// POST /moderation/bans のリクエストボディ
///
/// `duration` を省略すると永久BAN、設定するとタイムアウトとなる
struct HelixBanRequest: Encodable, Sendable {
    /// バン対象ユーザーの情報
    let data: BanData

    struct BanData: Encodable, Sendable {
        /// バン対象のユーザー ID
        let userId: String
        /// タイムアウト秒数（省略時は永久BAN）
        let duration: Int?
        /// バン理由（省略可）
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case duration
            case reason
        }
    }
}

// MARK: - チャット設定関連

/// PATCH /chat/settings のリクエストボディ
///
/// 変更したいフィールドのみ設定する（nil は変更なし）
struct HelixChatSettingsRequest: Encodable, Sendable {
    /// エモート限定モード
    let emoteMode: Bool?
    /// スローモード
    let slowMode: Bool?
    /// スローモード待機秒数
    let slowModeWaitTime: Int?
    /// サブスクライバー限定モード
    let subscriberMode: Bool?
    /// フォロワー限定モード
    let followerMode: Bool?
    /// フォロワー限定モードの最低フォロー期間（分）
    let followerModeDuration: Int?
    /// ユニークチャットモード
    let uniqueChatMode: Bool?

    enum CodingKeys: String, CodingKey {
        case emoteMode = "emote_mode"
        case slowMode = "slow_mode"
        case slowModeWaitTime = "slow_mode_wait_time"
        case subscriberMode = "subscriber_mode"
        case followerMode = "follower_mode"
        case followerModeDuration = "follower_mode_duration"
        case uniqueChatMode = "unique_chat_mode"
    }

    /// emote_mode のみ設定するイニシャライザ
    static func emoteOnly(_ enabled: Bool) -> Self {
        Self(
            emoteMode: enabled,
            slowMode: nil, slowModeWaitTime: nil,
            subscriberMode: nil,
            followerMode: nil, followerModeDuration: nil,
            uniqueChatMode: nil
        )
    }

    /// slow_mode のみ設定するイニシャライザ
    static func slow(enabled: Bool, waitTime: Int?) -> Self {
        Self(
            emoteMode: nil,
            slowMode: enabled, slowModeWaitTime: enabled ? (waitTime ?? 30) : nil,
            subscriberMode: nil,
            followerMode: nil, followerModeDuration: nil,
            uniqueChatMode: nil
        )
    }

    /// subscriber_mode のみ設定するイニシャライザ
    static func subscribers(_ enabled: Bool) -> Self {
        Self(
            emoteMode: nil,
            slowMode: nil, slowModeWaitTime: nil,
            subscriberMode: enabled,
            followerMode: nil, followerModeDuration: nil,
            uniqueChatMode: nil
        )
    }

    /// follower_mode のみ設定するイニシャライザ
    ///
    /// - Parameter duration: フォロワー期間（分）。デフォルトは 0 分（すぐフォローで参加可能）
    static func followers(enabled: Bool, duration: Int?) -> Self {
        Self(
            emoteMode: nil,
            slowMode: nil, slowModeWaitTime: nil,
            subscriberMode: nil,
            followerMode: enabled, followerModeDuration: enabled ? (duration.map { $0 * 60 } ?? 0) : nil,
            uniqueChatMode: nil
        )
    }

    /// unique_chat_mode のみ設定するイニシャライザ
    static func uniqueChat(_ enabled: Bool) -> Self {
        Self(
            emoteMode: nil,
            slowMode: nil, slowModeWaitTime: nil,
            subscriberMode: nil,
            followerMode: nil, followerModeDuration: nil,
            uniqueChatMode: enabled
        )
    }
}
