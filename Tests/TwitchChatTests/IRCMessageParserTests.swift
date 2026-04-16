// IRCMessageParserTests.swift
// IRCMessageParser の単体テスト
// 各種 IRC メッセージ形式のパースを検証する

import Testing
@testable import TwitchChat

/// IRCMessageParser のテストスイート
@Suite("IRCMessageParser テスト")
struct IRCMessageParserTests {

    // MARK: - PING メッセージ

    @Test("PING メッセージをパースできる")
    func pingメッセージをパースできる() {
        let rawMessage = "PING :tmi.twitch.tv"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "PING")
        #expect(result?.trailing == "tmi.twitch.tv")
        #expect(result?.tags.isEmpty == true)
    }

    // MARK: - PRIVMSG メッセージ（タグなし）

    @Test("タグなし PRIVMSG をパースできる")
    func タグなしPRIVMSGをパースできる() {
        let rawMessage = ":ユーザー名!ユーザー名@ユーザー名.tmi.twitch.tv PRIVMSG #テストチャンネル :こんにちは世界"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "PRIVMSG")
        #expect(result?.prefix == "ユーザー名!ユーザー名@ユーザー名.tmi.twitch.tv")
        #expect(result?.params == ["#テストチャンネル"])
        #expect(result?.trailing == "こんにちは世界")
        #expect(result?.tags.isEmpty == true)
    }

    // MARK: - PRIVMSG メッセージ（タグあり）

    @Test("タグ付き PRIVMSG をパースできる")
    func タグ付きPRIVMSGをパースできる() {
        let rawMessage = "@badge-info=subscriber/6;badges=subscriber/6;color=#FF0000;display-name=テストユーザー;emotes=;id=abc-123;mod=0;subscriber=1;tmi-sent-ts=1700000000000;user-id=12345 :testuser!testuser@testuser.tmi.twitch.tv PRIVMSG #テストチャンネル :これはテストメッセージです"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "PRIVMSG")
        #expect(result?.tags["display-name"] == "テストユーザー")
        #expect(result?.tags["color"] == "#FF0000")
        #expect(result?.tags["subscriber"] == "1")
        #expect(result?.tags["user-id"] == "12345")
        #expect(result?.trailing == "これはテストメッセージです")
    }

    @Test("broadcaster バッジを持つ PRIVMSG をパースできる")
    func broadcasterバッジを持つPRIVMSGをパースできる() {
        let rawMessage = "@badges=broadcaster/1,subscriber/12;color=#8A2BE2;display-name=配信者 :haishinsha!haishinsha@haishinsha.tmi.twitch.tv PRIVMSG #haishinsha :配信中です"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.tags["badges"] == "broadcaster/1,subscriber/12")
        #expect(result?.tags["display-name"] == "配信者")
        #expect(result?.tags["color"] == "#8A2BE2")
    }

    // MARK: - JOIN / PART メッセージ

    @Test("JOIN メッセージをパースできる")
    func JOINメッセージをパースできる() {
        let rawMessage = ":testuser!testuser@testuser.tmi.twitch.tv JOIN #テストチャンネル"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "JOIN")
        #expect(result?.params == ["#テストチャンネル"])
    }

    @Test("PART メッセージをパースできる")
    func PARTメッセージをパースできる() {
        let rawMessage = ":testuser!testuser@testuser.tmi.twitch.tv PART #テストチャンネル"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "PART")
        #expect(result?.params == ["#テストチャンネル"])
    }

    // MARK: - CAP ACK

    @Test("CAP ACK レスポンスをパースできる")
    func CAPACKレスポンスをパースできる() {
        let rawMessage = ":tmi.twitch.tv CAP * ACK :twitch.tv/tags twitch.tv/commands"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "CAP")
        #expect(result?.trailing == "twitch.tv/tags twitch.tv/commands")
    }

    // MARK: - エラーハンドリング

    @Test("空文字列はnilを返す")
    func 空文字列はnilを返す() {
        let result = IRCMessageParser.parse("")
        #expect(result == nil)
    }

    @Test("スペースのみの文字列はnilを返す")
    func スペースのみの文字列はnilを返す() {
        let result = IRCMessageParser.parse("   ")
        #expect(result == nil)
    }

    // MARK: - タグのエスケープ

    @Test("タグ値のエスケープシーケンスを正しく変換できる")
    func タグ値のエスケープシーケンスを正しく変換できる() {
        // \s はスペース、\: はセミコロン、\\ はバックスラッシュ
        let rawMessage = "@display-name=テスト\\sユーザー :user!user@user.tmi.twitch.tv PRIVMSG #ch :test"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result?.tags["display-name"] == "テスト ユーザー")
    }

    // MARK: - NOTICE メッセージ

    @Test("msg-id タグ付き NOTICE をパースできる")
    func msgidタグ付きNOTICEをパースできる() {
        // Twitch がレートリミット超過時に返す NOTICE の実際の形式
        let rawMessage = "@msg-id=msg_ratelimit :tmi.twitch.tv NOTICE #haishinsha :You are sending messages too quickly."
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "NOTICE")
        #expect(result?.tags["msg-id"] == "msg_ratelimit")
        #expect(result?.params == ["#haishinsha"])
        #expect(result?.trailing == "You are sending messages too quickly.")
        #expect(result?.prefix == "tmi.twitch.tv")
    }

    @Test("重複メッセージの NOTICE をパースできる")
    func 重複メッセージのNOTICEをパースできる() {
        let rawMessage = "@msg-id=msg_duplicate :tmi.twitch.tv NOTICE #haishinsha :Your message was not sent because it is identical to the previous one you sent, less than 30 seconds ago."
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "NOTICE")
        #expect(result?.tags["msg-id"] == "msg_duplicate")
        #expect(result?.params == ["#haishinsha"])
        #expect(result?.trailing == "Your message was not sent because it is identical to the previous one you sent, less than 30 seconds ago.")
    }

    @Test("msg-id タグなしの NOTICE もパースできる")
    func msgidタグなしのNOTICEもパースできる() {
        // 匿名接続時など、msg-id が付かない NOTICE も IRC メッセージとして解析できる
        let rawMessage = ":tmi.twitch.tv NOTICE * :Login unsuccessful"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "NOTICE")
        #expect(result?.tags["msg-id"] == nil)
        #expect(result?.params == ["*"])
        #expect(result?.trailing == "Login unsuccessful")
    }

    @Test("msg-id=msg_banned の NOTICE をパースできる")
    func msgidmsgbannedのNOTICEをパースできる() {
        let rawMessage = "@msg-id=msg_banned :tmi.twitch.tv NOTICE #haishinsha :You are permanently banned from talking in haishinsha."
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "NOTICE")
        #expect(result?.tags["msg-id"] == "msg_banned")
        #expect(result?.params == ["#haishinsha"])
        #expect(result?.trailing == "You are permanently banned from talking in haishinsha.")
    }

    // MARK: - 数値コマンド（RPL）

    @Test("数値コマンド 001 をパースできる")
    func 数値コマンド001をパースできる() {
        let rawMessage = ":tmi.twitch.tv 001 justinfan12345 :Welcome, GLHF!"
        let result = IRCMessageParser.parse(rawMessage)

        #expect(result != nil)
        #expect(result?.command == "001")
        #expect(result?.trailing == "Welcome, GLHF!")
    }
}
