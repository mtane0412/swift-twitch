// ChatSendError.swift
// チャットメッセージ送信エラーの定義
// ChatViewModel で使用する送信エラー型を独立したファイルとして管理する

import Foundation

/// チャットメッセージ送信時のエラー
enum ChatSendError: Error, LocalizedError, Equatable {
    /// 送信テキストが空（トリム後）
    case empty
    /// 送信テキストが 500 文字を超えている
    case tooLong
    /// 送信できる状態でない（未接続・未ログイン・スコープ不足）
    case notReady
    /// クライアント側レートリミット超過（送信前の事前チェック）
    ///
    /// - Parameter retryAfter: 送信可能になるまでの残り秒数
    case clientRateLimited(retryAfter: TimeInterval)
    /// レートリミット超過（msg_ratelimit）
    case rateLimited
    /// 重複メッセージの連投（msg_duplicate）
    case duplicate
    /// エモートオンリーモード（msg_emoteonly）
    case emoteOnly
    /// フォロワー限定モード（msg_followersonly / msg_followersonly_followed / msg_followersonly_zero）
    case followersOnly
    /// サブスクライバー限定モード（msg_subsonly）
    case subscribersOnly
    /// スローモード中（msg_slowmode）
    case slowMode
    /// BAN またはチャンネル停止（msg_banned / msg_channel_suspended / tos_ban）
    case banned
    /// タイムアウト中（msg_timedout）
    case timedOut
    /// メール/電話番号認証が必要（msg_verified_email / msg_requires_verified_phone_number）
    case verificationRequired
    /// 上記以外のサーバー起因エラー（エラー文言をそのまま保持）
    case serverRejected(String)
    /// 未知のスラッシュコマンド（補完候補にないコマンドを入力した場合）
    case unknownCommand(String)
    /// チャンネル接続前でまだ room-id が不明（まだメッセージを受信していない）
    case roomIdNotAvailable
    /// モデレーションコマンドに必要なOAuthスコープが付与されていない
    ///
    /// - Parameter required: 必要なスコープ一覧（例: ["channel:moderate"]）
    case scopeInsufficient(required: [String])

    var errorDescription: String? {
        switch self {
        case .empty:
            return "メッセージを入力してください"
        case .tooLong:
            return "メッセージは500文字以内にしてください"
        case .notReady:
            return "コメントの投稿にはログインが必要です"
        case .clientRateLimited(let retryAfter):
            // retryAfter が 0 以下になる場合でも「あと 1 秒」と表示して混乱を防ぐ
            let seconds = max(1, Int(ceil(retryAfter)))
            return "送信頻度が上限に達しました。あと \(seconds) 秒後に再試行してください"
        case .rateLimited:
            return "メッセージの送信頻度が速すぎます。少し待ってから送信してください"
        case .duplicate:
            return "直前と同じメッセージは連投できません"
        case .emoteOnly:
            return "このチャンネルはエモートのみ送信できます"
        case .followersOnly:
            return "このチャンネルはフォロワー限定モードです"
        case .subscribersOnly:
            return "このチャンネルはサブスクライバー限定モードです"
        case .slowMode:
            return "スローモード中です。時間を空けて送信してください"
        case .banned:
            return "このチャンネルで投稿が制限されています"
        case .timedOut:
            return "タイムアウト中は投稿できません"
        case .verificationRequired:
            return "投稿にはメール/電話番号の認証が必要です"
        case .serverRejected(let message):
            return "送信できませんでした: \(message)"
        case .unknownCommand(let name):
            return "不明なコマンドです: /\(name)"
        case .roomIdNotAvailable:
            return "チャンネル情報を取得中です。しばらくしてから再試行してください"
        case .scopeInsufficient(let required):
            return "このコマンドには追加の権限が必要です（\(required.joined(separator: ", "))）。再ログインしてください"
        }
    }

    /// TwitchNotice を ChatSendError に変換する
    ///
    /// 送信エラーに相当しない NOTICE（情報系通知など）は nil を返す。
    ///
    /// - Parameter notice: サーバーから受信した TwitchNotice
    /// - Returns: 対応する ChatSendError、または変換対象外の場合は nil
    static func from(notice: TwitchNotice) -> ChatSendError? {
        guard let msgId = notice.msgId else { return nil }
        if let mapped = msgIdToError[msgId] {
            return mapped
        }
        // "msg_" プレフィックスを持つ未知の msg-id はサーバー起因エラーとして扱う
        if msgId.hasPrefix("msg_") {
            return .serverRejected(notice.message)
        }
        // 情報系通知（host_on, host_off, raid 等）は nil を返してスキップする
        return nil
    }

    /// msg-id → ChatSendError のマッピングテーブル
    ///
    /// 複数の msg-id が同じエラーに対応する場合は同じ case を指定する。
    private static let msgIdToError: [String: ChatSendError] = {
        let entries: [(String, ChatSendError)] = [
            ("msg_ratelimit",                          .rateLimited),
            ("msg_duplicate",                          .duplicate),
            ("msg_emoteonly",                          .emoteOnly),
            ("msg_followersonly",                      .followersOnly),
            ("msg_followersonly_followed",             .followersOnly),
            ("msg_followersonly_zero",                 .followersOnly),
            ("msg_subsonly",                           .subscribersOnly),
            ("msg_slowmode",                           .slowMode),
            ("msg_banned",                             .banned),
            ("msg_channel_suspended",                  .banned),
            ("tos_ban",                                .banned),
            ("no_permission",                          .banned),
            ("msg_suspended",                          .banned),
            ("msg_timedout",                           .timedOut),
            ("msg_verified_email",                     .verificationRequired),
            ("msg_requires_verified_phone_number",     .verificationRequired)
        ]
        return Dictionary(uniqueKeysWithValues: entries)
    }()
}
