// FollowedChannel.swift
// フォロー中チャンネル情報モデル（ライブ中でないチャンネルも含む）
// Twitch Helix API /helix/channels/followed レスポンスを格納する

import Foundation

// MARK: - ドメインモデル

/// フォロー中チャンネル情報（ライブ状態に関わらず全フォロー済みチャンネルを表す）
///
/// `FollowedStream` はライブ中のみ取得できるが、`FollowedChannel` はオフラインチャンネルも含む。
/// チャンネル名入力補完のデータソースとして使用する。
struct FollowedChannel: Sendable, Identifiable, Equatable, Hashable {
    var id: String { broadcasterId }
    /// 配信者の Twitch ユーザーID
    let broadcasterId: String
    /// 配信者のログイン名（英数字小文字、IRC チャンネル名として使用）
    let broadcasterLogin: String
    /// 配信者の表示名（日本語名なども含む）
    let broadcasterName: String
}

// MARK: - Helix API レスポンスモデル

/// Helix API /helix/channels/followed レスポンス
struct HelixFollowedChannelsResponse: Decodable, Sendable {
    let data: [HelixFollowedChannelData]
    /// ページネーションカーソル（次ページがない場合は nil）
    let pagination: HelixPaginationCursor?
}

/// ページネーションカーソル
struct HelixPaginationCursor: Decodable, Sendable {
    let cursor: String?
}

/// Helix API /helix/channels/followed の各チャンネルデータ
struct HelixFollowedChannelData: Decodable, Sendable {
    let broadcasterId: String
    let broadcasterLogin: String
    let broadcasterName: String

    enum CodingKeys: String, CodingKey {
        case broadcasterId = "broadcaster_id"
        case broadcasterLogin = "broadcaster_login"
        case broadcasterName = "broadcaster_name"
    }

    /// `HelixFollowedChannelData` を `FollowedChannel` ドメインモデルに変換する
    func toFollowedChannel() -> FollowedChannel {
        FollowedChannel(
            broadcasterId: broadcasterId,
            broadcasterLogin: broadcasterLogin,
            broadcasterName: broadcasterName
        )
    }
}
