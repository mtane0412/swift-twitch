// ChatCommand.swift
// チャット入力コマンドを表す型
// スラッシュコマンド文字列をパースした結果を表現し、IRC送信とHelix API呼び出しの分岐に使用する

/// チャット入力から解析したコマンドを表す enum
///
/// - Note: `ChatCommandParser.parse(_:)` によって生成される
enum ChatCommand: Equatable {

    // MARK: - IRC 経由コマンド

    /// `/me <メッセージ>` — アクション形式でメッセージを送信する
    case me(message: String)

    // MARK: - Helix API: POST /moderation/bans

    /// `/ban <username> [reason]` — ユーザーを永久BANする
    case ban(username: String, reason: String?)

    /// `/timeout <username> <seconds> [reason]` — ユーザーを一時的にBANする
    case timeout(username: String, duration: Int, reason: String?)

    // MARK: - Helix API: DELETE /moderation/bans

    /// `/unban <username>` — ユーザーの永久BANを解除する
    case unban(username: String)

    /// `/untimeout <username>` — ユーザーのタイムアウトを解除する
    case untimeout(username: String)

    // MARK: - Helix API: PATCH /chat/settings

    /// `/emoteonly` / `/emoteonlyoff` — エモート限定モードを切り替える
    case emoteOnly(enabled: Bool)

    /// `/slow [seconds]` — スローモードを有効にする（seconds: nil の場合はデフォルト30秒）
    case slow(seconds: Int?)

    /// `/slowoff` — スローモードを無効にする
    case slowOff

    /// `/subscribers` / `/subscribersoff` — サブスクライバー限定モードを切り替える
    case subscribers(enabled: Bool)

    /// `/followers [duration]` — フォロワー限定モードを有効にする（duration: nil の場合はデフォルト）
    case followers(duration: Int?)

    /// `/followersoff` — フォロワー限定モードを無効にする
    case followersOff

    /// `/uniquechat` / `/uniquechatoff` — ユニークチャットモードを切り替える
    case uniqueChat(enabled: Bool)

    // MARK: - Helix API: DELETE /chat/messages

    /// `/clear` — チャットを全消去する
    case clear

    /// `/delete <messageId>` — 特定のメッセージを削除する
    case delete(messageId: String)

    // MARK: - 通常メッセージ・未知コマンド

    /// スラッシュコマンドではない通常のテキスト
    case plainText(String)

    /// 認識できないスラッシュコマンド
    case unknown(command: String, args: String)
}
