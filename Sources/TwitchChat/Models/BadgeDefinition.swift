// BadgeDefinition.swift
// Twitch Helix API バッジ定義レスポンスモデル
// api.twitch.tv/helix/chat/badges からバッジ画像URLを取得するためのDecodable構造体

import Foundation

// MARK: - Helix バッジレスポンス

/// Helix `GET /helix/chat/badges/global` および
/// `GET /helix/chat/badges?broadcaster_id={id}` 共通レスポンス
struct HelixBadgesResponse: Decodable, Sendable {
    let data: [HelixBadgeSet]
}

/// Helix バッジセット（例: "subscriber", "broadcaster"）
struct HelixBadgeSet: Decodable, Sendable {
    /// バッジセット識別子（例: "subscriber", "broadcaster", "moderator"）
    let setId: String

    /// バッジの各バージョン（月数やレベルごとに異なる画像を持つ）
    let versions: [HelixBadgeVersion]

    enum CodingKeys: String, CodingKey {
        case setId = "set_id"
        case versions
    }
}

/// Helix バッジバージョン（バッジの各レベル・月数に対応）
struct HelixBadgeVersion: Decodable, Sendable {
    /// バージョン識別子（例: "0", "1", "3", "6"）
    let id: String

    /// バッジ画像 URL（1x スケール）
    let imageUrl1x: String

    /// バッジ画像 URL（2x スケール）
    let imageUrl2x: String

    /// バッジ画像 URL（4x スケール）
    let imageUrl4x: String

    /// バッジのタイトル（例: "Broadcaster", "Moderator"）
    let title: String

    /// バッジの説明
    let description: String

    enum CodingKeys: String, CodingKey {
        case id
        case imageUrl1x = "image_url_1x"
        case imageUrl2x = "image_url_2x"
        case imageUrl4x = "image_url_4x"
        case title
        case description
    }
}
