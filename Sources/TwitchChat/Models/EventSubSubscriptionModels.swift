// EventSubSubscriptionModels.swift
// Twitch Helix API を使った EventSub サブスクリプション登録・削除のリクエスト/レスポンスモデル
//
// EventSub WebSocket の subscription 登録には、Welcome メッセージで取得した session_id が必要。
// POST https://api.twitch.tv/helix/eventsub/subscriptions
// DELETE https://api.twitch.tv/helix/eventsub/subscriptions?id={subscription_id}

import Foundation

// MARK: - サブスクリプション登録リクエスト

/// EventSub サブスクリプション登録リクエストボディ
///
/// Helix API `POST /eventsub/subscriptions` に送信する。
struct EventSubSubscriptionRequest: Encodable, Sendable {
    /// 購読するイベントの種別（例: "channel.chat.message"）
    let type: String

    /// イベントのバージョン（例: "1"）
    let version: String

    /// イベントの配信条件
    let condition: EventSubCondition

    /// イベントの配信トランスポート（WebSocket セッション）
    let transport: EventSubTransport
}

/// EventSub サブスクリプション条件
///
/// `channel.chat.message` の場合:
/// - `broadcasterUserId`: メッセージを受信するチャンネルのオーナー ID
/// - `userId`: 認証済みユーザー ID（自分のユーザー ID）
struct EventSubCondition: Encodable, Sendable {
    /// チャンネルオーナーのユーザー ID
    let broadcasterUserId: String

    /// 認証済みユーザー ID（自分の ID）
    let userId: String

    enum CodingKeys: String, CodingKey {
        case broadcasterUserId = "broadcaster_user_id"
        case userId = "user_id"
    }
}

/// EventSub WebSocket トランスポート設定
struct EventSubTransport: Encodable, Sendable {
    /// トランスポート方式（"websocket" 固定）
    let method: String

    /// EventSub WebSocket の Welcome メッセージで受信したセッション ID
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case method
        case sessionId = "session_id"
    }
}

// MARK: - サブスクリプション登録レスポンス

/// EventSub サブスクリプション登録レスポンス
struct EventSubSubscriptionResponse: Decodable, Sendable {
    /// 登録されたサブスクリプション一覧（通常は 1 件）
    let data: [EventSubSubscriptionData]
}

/// 登録済みサブスクリプションの詳細
struct EventSubSubscriptionData: Decodable, Sendable {
    /// サブスクリプションの一意な識別子
    ///
    /// `DELETE /eventsub/subscriptions?id=` で削除する際に使用する。
    let id: String

    /// サブスクリプションの状態（"enabled", "webhook_callback_verification_pending" 等）
    let status: String

    /// サブスクリプション種別（例: "channel.chat.message"）
    let type: String
}
