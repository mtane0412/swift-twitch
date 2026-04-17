// TwitchUserState.swift
// Twitch IRC USERSTATE コマンドを表すモデル
// 認証接続後に届く自分のユーザー情報（表示名・チャット色・バッジ）を保持する

/// Twitch IRC の USERSTATE コマンドから抽出したユーザー状態
///
/// 認証接続後、チャンネルに JOIN した直後やメッセージ送信後に
/// サーバーから自分のユーザー情報を含む USERSTATE が届く。
/// 楽観的 UI で自分のメッセージを正確に表示するために使用する。
///
/// 実際の IRC 形式:
/// `@badges=moderator/1;color=#1E90FF;display-name=テストユーザー;emote-sets=0;mod=1 :tmi.twitch.tv USERSTATE #channel`
struct TwitchUserState: Sendable, Equatable {
    /// 表示名（日本語名や大文字入りの名前）
    ///
    /// Twitch アカウントの大文字・小文字混在の表示名。
    /// サーバーから送られた `display-name` タグが空の場合は nil。
    let displayName: String?

    /// ユーザーのチャット文字色（16進数 #RRGGBB 形式）
    ///
    /// ユーザーが色を設定していない場合は nil。
    /// クライアント側でデフォルト色を決定する。
    let colorHex: String?

    /// バッジ一覧（broadcaster / moderator / subscriber 等）
    let badges: [Badge]

    /// IRCMessage から TwitchUserState を生成する
    ///
    /// USERSTATE コマンド以外の場合は nil を返す。
    ///
    /// - Parameter ircMessage: パース済みの IRCMessage
    init?(from ircMessage: IRCMessage) {
        guard ircMessage.command == "USERSTATE" else { return nil }
        // 空文字は未設定として nil に変換する
        self.displayName = ircMessage.tags["display-name"].flatMap { $0.isEmpty ? nil : $0 }
        self.colorHex = ircMessage.tags["color"].flatMap { $0.isEmpty ? nil : $0 }
        self.badges = Badge.parse(ircMessage.tags["badges"] ?? "")
    }
}
