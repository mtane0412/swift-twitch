// ChatCommandParserTests.swift
// ChatCommandParser のパーステスト
// コマンド文字列を ChatCommand enum に正しく変換することを検証する

import Testing
@testable import TwitchChat

@Suite("ChatCommandParserTests")
struct ChatCommandParserTests {

    // MARK: - 通常テキスト

    @Test("スラッシュなしの文字列は plainText になること")
    func testPlainText() {
        #expect(ChatCommandParser.parse("こんにちは") == .plainText("こんにちは"))
    }

    @Test("空文字は plainText になること")
    func testEmptyStringIsPlainText() {
        #expect(ChatCommandParser.parse("") == .plainText(""))
    }

    // MARK: - /me コマンド

    @Test("/me コマンドが正しくパースされること")
    func testMeCommand() {
        #expect(ChatCommandParser.parse("/me 踊る") == .me(message: "踊る"))
    }

    @Test("/me（本文なし）が unknown になること")
    func testMeCommandWithoutBody() {
        #expect(ChatCommandParser.parse("/me") == .me(message: ""))
    }

    @Test("/me は大文字小文字を区別しないこと")
    func testMeCommandCaseInsensitive() {
        #expect(ChatCommandParser.parse("/ME テスト") == .me(message: "テスト"))
        #expect(ChatCommandParser.parse("/Me テスト") == .me(message: "テスト"))
    }

    // MARK: - /ban コマンド

    @Test("/ban コマンドがユーザー名のみでパースされること")
    func testBanCommandWithUsernameOnly() {
        #expect(ChatCommandParser.parse("/ban あらし太郎") == .ban(username: "あらし太郎", reason: nil))
    }

    @Test("/ban コマンドがユーザー名と理由でパースされること")
    func testBanCommandWithReason() {
        #expect(ChatCommandParser.parse("/ban あらし太郎 荒らし行為") == .ban(username: "あらし太郎", reason: "荒らし行為"))
    }

    @Test("/ban は大文字小文字を区別しないこと")
    func testBanCommandCaseInsensitive() {
        #expect(ChatCommandParser.parse("/BAN ユーザー") == .ban(username: "ユーザー", reason: nil))
    }

    // MARK: - /unban コマンド

    @Test("/unban コマンドが正しくパースされること")
    func testUnbanCommand() {
        #expect(ChatCommandParser.parse("/unban あらし太郎") == .unban(username: "あらし太郎"))
    }

    // MARK: - /timeout コマンド

    @Test("/timeout コマンドがユーザー名と秒数でパースされること")
    func testTimeoutCommand() {
        #expect(ChatCommandParser.parse("/timeout ユーザー 600") == .timeout(username: "ユーザー", duration: 600, reason: nil))
    }

    @Test("/timeout コマンドがユーザー名・秒数・理由でパースされること")
    func testTimeoutCommandWithReason() {
        #expect(ChatCommandParser.parse("/timeout ユーザー 300 スパム") == .timeout(username: "ユーザー", duration: 300, reason: "スパム"))
    }

    @Test("/timeout で秒数が数値でない場合は unknown になること")
    func testTimeoutCommandWithInvalidDuration() {
        #expect(ChatCommandParser.parse("/timeout ユーザー abc") == .unknown(command: "timeout", args: "ユーザー abc"))
    }

    @Test("/timeout でユーザー名のみの場合は unknown になること")
    func testTimeoutCommandWithoutDuration() {
        #expect(ChatCommandParser.parse("/timeout ユーザー") == .unknown(command: "timeout", args: "ユーザー"))
    }

    // MARK: - /untimeout コマンド

    @Test("/untimeout コマンドが正しくパースされること")
    func testUntimeoutCommand() {
        #expect(ChatCommandParser.parse("/untimeout ユーザー") == .untimeout(username: "ユーザー"))
    }

    // MARK: - /emoteonly / /emoteonlyoff コマンド

    @Test("/emoteonly コマンドが enabled:true になること")
    func testEmoteOnlyCommand() {
        #expect(ChatCommandParser.parse("/emoteonly") == .emoteOnly(enabled: true))
    }

    @Test("/emoteonlyoff コマンドが enabled:false になること")
    func testEmoteOnlyOffCommand() {
        #expect(ChatCommandParser.parse("/emoteonlyoff") == .emoteOnly(enabled: false))
    }

    // MARK: - /slow / /slowoff コマンド

    @Test("/slow コマンドが秒数なしでパースされること")
    func testSlowCommandWithoutSeconds() {
        #expect(ChatCommandParser.parse("/slow") == .slow(seconds: nil))
    }

    @Test("/slow コマンドが秒数ありでパースされること")
    func testSlowCommandWithSeconds() {
        #expect(ChatCommandParser.parse("/slow 30") == .slow(seconds: 30))
    }

    @Test("/slowoff コマンドが正しくパースされること")
    func testSlowOffCommand() {
        #expect(ChatCommandParser.parse("/slowoff") == .slowOff)
    }

    // MARK: - /subscribers / /subscribersoff コマンド

    @Test("/subscribers コマンドが enabled:true になること")
    func testSubscribersCommand() {
        #expect(ChatCommandParser.parse("/subscribers") == .subscribers(enabled: true))
    }

    @Test("/subscribersoff コマンドが enabled:false になること")
    func testSubscribersOffCommand() {
        #expect(ChatCommandParser.parse("/subscribersoff") == .subscribers(enabled: false))
    }

    // MARK: - /followers / /followersoff コマンド

    @Test("/followers コマンドが日数なしでパースされること")
    func testFollowersCommandWithoutDuration() {
        #expect(ChatCommandParser.parse("/followers") == .followers(duration: nil))
    }

    @Test("/followers コマンドが日数ありでパースされること")
    func testFollowersCommandWithDuration() {
        #expect(ChatCommandParser.parse("/followers 7") == .followers(duration: 7))
    }

    @Test("/followersoff コマンドが正しくパースされること")
    func testFollowersOffCommand() {
        #expect(ChatCommandParser.parse("/followersoff") == .followersOff)
    }

    // MARK: - /uniquechat / /uniquechatoff コマンド

    @Test("/uniquechat コマンドが enabled:true になること")
    func testUniqueChatCommand() {
        #expect(ChatCommandParser.parse("/uniquechat") == .uniqueChat(enabled: true))
    }

    @Test("/uniquechatoff コマンドが enabled:false になること")
    func testUniqueChatOffCommand() {
        #expect(ChatCommandParser.parse("/uniquechatoff") == .uniqueChat(enabled: false))
    }

    // MARK: - /clear コマンド

    @Test("/clear コマンドが正しくパースされること")
    func testClearCommand() {
        #expect(ChatCommandParser.parse("/clear") == .clear)
    }

    // MARK: - /delete コマンド

    @Test("/delete コマンドがメッセージIDでパースされること")
    func testDeleteCommand() {
        #expect(ChatCommandParser.parse("/delete abc-123-def") == .delete(messageId: "abc-123-def"))
    }

    // MARK: - 未知のコマンド

    @Test("未知のスラッシュコマンドは unknown になること")
    func testUnknownCommand() {
        #expect(ChatCommandParser.parse("/unknowncmd foo") == .unknown(command: "unknowncmd", args: "foo"))
    }

    @Test("引数なしの未知のスラッシュコマンドは unknown になること")
    func testUnknownCommandWithoutArgs() {
        #expect(ChatCommandParser.parse("/unknowncmd") == .unknown(command: "unknowncmd", args: ""))
    }

    // MARK: - エッジケース

    @Test("/ban でユーザー名なしは unknown になること")
    func testBanCommandWithoutUsername() {
        #expect(ChatCommandParser.parse("/ban") == .unknown(command: "ban", args: ""))
    }

    @Test("/unban でユーザー名なしは unknown になること")
    func testUnbanCommandWithoutUsername() {
        #expect(ChatCommandParser.parse("/unban") == .unknown(command: "unban", args: ""))
    }

    @Test("/delete でIDなしは unknown になること")
    func testDeleteCommandWithoutId() {
        #expect(ChatCommandParser.parse("/delete") == .unknown(command: "delete", args: ""))
    }
}
