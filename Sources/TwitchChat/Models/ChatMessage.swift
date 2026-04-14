// ChatMessage.swift
// 表示用チャットメッセージとバッジ情報を表す構造体
// Twitch IRC の PRIVMSG から変換して UI 表示に使用する

import Foundation

/// Twitch チャットのバッジ情報
///
/// バッジ文字列 `"broadcaster/1"` を名前とバージョンに分解して保持する
struct Badge: Sendable, Equatable {
    /// バッジ名（例: "broadcaster", "subscriber", "moderator"）
    let name: String

    /// バッジのバージョン（例: "1", "12", "1000"）
    let version: String

    /// バッジ文字列を Badge 配列にパースする
    ///
    /// - Parameter badgesString: カンマ区切りのバッジ文字列（例: `"broadcaster/1,subscriber/12"`）
    /// - Returns: パースされた Badge の配列
    static func parse(_ badgesString: String) -> [Badge] {
        guard !badgesString.isEmpty else { return [] }
        return badgesString
            .split(separator: ",")
            .compactMap { pair -> Badge? in
                let parts = pair.split(separator: "/", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return Badge(name: String(parts[0]), version: String(parts[1]))
            }
    }
}

/// 表示用チャットメッセージ
///
/// IRCMessage の PRIVMSG から変換し、チャット UI に表示するために使用する
struct ChatMessage: Sendable, Identifiable {
    /// メッセージの一意な識別子（Twitch の message id、なければ UUID）
    let id: String

    /// IRC のユーザー名（小文字）
    let username: String

    /// 表示名（日本語や大文字を含む場合あり）
    let displayName: String

    /// メッセージ本文
    let text: String

    /// ユーザーのチャット文字色（16進数形式 `#RRGGBB`、未設定の場合は nil）
    let colorHex: String?

    /// バッジ一覧
    let badges: [Badge]

    /// パース済みエモート位置情報
    let emotes: [EmotePosition]

    /// メッセージのセグメント分割結果（テキストとエモートの交互配列）
    let segments: [MessageSegment]

    /// メッセージの受信時刻
    let receivedAt: Date

    /// IRCMessage から ChatMessage を生成する
    ///
    /// PRIVMSG コマンド以外、または trailing がない場合は nil を返す
    ///
    /// - Parameter ircMessage: パース済み IRCMessage
    /// - Returns: 変換成功時は ChatMessage、失敗時は nil
    init?(from ircMessage: IRCMessage) {
        guard ircMessage.command == "PRIVMSG",
              let text = ircMessage.trailing,
              let rawPrefix = ircMessage.prefix else { return nil }

        // プレフィックス "nick!user@host" から nick 部分を抽出し小文字に正規化
        let username = String(rawPrefix.split(separator: "!").first ?? Substring(rawPrefix)).lowercased()

        self.id = ircMessage.tags["id"] ?? UUID().uuidString
        self.username = username
        self.displayName = ircMessage.tags["display-name"]?.isEmpty == false
            ? ircMessage.tags["display-name"]!
            : username
        self.text = text
        self.colorHex = ircMessage.tags["color"]?.isEmpty == false ? ircMessage.tags["color"] : nil
        self.badges = Badge.parse(ircMessage.tags["badges"] ?? "")
        let parsedEmotes = EmoteParser.parse(ircMessage.tags["emotes"] ?? "")
        self.emotes = parsedEmotes
        self.segments = MessageSegment.segments(from: text, emotePositions: parsedEmotes)
        self.receivedAt = Date()
    }
}
