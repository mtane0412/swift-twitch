// TwitchUserStateTests.swift
// TwitchUserState モデルの単体テスト
// USERSTATE IRCメッセージからのパースを検証する

import Testing
@testable import TwitchChat

/// TwitchUserState モデルのテストスイート
@Suite("TwitchUserState テスト")
struct TwitchUserStateTests {

    // MARK: - 正常系: USERSTATE のパース

    @Test("USERSTATE から displayName / color / badges を正しく抽出できる")
    func USERSTATEからすべてのフィールドを抽出できる() throws {
        // 前提: バッジ・色・表示名が揃った USERSTATE メッセージ
        let rawMessage = "@badge-info=subscriber/12;badges=moderator/1,subscriber/12;color=#1E90FF;display-name=テストユーザー;emote-sets=0;mod=1;subscriber=1;user-type=mod :tmi.twitch.tv USERSTATE #testchannel"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: TwitchUserState に正しく変換される
        let userState = TwitchUserState(from: ircMessage)
        #expect(userState != nil)
        #expect(userState?.displayName == "テストユーザー")
        #expect(userState?.colorHex == "#1E90FF")
        #expect(userState?.badges == [
            Badge(name: "moderator", version: "1"),
            Badge(name: "subscriber", version: "12")
        ])
    }

    @Test("display-name が空の場合は nil になる")
    func displayNameが空の場合はnilになる() throws {
        // 前提: display-name が空文字の USERSTATE
        let rawMessage = "@badges=;color=#FF0000;display-name=;emote-sets=0;mod=0;subscriber=0;user-type= :tmi.twitch.tv USERSTATE #testchannel"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: userState が存在し、displayName が nil になる
        let userState = try #require(TwitchUserState(from: ircMessage), "TwitchUserState の生成に失敗しました")
        #expect(userState.displayName == nil)
    }

    @Test("color が空の場合は nil になる")
    func colorが空の場合はnilになる() throws {
        // 前提: color が空文字の USERSTATE（色未設定ユーザー）
        let rawMessage = "@badges=;color=;display-name=山田太郎;emote-sets=0;mod=0;subscriber=0;user-type= :tmi.twitch.tv USERSTATE #testchannel"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: userState が存在し、colorHex が nil になる
        let userState = try #require(TwitchUserState(from: ircMessage), "TwitchUserState の生成に失敗しました")
        #expect(userState.colorHex == nil)
    }

    @Test("badges が空の場合は空配列になる")
    func badgesが空の場合は空配列になる() throws {
        // 前提: badges が空文字の USERSTATE（バッジなしユーザー）
        let rawMessage = "@badges=;color=#FF0000;display-name=山田太郎;emote-sets=0;mod=0;subscriber=0;user-type= :tmi.twitch.tv USERSTATE #testchannel"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: userState が存在し、badges が空配列になる
        let userState = try #require(TwitchUserState(from: ircMessage), "TwitchUserState の生成に失敗しました")
        #expect(userState.badges == [])
    }

    // MARK: - 正常系: タグなし USERSTATE

    @Test("タグが一切ない USERSTATE でも初期化できる")
    func タグなしUSERSTATEでも初期化できる() throws {
        // 前提: タグなしの USERSTATE（匿名接続の場合など）
        let rawMessage = ":tmi.twitch.tv USERSTATE #testchannel"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: nil を返さず、各フィールドがデフォルト値になる
        let userState = try #require(TwitchUserState(from: ircMessage), "TwitchUserState の生成に失敗しました")
        #expect(userState.displayName == nil)
        #expect(userState.colorHex == nil)
        #expect(userState.badges == [])
    }

    // MARK: - 異常系: USERSTATE 以外のコマンド

    @Test("PRIVMSG の IRCMessage からは nil を返す")
    func PRIVMSGからはnilを返す() throws {
        // 前提: PRIVMSG メッセージ（USERSTATE ではない）
        let rawMessage = "@color=#FF0000;display-name=山田太郎 :yamadataro!yamadataro@yamadataro.tmi.twitch.tv PRIVMSG #testchannel :こんにちは"
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: USERSTATE 以外は nil を返す
        let userState = TwitchUserState(from: ircMessage)
        #expect(userState == nil)
    }

    @Test("NOTICE の IRCMessage からは nil を返す")
    func NOTICEからはnilを返す() throws {
        // 前提: NOTICE メッセージ（USERSTATE ではない）
        let rawMessage = "@msg-id=msg_ratelimit :tmi.twitch.tv NOTICE #testchannel :You are sending messages too quickly."
        let ircMessage = try #require(IRCMessageParser.parse(rawMessage), "IRCMessage のパースに失敗しました")

        // 検証: USERSTATE 以外は nil を返す
        let userState = TwitchUserState(from: ircMessage)
        #expect(userState == nil)
    }
}
