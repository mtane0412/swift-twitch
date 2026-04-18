// SlashCommandDefinition.swift
// スラッシュコマンドの静的定義モデル
// 補完候補として表示するコマンド名・説明文・使用例を保持する

import Foundation

/// スラッシュコマンドの補完候補定義
///
/// 入力欄で `/` を入力した際に表示される補完候補の表示情報を保持する。
/// コマンドのパース・実行ロジックは別途 `ChatCommandParser`（issue25 で実装予定）が担当し、
/// `name` フィールドで紐づける。
///
/// - Note: `allCommands` は静的リストとして定義する。
struct SlashCommandDefinition: Identifiable {

    /// コマンド名（先頭スラッシュなし。例: "ban", "timeout"）
    let name: String

    /// コマンドの説明文（日本語）
    let description: String

    /// 使用例（例: "/ban <ユーザー名> [理由]"）。省略可能なコマンドは nil
    let usage: String?

    /// Identifiable 準拠。name をそのまま ID とする
    var id: String { name }

    // MARK: - 全コマンド定義

    /// 利用可能なすべてのスラッシュコマンドの静的リスト
    static let allCommands: [SlashCommandDefinition] = [
        SlashCommandDefinition(
            name: "me",
            description: "アクション形式でメッセージを送信する",
            usage: "/me <メッセージ>"
        ),
        SlashCommandDefinition(
            name: "ban",
            description: "ユーザーをBANする",
            usage: "/ban <ユーザー名> [理由]"
        ),
        SlashCommandDefinition(
            name: "unban",
            description: "ユーザーのBANを解除する",
            usage: "/unban <ユーザー名>"
        ),
        SlashCommandDefinition(
            name: "timeout",
            description: "ユーザーを一時的にBANする",
            usage: "/timeout <ユーザー名> <秒数> [理由]"
        ),
        SlashCommandDefinition(
            name: "untimeout",
            description: "ユーザーのタイムアウトを解除する",
            usage: "/untimeout <ユーザー名>"
        ),
        SlashCommandDefinition(
            name: "slow",
            description: "スローモードを有効にする",
            usage: "/slow [秒数]"
        ),
        SlashCommandDefinition(
            name: "slowoff",
            description: "スローモードを無効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "followers",
            description: "フォロワー限定モードを有効にする",
            usage: "/followers [日数]"
        ),
        SlashCommandDefinition(
            name: "followersoff",
            description: "フォロワー限定モードを無効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "subscribers",
            description: "サブスクライバー限定モードを有効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "subscribersoff",
            description: "サブスクライバー限定モードを無効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "emoteonly",
            description: "エモート限定モードを有効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "emoteonlyoff",
            description: "エモート限定モードを無効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "clear",
            description: "チャットを全消去する",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "uniquechat",
            description: "ユニークチャットモードを有効にする（重複メッセージを禁止）",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "uniquechatoff",
            description: "ユニークチャットモードを無効にする",
            usage: nil
        ),
        SlashCommandDefinition(
            name: "delete",
            description: "特定のメッセージを削除する",
            usage: "/delete <メッセージID>"
        )
    ]
}
