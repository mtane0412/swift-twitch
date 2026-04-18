// ChatMessageTests.swift
// ChatMessage モデルの単体テスト
// IRCMessage からの変換と Badge パースを検証する

import Testing
@testable import TwitchChat

/// ChatMessage モデルのテストスイート
@Suite("ChatMessage テスト")
struct ChatMessageTests {

    // MARK: - IRCMessage からの変換

    @Test("PRIVMSG を ChatMessage に変換できる")
    func PRIVMSGをChatMessageに変換できる() {
        // 前提: タグ付き PRIVMSG メッセージ
        let rawMessage = "@badges=subscriber/6;color=#FF0000;display-name=山田太郎;emotes=;id=abc-123;user-id=99999 :yamadataro!yamadataro@yamadataro.tmi.twitch.tv PRIVMSG #テストチャンネル :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: ChatMessage に正しく変換される
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage != nil)
        #expect(chatMessage?.username == "yamadataro")
        #expect(chatMessage?.displayName == "山田太郎")
        #expect(chatMessage?.text == "こんにちは！")
        #expect(chatMessage?.colorHex == "#FF0000")
    }

    @Test("display-name がない場合は username をフォールバックとして使用する")
    func displayNameがない場合はusernameをフォールバックとして使用する() {
        let rawMessage = ":testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #ch :メッセージ"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.username == "testuser")
        #expect(chatMessage?.displayName == "testuser")
    }

    @Test("PRIVMSG 以外のコマンドは nil を返す")
    func PRIVMSG以外のコマンドはnilを返す() {
        let rawMessage = "PING :tmi.twitch.tv"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage == nil)
    }

    @Test("trailing がない PRIVMSG は nil を返す")
    func trailingがないPRIVMSGはnilを返す() {
        // trailing なし（テキストなし）のメッセージ
        let rawMessage = ":user!user@user.tmi.twitch.tv PRIVMSG #ch"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage == nil)
    }

    // MARK: - Badge のパース

    @Test("broadcaster バッジをパースできる")
    func broadcasterバッジをパースできる() {
        let badgeString = "broadcaster/1"
        let badges = Badge.parse(badgeString)

        #expect(badges.count == 1)
        #expect(badges[0].name == "broadcaster")
        #expect(badges[0].version == "1")
    }

    @Test("複数のバッジをパースできる")
    func 複数のバッジをパースできる() {
        let badgeString = "broadcaster/1,subscriber/12,bits/1000"
        let badges = Badge.parse(badgeString)

        #expect(badges.count == 3)
        #expect(badges[0].name == "broadcaster")
        #expect(badges[1].name == "subscriber")
        #expect(badges[1].version == "12")
        #expect(badges[2].name == "bits")
        #expect(badges[2].version == "1000")
    }

    @Test("空のバッジ文字列は空配列を返す")
    func 空のバッジ文字列は空配列を返す() {
        let badges = Badge.parse("")
        #expect(badges.isEmpty)
    }

    // MARK: - エモートのパース

    @Test("emotes タグが空の場合 segments はテキスト全体の1セグメントになる")
    func emotesタグが空の場合segmentsはテキスト全体の1セグメントになる() {
        // 前提: emotes タグが空（エモートなし）のメッセージ
        let rawMessage = "@emotes=;id=abc-001 :ユーザー001!ユーザー001@ユーザー001.tmi.twitch.tv PRIVMSG #テストチャンネル :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }
        // 検証: segments がテキスト全体の1セグメントになる
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.segments == [.text("こんにちは！")])
        #expect(chatMessage?.emotes.isEmpty == true)
    }

    @Test("emotes タグがある場合 segments にエモートセグメントが含まれる")
    func emotesタグがある場合segmentsにエモートセグメントが含まれる() {
        // 前提: Kappa(0-4) を含むメッセージ
        // "Kappa 配信中" — Kappa は K(0) a(1) p(2) p(3) a(4)
        let rawMessage = "@emotes=25:0-4;id=abc-002 :はいしんしゃ!はいしんしゃ@はいしんしゃ.tmi.twitch.tv PRIVMSG #テストチャンネル :Kappa 配信中"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }
        // 検証: エモート → テキストの2セグメントになる
        guard let chatMessage = ChatMessage(from: ircMessage) else {
            Issue.record("ChatMessage への変換に失敗しました")
            return
        }
        #expect(chatMessage.emotes.count == 1)
        #expect(chatMessage.emotes.first?.emoteId == "25")
        let segments = chatMessage.segments
        #expect(segments.count == 2)
        #expect(segments[0] == .emote(id: "25", name: "Kappa"))
        #expect(segments[1] == .text(" 配信中"))
    }

    @Test("PRIVMSG のバッジタグが正しく ChatMessage に反映される")
    func PRIVMSGのバッジタグが正しくChatMessageに反映される() {
        let rawMessage = "@badges=broadcaster/1,subscriber/12;color=#0000FF;display-name=配信者 :haishinsha!haishinsha@haishinsha.tmi.twitch.tv PRIVMSG #haishinsha :配信開始！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.badges.count == 2)
        #expect(chatMessage?.badges[0].name == "broadcaster")
        #expect(chatMessage?.badges[1].name == "subscriber")
        #expect(chatMessage?.colorHex == "#0000FF")
    }

    @Test("PRIVMSG の room-id タグが roomId プロパティに反映される")
    func PRIVMSGのroomIdタグがroomIdプロパティに反映される() {
        let rawMessage = "@room-id=12345678;display-name=視聴者;color=#FF0000 :viewer!viewer@viewer.tmi.twitch.tv PRIVMSG #haishinsha :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.roomId == "12345678")
    }

    @Test("room-id タグがない場合は roomId が nil になる")
    func roomIdタグがない場合はnilになる() {
        let rawMessage = "@display-name=視聴者;color=#FF0000 :viewer!viewer@viewer.tmi.twitch.tv PRIVMSG #haishinsha :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.roomId == nil)
    }

    @Test("room-id タグが空文字の場合は roomId が nil になる")
    func roomIdタグが空文字の場合はnilになる() {
        let rawMessage = "@room-id=;display-name=視聴者 :viewer!viewer@viewer.tmi.twitch.tv PRIVMSG #haishinsha :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.roomId == nil)
    }

    // MARK: - ACTION（/me コマンド）

    @Test("ACTION 形式の PRIVMSG で isAction が true になりテキストから ACTION プレフィックスが除去される")
    func ACTION形式のPRIVMSGでisActionがtrueになりテキストからACTIONプレフィックスが除去される() {
        // 前提: trailing が "\u{1}ACTION こんにちは\u{1}" の PRIVMSG
        let rawMessage = "@display-name=山田太郎;id=act-001 :yamadataro!yamadataro@yamadataro.tmi.twitch.tv PRIVMSG #テストチャンネル :\u{1}ACTION こんにちは\u{1}"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: isAction が true になり、text から ACTION プレフィックスが除去される
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage != nil)
        #expect(chatMessage?.isAction == true)
        #expect(chatMessage?.text == "こんにちは")
    }

    @Test("通常の PRIVMSG で isAction が false になる")
    func 通常のPRIVMSGでisActionがfalseになる() {
        // 前提: 通常の PRIVMSG メッセージ
        let rawMessage = "@display-name=山田太郎;id=msg-001 :yamadataro!yamadataro@yamadataro.tmi.twitch.tv PRIVMSG #テストチャンネル :こんにちは！"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: isAction が false になる
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.isAction == false)
        #expect(chatMessage?.text == "こんにちは！")
    }

    @Test("ACTION 形式の PRIVMSG でも segments は ACTION 除去後のテキストで生成される")
    func ACTION形式のPRIVMSGでもsegmentsはACTION除去後のテキストで生成される() {
        // 前提: ACTION 形式でテキストのみ（エモートなし）
        let rawMessage = "@display-name=配信者;id=act-002;emotes= :haishinsha!haishinsha@haishinsha.tmi.twitch.tv PRIVMSG #テストチャンネル :\u{1}ACTION 配信中です\u{1}"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: segments が ACTION 除去後のテキストで1セグメントになる
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.isAction == true)
        #expect(chatMessage?.text == "配信中です")
        #expect(chatMessage?.segments == [.text("配信中です")])
    }

    @Test("ACTION 形式の PRIVMSG にエモートが含まれる場合 segments にエモートが含まれる")
    func ACTION形式のPRIVMSGにエモートが含まれる場合segmentsにエモートが含まれる() {
        // 前提: ACTION 形式で Kappa(0-4) を含むメッセージ
        // Twitch IRC ではエモートのオフセットは ACTION 本文に対するものとして送信される
        // "Kappa 配信中" — Kappa は K(0) a(1) p(2) p(3) a(4)
        let rawMessage = "@display-name=配信者;id=act-003;emotes=25:0-4 :haishinsha!haishinsha@haishinsha.tmi.twitch.tv PRIVMSG #テストチャンネル :\u{1}ACTION Kappa 配信中\u{1}"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: ACTION プレフィックス除去後のテキストでエモートセグメントが生成される
        guard let chatMessage = ChatMessage(from: ircMessage) else {
            Issue.record("ChatMessage への変換に失敗しました")
            return
        }
        #expect(chatMessage.isAction == true)
        #expect(chatMessage.text == "Kappa 配信中")
        #expect(chatMessage.emotes.count == 1)
        let segments = chatMessage.segments
        #expect(segments.count == 2)
        #expect(segments[0] == .emote(id: "25", name: "Kappa"))
        #expect(segments[1] == .text(" 配信中"))
    }

    // MARK: - 楽観的 UI 用イニシャライザ

    @Test("楽観的 UI 用イニシャライザで isAction を true に指定できる")
    func 楽観的UI用イニシャライザでisActionをtrueに指定できる() {
        // 前提: /me コマンドの楽観的 UI 表示用メッセージ（本文のみ指定）
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            displayName: "山田太郎",
            text: "手を振る",
            isAction: true
        )

        // 検証: isAction が true になり、text は本文のみになる
        #expect(chatMessage.isAction == true)
        #expect(chatMessage.text == "手を振る")
    }

    @Test("楽観的 UI 用イニシャライザで isAction を省略すると false になる")
    func 楽観的UI用イニシャライザでisActionを省略するとfalseになる() {
        // 前提: 通常メッセージの楽観的 UI 表示用（isAction 省略）
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            text: "普通のメッセージ"
        )

        // 検証: isAction がデフォルト値の false になる
        #expect(chatMessage.isAction == false)
    }

    @Test("楽観的 UI 用イニシャライザで ChatMessage を生成できる")
    func 楽観的UI用イニシャライザでChatMessageを生成できる() {
        // 前提: ローカルユーザー名とテキストを指定
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            displayName: "山田太郎",
            text: "こんにちは！",
            roomId: "12345678"
        )

        // 検証: 各フィールドが期待通りに設定される
        #expect(chatMessage.username == "yamadataro")
        #expect(chatMessage.displayName == "山田太郎")
        #expect(chatMessage.text == "こんにちは！")
        #expect(chatMessage.roomId == "12345678")
        #expect(chatMessage.colorHex == nil)
        #expect(chatMessage.badges.isEmpty)
        #expect(chatMessage.emotes.isEmpty)
        #expect(!chatMessage.id.isEmpty)
    }

    @Test("楽観的 UI 用イニシャライザで displayName を省略すると username にフォールバックされる")
    func 楽観的UI用イニシャライザでdisplayNameを省略するとusernameにフォールバックされる() {
        // 前提: displayName を省略して生成
        let chatMessage = ChatMessage(
            localUsername: "testviewer",
            text: "テストメッセージ"
        )

        // 検証: displayName が username と同じになる
        #expect(chatMessage.username == "testviewer")
        #expect(chatMessage.displayName == "testviewer")
    }

    @Test("楽観的 UI 用イニシャライザで segments はテキスト全体の1セグメントになる")
    func 楽観的UI用イニシャライザでsegmentsはテキスト全体の1セグメントになる() {
        // 前提: テキストを指定して生成（エモートなし）
        let chatMessage = ChatMessage(
            localUsername: "haishinshaA",
            text: "配信開始！"
        )

        // 検証: segments がテキスト全体の1セグメントになる
        #expect(chatMessage.segments == [.text("配信開始！")])
        #expect(chatMessage.emotes.isEmpty)
    }

    @Test("楽観的 UI 用イニシャライザで生成した id は一意な UUID 形式になる")
    func 楽観的UI用イニシャライザで生成したidは一意なUUID形式になる() {
        // 前提: 同じパラメータで2つのメッセージを生成
        let message1 = ChatMessage(localUsername: "視聴者001", text: "同じメッセージ")
        let message2 = ChatMessage(localUsername: "視聴者001", text: "同じメッセージ")

        // 検証: id が異なる（UUID によるユニーク保証）
        #expect(message1.id != message2.id)
        #expect(!message1.id.isEmpty)
    }

    @Test("楽観的 UI 用イニシャライザで colorHex と badges を渡した場合にセットされる")
    func 楽観的UI用イニシャライザでcolorHexとbadgesを渡した場合にセットされる() {
        // 前提: USERSTATE から取得した color と badges を指定して生成
        let badges = [Badge(name: "moderator", version: "1"), Badge(name: "subscriber", version: "12")]
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            displayName: "山田太郎",
            text: "こんにちは！",
            roomId: "12345678",
            colorHex: "#1E90FF",
            badges: badges
        )

        // 検証: colorHex と badges が正しくセットされる
        #expect(chatMessage.colorHex == "#1E90FF")
        #expect(chatMessage.badges == badges)
    }

    @Test("楽観的 UI 用イニシャライザで colorHex と badges を省略した場合はデフォルト値になる")
    func 楽観的UI用イニシャライザでcolorHexとbadgesを省略した場合はデフォルト値になる() {
        // 前提: colorHex / badges を省略して生成（従来の呼び出し方）
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            displayName: "山田太郎",
            text: "こんにちは！"
        )

        // 検証: colorHex は nil、badges は空配列（後方互換）
        #expect(chatMessage.colorHex == nil)
        #expect(chatMessage.badges.isEmpty)
    }

    // MARK: - 返信（Reply）

    @Test("返信タグ付き PRIVMSG から返信メタデータが読み取れる")
    func 返信タグ付きPRIVMSGから返信メタデータが読み取れる() {
        // 前提: reply-parent-* タグを含む PRIVMSG
        let rawMessage = "@reply-parent-msg-id=親メッセージid-123;reply-parent-user-login=oyausername;reply-parent-display-name=親ユーザー;reply-parent-msg-body=元のメッセージ内容;display-name=返信者;id=reply-001 :henshinsha!henshinsha@henshinsha.tmi.twitch.tv PRIVMSG #ch :返信テキスト"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: 4つの返信メタデータが正しく読み取られる
        guard let chatMessage = ChatMessage(from: ircMessage) else {
            Issue.record("ChatMessage への変換に失敗しました")
            return
        }
        #expect(chatMessage.replyParentMsgId == "親メッセージid-123")
        #expect(chatMessage.replyParentUserLogin == "oyausername")
        #expect(chatMessage.replyParentDisplayName == "親ユーザー")
        #expect(chatMessage.replyParentMsgBody == "元のメッセージ内容")
    }

    @Test("返信タグがない PRIVMSG では返信メタデータが全て nil になる")
    func 返信タグがないPRIVMSGでは返信メタデータが全てnilになる() {
        // 前提: 通常のタグ付き PRIVMSG（reply タグなし）
        let rawMessage = "@badges=subscriber/6;color=#FF0000;display-name=山田太郎;id=abc-123 :yamadataro!yamadataro@yamadataro.tmi.twitch.tv PRIVMSG #ch :通常メッセージ"
        guard let ircMessage = IRCMessageParser.parse(rawMessage) else {
            Issue.record("IRCMessage のパースに失敗しました")
            return
        }

        // 検証: 返信メタデータが全て nil になる
        guard let chatMessage = ChatMessage(from: ircMessage) else {
            Issue.record("ChatMessage への変換に失敗しました")
            return
        }
        #expect(chatMessage.replyParentMsgId == nil)
        #expect(chatMessage.replyParentUserLogin == nil)
        #expect(chatMessage.replyParentDisplayName == nil)
        #expect(chatMessage.replyParentMsgBody == nil)
    }

    @Test("楽観的 UI 用イニシャライザで replyParentMsgId を指定できる")
    func 楽観的UI用イニシャライザでreplyParentMsgIdを指定できる() {
        // 前提: 返信送信時に返信先メッセージ ID を指定
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            displayName: "山田太郎",
            text: "返信メッセージ",
            replyParentMsgId: "親メッセージid-456"
        )

        // 検証: replyParentMsgId が設定される
        #expect(chatMessage.replyParentMsgId == "親メッセージid-456")
    }

    @Test("楽観的 UI 用イニシャライザで replyParentMsgId を省略すると nil になる")
    func 楽観的UI用イニシャライザでreplyParentMsgIdを省略するとnilになる() {
        // 前提: replyParentMsgId を省略して生成（通常メッセージ、後方互換）
        let chatMessage = ChatMessage(
            localUsername: "yamadataro",
            text: "通常メッセージ"
        )

        // 検証: replyParentMsgId が nil になる
        #expect(chatMessage.replyParentMsgId == nil)
    }
}
