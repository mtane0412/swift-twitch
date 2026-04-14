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
        let chatMessage = ChatMessage(from: ircMessage)
        #expect(chatMessage?.emotes.count == 1)
        #expect(chatMessage?.emotes.first?.emoteId == "25")
        #expect(chatMessage?.segments.count == 2)
        #expect(chatMessage?.segments[0] == .emote(id: "25", name: "Kappa"))
        #expect(chatMessage?.segments[1] == .text(" 配信中"))
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
}
