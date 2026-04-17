// ChannelSearchResult.swift
// チャンネル検索結果モデル
// Twitch Helix API /helix/search/channels レスポンスを格納する

import Foundation

// MARK: - ドメインモデル

/// チャンネル検索結果（/helix/search/channels のレスポンス）
///
/// フォロー外チャンネルを検索する際に使用する。`isLive` でライブ状態が判定できる。
struct ChannelSearchResult: Sendable, Identifiable, Equatable {
    /// 配信者の Twitch ユーザーID（プロフィール画像キャッシュのキーとして使用）
    let id: String
    /// 配信者のログイン名（英数字小文字）
    let broadcasterLogin: String
    /// 配信者の表示名
    let displayName: String
    /// 配信中のゲーム名（ライブ中でない場合は空文字列の場合あり）
    let gameName: String
    /// ライブ配信中かどうか
    let isLive: Bool
}

// MARK: - Helix API レスポンスモデル

/// Helix API /helix/search/channels レスポンス
struct HelixSearchChannelsResponse: Decodable, Sendable {
    let data: [HelixSearchChannelData]
}

/// Helix API /helix/search/channels の各チャンネルデータ
struct HelixSearchChannelData: Decodable, Sendable {
    let id: String
    let broadcasterLogin: String
    let displayName: String
    let gameName: String
    let isLive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case broadcasterLogin = "broadcaster_login"
        case displayName = "display_name"
        case gameName = "game_name"
        case isLive = "is_live"
    }

    /// `HelixSearchChannelData` を `ChannelSearchResult` ドメインモデルに変換する
    func toChannelSearchResult() -> ChannelSearchResult {
        ChannelSearchResult(
            id: id,
            broadcasterLogin: broadcasterLogin,
            displayName: displayName,
            gameName: gameName,
            isLive: isLive
        )
    }
}
