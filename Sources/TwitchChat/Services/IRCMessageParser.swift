// IRCMessageParser.swift
// IRC メッセージのパーサー
// RFC 1459 形式 + IRCv3 タグ拡張（Twitch IRC）に対応した純粋関数パーサー

import Foundation

/// IRC メッセージのパーサー
///
/// Twitch IRC メッセージ形式:
/// `[@tags] [:prefix] <command> [params] [:trailing]`
///
/// - Note: 副作用なしの純粋関数で実装し、テスト容易性を確保する
enum IRCMessageParser {

    /// 生の IRC メッセージ文字列をパースして IRCMessage を返す
    ///
    /// - Parameter rawMessage: 生の IRC メッセージ文字列
    /// - Returns: パース成功時は IRCMessage、失敗時は nil
    static func parse(_ rawMessage: String) -> IRCMessage? {
        let trimmed = rawMessage.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var remainder = trimmed

        // タグの抽出（@key=value;key2=value2 形式）
        var tags: [String: String] = [:]
        if remainder.hasPrefix("@") {
            remainder.removeFirst() // @ を除去
            let parts = remainder.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            tags = parseTags(String(parts[0]))
            remainder = String(parts[1])
        }

        // プレフィックスの抽出（:nick!user@host 形式）
        var messagePrefix: String?
        if remainder.hasPrefix(":") {
            remainder.removeFirst() // : を除去
            let parts = remainder.split(separator: " ", maxSplits: 1)
            guard !parts.isEmpty else { return nil }
            messagePrefix = String(parts[0])
            remainder = parts.count > 1 ? String(parts[1]) : ""
        }

        // コマンドとパラメータの抽出
        let (command, params, trailing) = parseCommandAndParams(remainder)
        guard !command.isEmpty else { return nil }

        return IRCMessage(
            tags: tags,
            prefix: messagePrefix,
            command: command,
            params: params,
            trailing: trailing
        )
    }

    // MARK: - プライベートメソッド

    /// タグ文字列をディクショナリに変換する
    ///
    /// - Parameter tagsString: セミコロン区切りのタグ文字列（例: `key=value;key2=value2`）
    /// - Returns: キーと値のディクショナリ
    private static func parseTags(_ tagsString: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = tagsString.split(separator: ";", omittingEmptySubsequences: true)
        for pair in pairs {
            guard !pair.isEmpty else { continue }
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            let key = String(keyValue[0])
            let value = keyValue.count > 1 ? unescapeTagValue(String(keyValue[1])) : ""
            result[key] = value
        }
        return result
    }

    /// IRCv3 タグ値のエスケープシーケンスを変換する
    ///
    /// エスケープシーケンス一覧:
    /// - `\:` → `;`
    /// - `\s` → スペース
    /// - `\\` → `\`
    /// - `\r` → CR
    /// - `\n` → LF
    ///
    /// - Parameter value: エスケープされたタグ値
    /// - Returns: アンエスケープされた文字列
    private static func unescapeTagValue(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let char = iterator.next() {
            if char == "\\" {
                switch iterator.next() {
                case ":": result.append(";")
                case "s": result.append(" ")
                case "\\": result.append("\\")
                case "r": result.append("\r")
                case "n": result.append("\n")
                case let next?: result.append(next)
                case nil: break
                }
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// コマンド・パラメータ・trailing を抽出する
    ///
    /// - Parameter remainder: プレフィックス除去後の文字列
    /// - Returns: (コマンド, パラメータ配列, trailing) のタプル
    private static func parseCommandAndParams(_ remainder: String) -> (String, [String], String?) {
        guard !remainder.isEmpty else { return ("", [], nil) }

        var parts = remainder.components(separatedBy: " ")
        guard !parts.isEmpty else { return ("", [], nil) }

        let command = parts.removeFirst()
        var params: [String] = []
        var trailing: String?

        // trailing の検出（":" で始まるパラメータ）
        var trailingStartIndex: Int?
        for (index, part) in parts.enumerated() {
            if part.hasPrefix(":") {
                trailingStartIndex = index
                break
            }
            params.append(part)
        }

        if let idx = trailingStartIndex {
            var trailingParts = Array(parts[idx...])
            // 先頭の ":" を除去
            trailingParts[0] = String(trailingParts[0].dropFirst())
            trailing = trailingParts.joined(separator: " ")
        }

        return (command, params, trailing)
    }
}
