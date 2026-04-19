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
        case "slow":        return parseOptionalIntCommand(args: args, commandName: commandName, validRange: 3...120) { .slow(seconds: $0) }
        case "slowoff":     return .slowOff
        case "subscribers": return .subscribers(enabled: true)
        case "subscribersoff": return .subscribers(enabled: false)
        case "followers":   return parseOptionalIntCommand(args: args, commandName: commandName, validRange: 0...129_600) { .followers(duration: $0) }
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
        // 空要素を除外して分割し、連続する空白でも正しくパースする
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        let username = String(parts[0])
        let reason = parts.count > 1 ? parts[1...].joined(separator: " ") : nil
        return .ban(username: username, reason: reason)
    }

    /// /timeout コマンドの引数をパースする
    ///
    /// - Parameter args: コマンド名を除いた引数文字列（例: "ユーザー 600 スパム"）
    private static func parseTimeout(args: String) -> ChatCommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .unknown(command: "timeout", args: args) }
        // 空要素を除外して分割し、連続する空白でも正しくパースする
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return .unknown(command: "timeout", args: args) }
        let username = String(parts[0])
        // Helix API の上限は 1,209,600 秒（2週間）
        guard let duration = Int(parts[1]), (1...1_209_600).contains(duration) else {
            return .unknown(command: "timeout", args: args)
        }
        let reason = parts.count > 2 ? parts[2...].joined(separator: " ") : nil
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

    /// 省略可能な整数引数を受け付けるコマンドをパースする（slow/followers 用）
    ///
    /// - 引数なし → `makeCommand(nil)` を返す（デフォルト値で有効化）
    /// - 有効な整数 → `makeCommand(value)` を返す
    /// - 無効な文字列 → `.unknown` を返す（ユーザー入力ミスを早期にフィードバックする）
    ///
    /// - Parameters:
    ///   - args: コマンド名を除いた引数文字列
    ///   - commandName: エラー表示に使用するコマンド名
    ///   - makeCommand: 整数値（または nil）を受け取って ChatCommand を生成するクロージャ
    private static func parseOptionalIntCommand(
        args: String,
        commandName: String,
        validRange: ClosedRange<Int>? = nil,
        makeCommand: (Int?) -> ChatCommand
    ) -> ChatCommand {
        let trimmedArgs = args.trimmingCharacters(in: .whitespaces)
        // 引数なしの場合はデフォルト値で有効化（範囲チェック不要）
        if trimmedArgs.isEmpty { return makeCommand(nil) }
        // 先頭トークンを整数としてパース。非数値の場合は .unknown を返す
        guard let value = trimmedArgs.split(separator: " ").first.flatMap({ Int($0) }) else {
            return .unknown(command: commandName, args: args)
        }
        // 範囲が指定されている場合、範囲外の値は .unknown を返す
        if let validRange, !validRange.contains(value) {
            return .unknown(command: commandName, args: args)
        }
        return makeCommand(value)
    }
}
