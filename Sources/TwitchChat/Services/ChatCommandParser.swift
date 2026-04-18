// ChatCommandParser.swift
// チャット入力テキストを ChatCommand enum に変換する純粋パーサー
// 外部依存なし・副作用なし。ChatViewModel の sendMessage() から呼び出される

/// チャット入力テキストを ChatCommand に変換するパーサー
///
/// - Note: 外部依存なし・副作用なしの純粋関数として実装する
enum ChatCommandParser {

    /// 入力テキストをパースして対応する ChatCommand を返す
    ///
    /// - Parameter input: チャット入力テキスト（サニタイズ済みを想定）
    /// - Returns: パース結果の `ChatCommand`
    static func parse(_ input: String) -> ChatCommand {
        // スラッシュで始まらない場合は通常テキスト
        guard input.hasPrefix("/") else {
            return .plainText(input)
        }

        // "/" を除いた文字列からコマンド名と引数を分離する
        let withoutSlash = String(input.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let commandName = parts.isEmpty ? "" : String(parts[0]).lowercased()
        let argsString = parts.count > 1 ? String(parts[1]) : ""

        return parseUserCommands(commandName: commandName, args: argsString)
            ?? parseChatSettingsCommands(commandName: commandName, args: argsString)
            ?? parseMessageCommands(commandName: commandName, args: argsString)
            ?? .unknown(command: commandName, args: argsString)
    }

    // MARK: - カテゴリ別ルーター

    /// ユーザー対象コマンドをパースする（ban/timeout/unban/untimeout/me）
    ///
    /// - Returns: 対応するコマンド。カテゴリ外の場合は nil
    private static func parseUserCommands(commandName: String, args: String) -> ChatCommand? {
        switch commandName {
        case "me":
            return .me(message: args)
        case "ban":
            return parseBan(args: args)
        case "unban":
            return parseUsernameOnly(commandName: commandName, args: args).map { .unban(username: $0) }
        case "timeout":
            return parseTimeout(args: args)
        case "untimeout":
            return parseUsernameOnly(commandName: commandName, args: args).map { .untimeout(username: $0) }
        default:
            return nil
        }
    }

    /// チャット設定コマンドをパースする（emoteonly/slow/subscribers/followers/uniquechat 等）
    ///
    /// - Returns: 対応するコマンド。カテゴリ外の場合は nil
    private static func parseChatSettingsCommands(commandName: String, args: String) -> ChatCommand? {
        switch commandName {
        case "emoteonly":   return .emoteOnly(enabled: true)
        case "emoteonlyoff": return .emoteOnly(enabled: false)
        case "slow":        return .slow(seconds: parseOptionalInt(from: args))
        case "slowoff":     return .slowOff
        case "subscribers": return .subscribers(enabled: true)
        case "subscribersoff": return .subscribers(enabled: false)
        case "followers":   return .followers(duration: parseOptionalInt(from: args))
        case "followersoff": return .followersOff
        case "uniquechat":  return .uniqueChat(enabled: true)
        case "uniquechatoff": return .uniqueChat(enabled: false)
        default:            return nil
        }
    }

    /// メッセージ操作コマンドをパースする（clear/delete）
    ///
    /// - Returns: 対応するコマンド。カテゴリ外の場合は nil
    private static func parseMessageCommands(commandName: String, args: String) -> ChatCommand? {
        switch commandName {
        case "clear":
            return .clear
        case "delete":
            let trimmed = args.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return .unknown(command: commandName, args: args) }
            let messageId = String(trimmed.split(separator: " ")[0])
            return .delete(messageId: messageId)
        default:
            return nil
        }
    }

    // MARK: - 引数パーサー

    /// /ban コマンドの引数をパースする
    ///
    /// - Parameter args: コマンド名を除いた引数文字列（例: "あらし太郎 荒らし行為"）
    private static func parseBan(args: String) -> ChatCommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unknown(command: "ban", args: args) }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let username = String(parts[0])
        let reason = parts.count > 1 ? String(parts[1]) : nil
        return .ban(username: username, reason: reason)
    }

    /// /timeout コマンドの引数をパースする
    ///
    /// - Parameter args: コマンド名を除いた引数文字列（例: "ユーザー 600 スパム"）
    private static func parseTimeout(args: String) -> ChatCommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unknown(command: "timeout", args: args) }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return .unknown(command: "timeout", args: args) }
        let username = String(parts[0])
        guard let duration = Int(parts[1]) else { return .unknown(command: "timeout", args: args) }
        let reason = parts.count > 2 ? String(parts[2]) : nil
        return .timeout(username: username, duration: duration, reason: reason)
    }

    /// ユーザー名のみを受け取るコマンドをパースする（unban/untimeout 用）
    ///
    /// - Returns: ユーザー名文字列。引数が空または空白のみの場合は nil
    private static func parseUsernameOnly(commandName: String, args: String) -> String? {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// 先頭の数値引数をパースする（slow/followers 用）
    ///
    /// - Parameter args: 引数文字列（空文字列または数値を含む）
    /// - Returns: 数値。空文字または非数値の場合は nil
    private static func parseOptionalInt(from args: String) -> Int? {
        guard !args.isEmpty else { return nil }
        return args.split(separator: " ").first.flatMap { Int($0) }
    }
}
