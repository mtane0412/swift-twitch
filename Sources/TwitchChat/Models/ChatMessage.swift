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

    /// 返信先メッセージの一意な識別子（`reply-parent-msg-id` タグ）
    ///
    /// このメッセージが他のメッセージへの返信である場合に設定される。通常メッセージは nil。
    let replyParentMsgId: String?

    /// 楽観的 UI メッセージかどうか（送信直後にローカルで生成したメッセージ）
    ///
    /// true の場合は Twitch サーバーが認識する本物の message ID を持たないため、
    /// このメッセージへの返信機能を無効化する必要がある。
    let isOptimistic: Bool

    /// 返信先ユーザーのログイン名（`reply-parent-user-login` タグ）
    let replyParentUserLogin: String?

    /// 返信先ユーザーの表示名（`reply-parent-display-name` タグ）
    let replyParentDisplayName: String?

    /// 返信先メッセージの本文（`reply-parent-msg-body` タグ）
    let replyParentMsgBody: String?

    /// システム通知メッセージかどうか（モデレーションコマンド成功等のローカル通知）
    ///
    /// true の場合は通常のチャットメッセージではなく、アプリが生成した情報メッセージとして表示する。
    /// ユーザー名やバッジは表示せず、テキストのみをシステムスタイルで表示する。
    let isSystemNotice: Bool

    /// このメッセージが投稿された配信の VOD video_id（Twitch Helix API の video.id）
    ///
    /// ROOMSTATE 受信後に Helix /helix/videos で取得した最新 archive の id をスタンプする。
    /// VOD 保存無効の配信者や archive 未生成のタイミングでは nil になる。
    let videoId: String?

    /// 楽観的 UI 表示のためのローカル ChatMessage を生成する
    ///
    /// Twitch IRC は自分が送信した PRIVMSG をエコーバックしないため、
    /// 送信直後にローカルで ChatMessage を組み立てて表示リストに追加する際に使用する。
    ///
    /// - Parameters:
    ///   - username: 送信者のログイン名（IRC の NICK に使用した小文字の識別子）
    ///   - displayName: 表示名（省略時は username と同じ値を使用）
    ///   - text: 送信したメッセージ本文（/me の場合は本文のみ、プレフィックスなし）
    ///   - isAction: ACTION メッセージ（/me コマンド）かどうか（省略時は false）
    ///   - roomId: 接続中チャンネルの room-id（既知の場合は渡す、省略可）
    ///   - colorHex: チャット文字色（#RRGGBB 形式、USERSTATE から取得した場合に指定）
    ///   - badges: バッジ一覧（USERSTATE から取得した場合に指定）
    ///   - replyParentMsgId: 返信先メッセージの ID（返信送信時に指定、省略可）
    ///   - emotePositions: テキスト内のエモート位置情報（EmoteStore から解決した場合に指定）
    init(
        localUsername username: String,
        displayName: String? = nil,
        text: String,
        isAction: Bool = false,
        roomId: String? = nil,
        colorHex: String? = nil,
        badges: [Badge] = [],
        replyParentMsgId: String? = nil,
        emotePositions: [EmotePosition] = []
    ) {
        self.id = UUID().uuidString
        self.username = username
        self.displayName = displayName ?? username
        self.text = text
        self.isAction = isAction
        self.colorHex = colorHex
        self.badges = badges
        self.emotes = emotePositions
        self.segments = MessageSegment.segments(from: text, emotePositions: emotePositions)
        self.roomId = roomId
        self.receivedAt = Date()
        self.replyParentMsgId = replyParentMsgId
        self.replyParentUserLogin = nil
        self.replyParentDisplayName = nil
        self.replyParentMsgBody = nil
        self.isOptimistic = true
        self.isSystemNotice = false
        self.videoId = nil
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
        let parsedText: String
        if trailing.hasPrefix(actionPrefix) && trailing.hasSuffix("\u{1}") && trailing.count >= actionPrefix.count + 1 {
            self.isAction = true
            // "\u{1}ACTION " と末尾の "\u{1}" を除去して本文のみを抽出する
            parsedText = String(trailing.dropFirst(actionPrefix.count).dropLast())
        } else {
            self.isAction = false
            parsedText = trailing
        }
        self.text = parsedText

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
        self.segments = MessageSegment.segments(from: parsedText, emotePositions: parsedEmotes)
        self.receivedAt = Date()
        self.replyParentMsgId = ircMessage.tags["reply-parent-msg-id"].flatMap { $0.isEmpty ? nil : $0 }
        self.replyParentUserLogin = ircMessage.tags["reply-parent-user-login"].flatMap { $0.isEmpty ? nil : $0 }
        self.replyParentDisplayName = ircMessage.tags["reply-parent-display-name"].flatMap { $0.isEmpty ? nil : $0 }
        self.replyParentMsgBody = ircMessage.tags["reply-parent-msg-body"].flatMap { $0.isEmpty ? nil : $0 }
        self.isOptimistic = false
        self.isSystemNotice = false
        self.videoId = nil
    }

    /// 楽観的 UI メッセージの ID を EventSub で受信した本物の message ID で差し替えた新しいインスタンスを生成する
    ///
    /// Twitch IRC は自分のメッセージをエコーバックしないため、送信直後は楽観的 UI メッセージとして
    /// ローカル UUID が割り当てられる。EventSub `channel.chat.message` で本物の ID を受信した際に
    /// このイニシャライザで差し替えることで、返信機能が有効化される。
    ///
    /// - Parameters:
    ///   - original: 差し替え元の楽観的 UI メッセージ
    ///   - realId: EventSub から受信した本物の message ID
    init(confirming original: ChatMessage, withRealId realId: String) {
        self.id = realId
        self.username = original.username
        self.displayName = original.displayName
        self.text = original.text
        self.isAction = original.isAction
        self.colorHex = original.colorHex
        self.badges = original.badges
        self.emotes = original.emotes
        self.segments = original.segments
        self.roomId = original.roomId
        self.receivedAt = original.receivedAt
        self.replyParentMsgId = original.replyParentMsgId
        self.replyParentUserLogin = original.replyParentUserLogin
        self.replyParentDisplayName = original.replyParentDisplayName
        self.replyParentMsgBody = original.replyParentMsgBody
        self.isOptimistic = false
        self.isSystemNotice = original.isSystemNotice
        self.videoId = original.videoId
    }

    /// 永続化層からの復元用イニシャライザ（PersistedChatMessage.toDomain() から呼ぶ）
    ///
    /// segments は text と emotePositions から再生成する。
    ///
    /// - Note: このイニシャライザは Persistence 層の DTO 変換にのみ使用する
    init(
        id: String,
        username: String,
        displayName: String,
        text: String,
        colorHex: String?,
        badges: [Badge],
        emotePositions: [EmotePosition],
        roomId: String?,
        isAction: Bool,
        receivedAt: Date,
        replyParentMsgId: String?,
        isOptimistic: Bool,
        replyParentUserLogin: String?,
        replyParentDisplayName: String?,
        replyParentMsgBody: String?,
        isSystemNotice: Bool,
        videoId: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.text = text
        self.colorHex = colorHex
        self.badges = badges
        self.emotes = emotePositions
        self.segments = MessageSegment.segments(from: text, emotePositions: emotePositions)
        self.roomId = roomId
        self.isAction = isAction
        self.receivedAt = receivedAt
        self.replyParentMsgId = replyParentMsgId
        self.isOptimistic = isOptimistic
        self.replyParentUserLogin = replyParentUserLogin
        self.replyParentDisplayName = replyParentDisplayName
        self.replyParentMsgBody = replyParentMsgBody
        self.isSystemNotice = isSystemNotice
        self.videoId = videoId
    }

    /// システム通知メッセージを生成する
    ///
    /// モデレーションコマンドの成功・失敗等、アプリが生成する情報メッセージに使用する。
    ///
    /// - Parameters:
    ///   - text: 表示する通知テキスト
    ///   - roomId: 表示先チャンネルの room-id（省略可）
    init(systemNotice text: String, roomId: String? = nil) {
        self.id = UUID().uuidString
        self.username = ""
        self.displayName = ""
        self.text = text
        self.isAction = false
        self.colorHex = nil
        self.badges = []
        self.emotes = []
        self.segments = MessageSegment.segments(from: text, emotePositions: [])
        self.roomId = roomId
        self.receivedAt = Date()
        self.replyParentMsgId = nil
        self.replyParentUserLogin = nil
        self.replyParentDisplayName = nil
        self.replyParentMsgBody = nil
        self.isOptimistic = false
        self.isSystemNotice = true
        self.videoId = nil
    }
}

// MARK: - roomId / videoId の後付けヘルパー

extension ChatMessage {
    /// roomId と videoId を指定した値で上書きした新しいインスタンスを返す
    ///
    /// flush 時に ROOMSTATE 受信後の `currentRoomId` / Helix 取得後の `currentVideoId` を
    /// 後付けスタンプするために使用する。nil を渡した場合は既存の値を維持する。
    func withRoomIdAndVideoId(roomId: String?, videoId: String?) -> ChatMessage {
        ChatMessage(
            id: id,
            username: username,
            displayName: displayName,
            text: text,
            colorHex: colorHex,
            badges: badges,
            emotePositions: emotes,
            roomId: roomId ?? self.roomId,
            isAction: isAction,
            receivedAt: receivedAt,
            replyParentMsgId: replyParentMsgId,
            isOptimistic: isOptimistic,
            replyParentUserLogin: replyParentUserLogin,
            replyParentDisplayName: replyParentDisplayName,
            replyParentMsgBody: replyParentMsgBody,
            isSystemNotice: isSystemNotice,
            videoId: videoId ?? self.videoId
        )
    }
}
