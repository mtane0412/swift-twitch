// EventSubModels.swift
// Twitch EventSub WebSocket で受信するメッセージの Codable モデル定義
//
// EventSub WebSocket は JSON ベースのプロトコル。
// 全メッセージはトップレベルの EventSubMessage として受信し、
// metadata.messageType でメッセージ種別を判別する。
//
// 参考: https://dev.twitch.tv/docs/eventsub/handling-websocket-events/

import Foundation

// MARK: - トップレベルメッセージ

/// EventSub WebSocket で受信するメッセージのトップレベルモデル
///
/// すべてのメッセージが共通の envelope 構造を持ち、
/// `metadata.messageType` でメッセージ種別を判別する。
struct EventSubMessage: Decodable {
    let metadata: EventSubMetadata
    let payload: EventSubPayload
}

// MARK: - メタデータ

/// EventSub メッセージのメタデータ
///
/// 全メッセージ共通のヘッダー情報を保持する。
struct EventSubMetadata: Decodable {
    /// メッセージの一意な識別子
    let messageId: String

    /// メッセージ種別
    let messageType: EventSubMessageType

    /// メッセージのタイムスタンプ（ISO8601）
    let messageTimestamp: String

    /// サブスクリプション種別（notification/revocation のみ存在）
    let subscriptionType: String?

    /// サブスクリプションバージョン（notification/revocation のみ存在）
    let subscriptionVersion: String?
}

/// EventSub メッセージ種別
enum EventSubMessageType: String, Decodable {
    /// 接続確立（session_id を含む）
    case sessionWelcome = "session_welcome"
    /// keepalive（ペイロードなし）
    case sessionKeepalive = "session_keepalive"
    /// 再接続要求（新しい WebSocket URL を含む）
    case sessionReconnect = "session_reconnect"
    /// イベント通知（購読イベントのデータを含む）
    case notification = "notification"
    /// サブスクリプション失効
    case revocation = "revocation"
    /// 将来追加される可能性のある未知の種別
    case unknown

    /// 未知の raw value は .unknown に fallback する
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = EventSubMessageType(rawValue: raw) ?? .unknown
    }
}

// MARK: - ペイロード

/// EventSub メッセージのペイロード
///
/// メッセージ種別によって含まれるフィールドが異なる。
/// session_welcome / session_reconnect: `session` が存在
/// notification: `subscription` + `event` が存在
/// revocation: `subscription` が存在
/// session_keepalive: 全フィールド nil
struct EventSubPayload: Decodable {
    /// セッション情報（session_welcome / session_reconnect）
    let session: EventSubSession?

    /// サブスクリプション情報（notification / revocation）
    let subscription: EventSubSubscriptionInfo?

    /// イベントデータ（notification のみ）
    let event: EventSubChatEvent?
}

/// EventSub セッション情報
///
/// session_welcome / session_reconnect メッセージのペイロードに含まれる。
struct EventSubSession: Decodable {
    /// セッションの一意な識別子
    ///
    /// Helix API でサブスクリプション登録する際に transport.session_id として使用する。
    let id: String

    /// セッションの状態（"connected", "reconnecting" 等）
    let status: String

    /// keepalive タイムアウト秒数
    ///
    /// この時間内に keepalive または notification が届かない場合は再接続が必要。
    /// session_reconnect では null。
    let keepaliveTimeoutSeconds: Int?

    /// 再接続先 WebSocket URL（session_reconnect のみ）
    let reconnectUrl: String?
}

/// サブスクリプション情報（notification / revocation 用）
///
/// notification メッセージのペイロードに含まれるが、
/// 現在は event フィールドのみ使用するため最小限の定義にとどめる。
struct EventSubSubscriptionInfo: Decodable {
    let id: String
    let status: String
    let type: String
}

// MARK: - チャットメッセージイベント

/// channel.chat.message EventSub イベント
///
/// notification メッセージの payload.event として受信する。
/// 自分が送信したメッセージも含む全チャットメッセージを配信する。
struct EventSubChatEvent: Decodable, Sendable {
    /// チャンネルオーナーのユーザー ID
    let broadcasterUserId: String

    /// チャンネルオーナーのログイン名（小文字）
    let broadcasterUserLogin: String

    /// 発言者のユーザー ID
    let chatterUserId: String

    /// 発言者のログイン名（小文字）
    let chatterUserLogin: String

    /// メッセージの本物の一意な識別子
    ///
    /// Twitch サーバーが割り当てる ID。
    /// 楽観的 UI メッセージのローカル UUID をこの ID で差し替えることで返信機能を有効化する。
    let messageId: String

    /// メッセージ本文
    let message: EventSubChatMessageContent
}

/// EventSub チャットメッセージの本文
struct EventSubChatMessageContent: Decodable, Sendable {
    /// メッセージテキスト（プレーンテキスト形式）
    let text: String
}
