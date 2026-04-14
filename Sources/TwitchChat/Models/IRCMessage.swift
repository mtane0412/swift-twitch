// IRCMessage.swift
// パース済み IRC メッセージを表す構造体
// RFC 1459 形式に Twitch 固有のタグ（IRCv3）を加えた構造を表現する

import Foundation

/// パース済み IRC メッセージ
///
/// IRC メッセージの形式:
/// `[@tags] [:prefix] <command> [params] [:trailing]`
///
/// - Note: Twitch IRC では IRCv3 のタグ拡張が使用される
struct IRCMessage: Sendable {
    /// IRCv3 タグ（`@key=value;key2=value2` 形式）
    let tags: [String: String]

    /// メッセージのプレフィックス（送信者情報: `nick!user@host` 形式）
    let prefix: String?

    /// IRC コマンド（例: PING, PRIVMSG, JOIN, 001 など）
    let command: String

    /// コマンドのパラメータ（trailing を除く）
    let params: [String]

    /// メッセージの trailing 部分（`:` の後ろの文字列）
    let trailing: String?
}
