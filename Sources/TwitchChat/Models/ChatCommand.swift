// ChatCommand.swift
// チャット入力テキストの解析結果を表す型と、解析ロジックを提供するモジュール
// ChatViewModel からコマンド解析の責務を分離し、単体テストを容易にする

import Foundation

/// チャット入力テキストの解析結果
///
/// `ChatCommandParser.parse(_:)` が返す値。
/// 呼び出し元はこの型で switch して送信方法と UI 挙動を分岐させる。
enum ChatInputResult: Equatable {
    /// 通常のチャットメッセージ（スラッシュコマンドではない）
    case message(String)
    /// `/me` コマンド。本文のみを保持する（ACTION ラッパーは呼び出し元で付与する）
    case me(body: String)
    /// モデレーションコマンド（`/ban`, `/timeout` 等）
    ///
    /// - Parameters:
    ///   - name: コマンド名（小文字、スラッシュなし。例: "ban"）
    ///   - ircText: IRC 送信用テキスト（入力テキストをそのまま使用。例: "/ban ユーザー名"）
    case moderationCommand(name: String, ircText: String)
    /// 未知のスラッシュコマンド
    ///
    /// - Parameter name: コマンド名（小文字）
    case unknownCommand(name: String)
}

/// チャット入力テキストのパーサー
///
/// サニタイズ済みテキストを受け取り、`ChatInputResult` を返す純粋な静的関数群を提供する。
/// 外部依存なし・状態なしのため単体テストが容易。
enum ChatCommandParser {

    // MARK: - モデレーションコマンド定義

    /// 対応するモデレーションコマンドと、その必須引数の最小個数
    ///
    /// - key: コマンド名（小文字、スラッシュなし）
    /// - value: 必須引数の最小個数（0 = 引数不要）
    ///
    /// 引数の値バリデーション（秒数が数値かどうか等）はサーバー側に委ねる。
    /// クライアント側では個数のみをチェックする。
    private static let moderationCommands: [String: Int] = {
        let entries: [(String, Int)] = [
            ("ban",             1),  // /ban <ユーザー名> [理由]
            ("unban",           1),  // /unban <ユーザー名>
            ("timeout",         2),  // /timeout <ユーザー名> <秒数> [理由]
            ("untimeout",       1),  // /untimeout <ユーザー名>
            ("slow",            0),  // /slow [秒数]
            ("slowoff",         0),  // /slowoff
            ("followers",       0),  // /followers [期間]
            ("followersoff",    0),  // /followersoff
            ("subscribers",     0),  // /subscribers
            ("subscribersoff",  0),  // /subscribersoff
            ("emoteonly",       0),  // /emoteonly
            ("emoteonlyoff",    0),  // /emoteonlyoff
            ("clear",           0),  // /clear
            ("uniquechat",      0),  // /uniquechat
            ("uniquechatoff",   0),  // /uniquechatoff
            ("delete",          1)   // /delete <メッセージID>
        ]
        return Dictionary(uniqueKeysWithValues: entries)
    }()

    /// 各コマンドの使い方を示す文字列（エラーメッセージ用）
    private static let commandUsage: [String: String] = [
        "ban": "/ban <ユーザー名>",
        "unban": "/unban <ユーザー名>",
        "timeout": "/timeout <ユーザー名> <秒数>",
        "untimeout": "/untimeout <ユーザー名>",
        "delete": "/delete <メッセージID>"
    ]

    // MARK: - パース

    /// サニタイズ済みのチャット入力テキストを解析する
    ///
    /// - Parameter sanitized: サニタイズ済みの入力テキスト（`ChatViewModel.sanitize` 適用後）
    /// - Returns: 解析結果（`ChatInputResult`）
    /// - Throws:
    ///   - `ChatSendError.empty` — `/me` の本文が空
    ///   - `ChatSendError.missingArguments` — 必須引数が不足しているモデレーションコマンド
    static func parse(_ sanitized: String) throws -> ChatInputResult {
        // スラッシュで始まらない場合は通常メッセージ
        guard sanitized.hasPrefix("/") else {
            return .message(sanitized)
        }

        // コマンド名と引数を分割する
        // 入力例: "/ban ユーザー名 理由" → components = ["", "ban", "ユーザー名", "理由"]
        // 先頭のスラッシュを除いた文字列でスペース分割する
        let withoutSlash = String(sanitized.dropFirst())
        let parts = withoutSlash.split(separator: " ", omittingEmptySubsequences: true)
        let commandName = parts.first.map { String($0).lowercased() } ?? ""
        let args = parts.dropFirst()

        // /me コマンド
        if commandName == "me" {
            let body = args.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { throw ChatSendError.empty }
            return .me(body: body)
        }

        // モデレーションコマンド
        if let minArgs = moderationCommands[commandName] {
            guard args.count >= minArgs else {
                let usage = commandUsage[commandName] ?? "/\(commandName)"
                throw ChatSendError.missingArguments(command: commandName, expected: usage)
            }
            // ircText には入力テキストをそのまま渡す（Twitch サーバーがコマンドとして解釈する）
            return .moderationCommand(name: commandName, ircText: sanitized)
        }

        // 未知のコマンド
        return .unknownCommand(name: commandName)
    }
}
