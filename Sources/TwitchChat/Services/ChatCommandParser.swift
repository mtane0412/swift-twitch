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

        switch commandName {
        case "me":
            return .me(message: argsString)

        case "ban":
            return parseBan(args: argsString)

        case "unban":
            guard !argsString.isEmpty else { return .unknown(command: commandName, args: argsString) }
            let username = argsString.split(separator: " ").first.map(String.init) ?? argsString
            return .unban(username: username)

        case "timeout":
            return parseTimeout(args: argsString)

        case "untimeout":
            guard !argsString.isEmpty else { return .unknown(command: commandName, args: argsString) }
            let username = argsString.split(separator: " ").first.map(String.init) ?? argsString
            return .untimeout(username: username)

        case "emoteonly":
            return .emoteOnly(enabled: true)

        case "emoteonlyoff":
            return .emoteOnly(enabled: false)

        case "slow":
            if argsString.isEmpty {
                return .slow(seconds: nil)
            }
            if let seconds = Int(argsString.split(separator: " ")[0]) {
                return .slow(seconds: seconds)
            }
            return .slow(seconds: nil)

        case "slowoff":
            return .slowOff

        case "subscribers":
            return .subscribers(enabled: true)

        case "subscribersoff":
            return .subscribers(enabled: false)

        case "followers":
            if argsString.isEmpty {
                return .followers(duration: nil)
            }
            if let duration = Int(argsString.split(separator: " ")[0]) {
                return .followers(duration: duration)
            }
            return .followers(duration: nil)

        case "followersoff":
            return .followersOff

        case "uniquechat":
            return .uniqueChat(enabled: true)

        case "uniquechatoff":
            return .uniqueChat(enabled: false)

        case "clear":
            return .clear

        case "delete":
            guard !argsString.isEmpty else { return .unknown(command: commandName, args: argsString) }
            let messageId = String(argsString.split(separator: " ")[0])
            return .delete(messageId: messageId)

        default:
            return .unknown(command: commandName, args: argsString)
        }
    }

    // MARK: - プライベートヘルパー

    /// /ban コマンドの引数をパースする
    ///
    /// - Parameter args: コマンド名を除いた引数文字列（例: "あらし太郎 荒らし行為"）
    private static func parseBan(args: String) -> ChatCommand {
        guard !args.isEmpty else { return .unknown(command: "ban", args: args) }
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let username = String(parts[0])
        let reason = parts.count > 1 ? String(parts[1]) : nil
        return .ban(username: username, reason: reason)
    }

    /// /timeout コマンドの引数をパースする
    ///
    /// - Parameter args: コマンド名を除いた引数文字列（例: "ユーザー 600 スパム"）
    private static func parseTimeout(args: String) -> ChatCommand {
        let parts = args.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return .unknown(command: "timeout", args: args) }
        let username = String(parts[0])
        guard let duration = Int(parts[1]) else { return .unknown(command: "timeout", args: args) }
        let reason = parts.count > 2 ? String(parts[2]) : nil
        return .timeout(username: username, duration: duration, reason: reason)
    }
}
