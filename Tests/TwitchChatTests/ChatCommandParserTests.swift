// ChatCommandParserTests.swift
// ChatCommandParser の単体テスト
// チャット入力テキストを解析して ChatInputResult を返す振る舞いを検証する

import Testing
@testable import TwitchChat

@Suite("ChatCommandParser")
struct ChatCommandParserTests {

    // MARK: - 通常メッセージ

    @Test("スラッシュなしのテキストは .message として解析される")
    func normalMessageReturnsMessage() throws {
        // 通常のチャットメッセージはコマンドとして解釈されない
        let result = try ChatCommandParser.parse("こんにちは！")
        #expect(result == .message("こんにちは！"))
    }

    @Test("英数字のみのテキストは .message として解析される")
    func alphanumericTextReturnsMessage() throws {
        let result = try ChatCommandParser.parse("hello world")
        #expect(result == .message("hello world"))
    }

    @Test("空文字列は .message として解析される（空チェックは呼び出し元の責務）")
    func emptyStringReturnsMessage() throws {
        // 空文字列はコマンドとして解釈されない（呼び出し元の ChatViewModel が空チェックする）
        let result = try ChatCommandParser.parse("")
        #expect(result == .message(""))
    }

    @Test("空白のみの入力は .message として解析される（空チェックは呼び出し元の責務）")
    func whitespaceTextReturnsMessage() throws {
        let result = try ChatCommandParser.parse("  ")
        #expect(result == .message("  "))
    }

    @Test("スラッシュのみの入力は .message として解析される")
    func singleSlashReturnsMessage() throws {
        // コマンド名がない "/" は通常メッセージとして扱う
        let result = try ChatCommandParser.parse("/")
        #expect(result == .message("/"))
    }

    // MARK: - /me コマンド

    @Test("/me コマンドは .me として解析される")
    func meCommandReturnsMeResult() throws {
        let result = try ChatCommandParser.parse("/me 踊る")
        #expect(result == .me(body: "踊る"))
    }

    @Test("/me コマンドは大文字小文字を区別しない")
    func meCommandCaseInsensitive() throws {
        let lower = try ChatCommandParser.parse("/me テスト")
        let upper = try ChatCommandParser.parse("/ME テスト")
        let mixed = try ChatCommandParser.parse("/Me テスト")
        #expect(lower == .me(body: "テスト"))
        #expect(upper == .me(body: "テスト"))
        #expect(mixed == .me(body: "テスト"))
    }

    @Test("/me の本文が空の場合は ChatSendError.empty を throw する")
    func meCommandWithoutBodyThrowsEmpty() {
        // "/me" のみで本文なしは空メッセージと同等
        #expect(throws: ChatSendError.empty) {
            try ChatCommandParser.parse("/me")
        }
    }

    @Test("/me の本文がスペースのみの場合は ChatSendError.empty を throw する")
    func meCommandWithOnlySpacesThrowsEmpty() {
        #expect(throws: ChatSendError.empty) {
            try ChatCommandParser.parse("/me   ")
        }
    }

    // MARK: - モデレーションコマンド（引数あり）

    @Test("/ban ユーザー名 は .moderationCommand として解析される")
    func banCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/ban スパムユーザー")
        #expect(result == .moderationCommand(name: "ban", ircText: "/ban スパムユーザー"))
    }

    @Test("/ban はオプションの理由付きでも解析される")
    func banCommandWithReasonReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/ban スパムユーザー スパム行為のため")
        #expect(result == .moderationCommand(name: "ban", ircText: "/ban スパムユーザー スパム行為のため"))
    }

    @Test("/ban 引数なしは ChatSendError.missingArguments を throw する")
    func banCommandWithoutArgumentsThrowsMissingArguments() {
        #expect(throws: ChatSendError.missingArguments(command: "ban", expected: "/ban <ユーザー名>")) {
            try ChatCommandParser.parse("/ban")
        }
    }

    @Test("/unban ユーザー名 は .moderationCommand として解析される")
    func unbanCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/unban 解除ユーザー")
        #expect(result == .moderationCommand(name: "unban", ircText: "/unban 解除ユーザー"))
    }

    @Test("/unban 引数なしは ChatSendError.missingArguments を throw する")
    func unbanCommandWithoutArgumentsThrows() {
        #expect(throws: ChatSendError.missingArguments(command: "unban", expected: "/unban <ユーザー名>")) {
            try ChatCommandParser.parse("/unban")
        }
    }

    @Test("/timeout ユーザー名 秒数 は .moderationCommand として解析される")
    func timeoutCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/timeout 荒らしユーザー 600")
        #expect(result == .moderationCommand(name: "timeout", ircText: "/timeout 荒らしユーザー 600"))
    }

    @Test("/timeout ユーザー名のみ（秒数なし）は ChatSendError.missingArguments を throw する")
    func timeoutCommandWithoutSecondsThrows() {
        #expect(throws: ChatSendError.missingArguments(command: "timeout", expected: "/timeout <ユーザー名> <秒数>")) {
            try ChatCommandParser.parse("/timeout 荒らしユーザー")
        }
    }

    @Test("/timeout 引数なしは ChatSendError.missingArguments を throw する")
    func timeoutCommandWithoutArgumentsThrows() {
        #expect(throws: ChatSendError.missingArguments(command: "timeout", expected: "/timeout <ユーザー名> <秒数>")) {
            try ChatCommandParser.parse("/timeout")
        }
    }

    @Test("/untimeout ユーザー名 は .moderationCommand として解析される")
    func untimeoutCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/untimeout 解除ユーザー")
        #expect(result == .moderationCommand(name: "untimeout", ircText: "/untimeout 解除ユーザー"))
    }

    @Test("/untimeout 引数なしは ChatSendError.missingArguments を throw する")
    func untimeoutCommandWithoutArgumentsThrows() {
        #expect(throws: ChatSendError.missingArguments(command: "untimeout", expected: "/untimeout <ユーザー名>")) {
            try ChatCommandParser.parse("/untimeout")
        }
    }

    @Test("/delete メッセージID は .moderationCommand として解析される")
    func deleteCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/delete abc-123-def")
        #expect(result == .moderationCommand(name: "delete", ircText: "/delete abc-123-def"))
    }

    @Test("/delete 引数なしは ChatSendError.missingArguments を throw する")
    func deleteCommandWithoutArgumentsThrows() {
        #expect(throws: ChatSendError.missingArguments(command: "delete", expected: "/delete <メッセージID>")) {
            try ChatCommandParser.parse("/delete")
        }
    }

    // MARK: - モデレーションコマンド（引数不要）

    @Test("/slow は引数なしで .moderationCommand として解析される")
    func slowCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/slow")
        #expect(result == .moderationCommand(name: "slow", ircText: "/slow"))
    }

    @Test("/slow は秒数付きでも .moderationCommand として解析される")
    func slowCommandWithSecondsReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/slow 10")
        #expect(result == .moderationCommand(name: "slow", ircText: "/slow 10"))
    }

    @Test("/slowoff は .moderationCommand として解析される")
    func slowoffCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/slowoff")
        #expect(result == .moderationCommand(name: "slowoff", ircText: "/slowoff"))
    }

    @Test("/subscribers は .moderationCommand として解析される")
    func subscribersCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/subscribers")
        #expect(result == .moderationCommand(name: "subscribers", ircText: "/subscribers"))
    }

    @Test("/subscribersoff は .moderationCommand として解析される")
    func subscribersoffCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/subscribersoff")
        #expect(result == .moderationCommand(name: "subscribersoff", ircText: "/subscribersoff"))
    }

    @Test("/emoteonly は .moderationCommand として解析される")
    func emoteonlyCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/emoteonly")
        #expect(result == .moderationCommand(name: "emoteonly", ircText: "/emoteonly"))
    }

    @Test("/emoteonlyoff は .moderationCommand として解析される")
    func emoteonlyoffCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/emoteonlyoff")
        #expect(result == .moderationCommand(name: "emoteonlyoff", ircText: "/emoteonlyoff"))
    }

    @Test("/followers は .moderationCommand として解析される")
    func followersCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/followers")
        #expect(result == .moderationCommand(name: "followers", ircText: "/followers"))
    }

    @Test("/followersoff は .moderationCommand として解析される")
    func followersoffCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/followersoff")
        #expect(result == .moderationCommand(name: "followersoff", ircText: "/followersoff"))
    }

    @Test("/clear は .moderationCommand として解析される")
    func clearCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/clear")
        #expect(result == .moderationCommand(name: "clear", ircText: "/clear"))
    }

    @Test("/uniquechat は .moderationCommand として解析される")
    func uniquechatCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/uniquechat")
        #expect(result == .moderationCommand(name: "uniquechat", ircText: "/uniquechat"))
    }

    @Test("/uniquechatoff は .moderationCommand として解析される")
    func uniquechatoffCommandReturnsModerationCommand() throws {
        let result = try ChatCommandParser.parse("/uniquechatoff")
        #expect(result == .moderationCommand(name: "uniquechatoff", ircText: "/uniquechatoff"))
    }

    // MARK: - 大文字小文字の正規化

    @Test("モデレーションコマンドは大文字小文字を区別しない")
    func moderationCommandCaseInsensitive() throws {
        let upper = try ChatCommandParser.parse("/BAN スパムユーザー")
        let mixed = try ChatCommandParser.parse("/Ban スパムユーザー")
        #expect(upper == .moderationCommand(name: "ban", ircText: "/BAN スパムユーザー"))
        #expect(mixed == .moderationCommand(name: "ban", ircText: "/Ban スパムユーザー"))
    }

    // MARK: - 未知のコマンド

    @Test("未知のコマンドは .unknownCommand として解析される")
    func unknownCommandReturnsUnknownCommand() throws {
        let result = try ChatCommandParser.parse("/hoge")
        #expect(result == .unknownCommand(name: "hoge"))
    }

    @Test("未知のコマンドは引数つきでも .unknownCommand として解析される")
    func unknownCommandWithArgsReturnsUnknownCommand() throws {
        let result = try ChatCommandParser.parse("/dance ユーザー名")
        #expect(result == .unknownCommand(name: "dance"))
    }

    @Test("未知のコマンドは大文字小文字を保持しない（名前を小文字で返す）")
    func unknownCommandNameIsLowercased() throws {
        let result = try ChatCommandParser.parse("/UNKNOWN")
        #expect(result == .unknownCommand(name: "unknown"))
    }
}
