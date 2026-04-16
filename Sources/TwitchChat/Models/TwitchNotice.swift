// TwitchNotice.swift
// Twitch IRC NOTICE コマンドを表すモデル
// サーバーからの通知（レートリミット超過・BAN・スローモードなど）を保持する

import Foundation

/// Twitch IRC の NOTICE コマンド（サーバーからの通知）
///
/// 認証接続後に `CAP REQ :twitch.tv/commands` を要求している場合、
/// NOTICE には `@msg-id=...` タグが付与され、通知の種類を識別できる。
///
/// 実際の IRC 形式:
/// `@msg-id=msg_ratelimit :tmi.twitch.tv NOTICE #channel :You are sending messages too quickly.`
struct TwitchNotice: Sendable, Equatable {
    /// 通知の種類を識別するタグ（例: "msg_ratelimit", "msg_duplicate"）
    ///
    /// `CAP REQ :twitch.tv/commands` が有効な場合のみ付与される。
    /// 匿名接続時や古い接続では nil になる。
    let msgId: String?

    /// 通知の対象チャンネル名（`#` なし）
    ///
    /// 特定チャンネル向けでない NOTICE（例: ログイン失敗通知）では nil になる。
    let channel: String?

    /// ユーザー向け通知文言（IRC メッセージの trailing 部分）
    ///
    /// 例: "You are sending messages too quickly."
    let message: String
}
