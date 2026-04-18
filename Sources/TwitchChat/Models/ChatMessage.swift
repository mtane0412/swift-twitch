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

    /// チャンネルの Twitch ユーザーID（IRCの room-id タグ）
    ///
    /// チャンネル固有バッジ（subscriber 等）のフェッチに使用する
    let roomId: String?

    /// ACTION メッセージ（/me コマンド）かどうか
    ///
    /// IRC の PRIVMSG trailing が `\u{1}ACTION ...\u{1}` 形式の場合に true となる。
    /// true の場合、text には ACTION プレフィックスを除去した本文のみが格納される。
    let isAction: Bool

    /// メッセージの受信時刻
    let receivedAt: Date

    /// 楽観的 UI 表示のためのローカル ChatMessage を生成する
    ///
    /// Twitch IRC は自分が送信した PRIVMSG をエコーバックしないため、
    /// 送信直後にローカルで ChatMessage を組み立てて表示リストに追加する際に使用する。
    /// エモートは未解決のためセグメントはテキスト全体の1要素になる。
    ///
    /// - Parameters:
    ///   - username: 送信者のログイン名（IRC の NICK に使用した小文字の識別子）
    ///   - displayName: 表示名（省略時は username と同じ値を使用）
    ///   - text: 送信したメッセージ本文（/me の場合は本文のみ、プレフィックスなし）
    ///   - isAction: ACTION メッセージ（/me コマンド）かどうか（省略時は false）
    ///   - roomId: 接続中チャンネルの room-id（既知の場合は渡す、省略可）
    ///   - colorHex: チャット文字色（#RRGGBB 形式、USERSTATE から取得した場合に指定）
    ///   - badges: バッジ一覧（USERSTATE から取得した場合に指定）
    init(
        localUsername username: String,
        displayName: String? = nil,
        text: String,
        isAction: Bool = false,
        roomId: String? = nil,
        colorHex: String? = nil,
        badges: [Badge] = []
    ) {
        self.id = UUID().uuidString
        self.username = username
        self.displayName = displayName ?? username
        self.text = text
        self.isAction = isAction
        self.colorHex = colorHex
        self.badges = badges
        self.emotes = []
        self.segments = MessageSegment.segments(from: text, emotePositions: [])
        self.roomId = roomId
        self.receivedAt = Date()
    }

    /// IRCMessage から ChatMessage を生成する
    ///
    /// PRIVMSG コマンド以外、または trailing がない場合は nil を返す
    ///
    /// - Parameter ircMessage: パース済み IRCMessage
    /// - Returns: 変換成功時は ChatMessage、失敗時は nil
    init?(from ircMessage: IRCMessage) {
        guard ircMessage.command == "PRIVMSG",
              let trailing = ircMessage.trailing,
              let rawPrefix = ircMessage.prefix else { return nil }

        // プレフィックス "nick!user@host" から nick 部分を抽出し小文字に正規化
        let username = String(rawPrefix.split(separator: "!").first ?? Substring(rawPrefix)).lowercased()

        // ACTION 形式（/me コマンド）の検出と本文抽出
        // trailing が "\u{1}ACTION 本文\u{1}" の形式かどうかを確認する
        let actionPrefix = "\u{1}ACTION "
        if trailing.hasPrefix(actionPrefix) && trailing.hasSuffix("\u{1}") && trailing.count >= actionPrefix.count + 1 {
            self.isAction = true
            // "\u{1}ACTION " と末尾の "\u{1}" を除去して本文のみを抽出する
            let body = trailing.dropFirst(actionPrefix.count).dropLast()
            self.text = String(body)
        } else {
            self.isAction = false
            self.text = trailing
        }

        self.id = ircMessage.tags["id"] ?? UUID().uuidString
        self.username = username
        self.displayName = ircMessage.tags["display-name"]?.isEmpty == false
            ? ircMessage.tags["display-name"]!
            : username
        self.colorHex = ircMessage.tags["color"].flatMap { $0.isEmpty ? nil : $0 }
        self.badges = Badge.parse(ircMessage.tags["badges"] ?? "")
        self.roomId = ircMessage.tags["room-id"].flatMap { $0.isEmpty ? nil : $0 }
        let parsedEmotes = EmoteParser.parse(ircMessage.tags["emotes"] ?? "")
        self.emotes = parsedEmotes
        self.segments = MessageSegment.segments(from: self.text, emotePositions: parsedEmotes)
        self.receivedAt = Date()
    }
}
