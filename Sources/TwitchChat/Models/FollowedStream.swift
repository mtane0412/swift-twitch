// FollowedStream.swift
// フォロー中の配信中ストリーム情報モデル
// Twitch Helix API /streams/followed レスポンスを格納する

import Foundation

// MARK: - ドメインモデル

/// フォロー中の配信中ストリーム情報
///
/// サイドバーのライブリスト表示および IRC 接続に必要な情報を保持する
struct FollowedStream: Sendable, Identifiable, Equatable {
    /// Twitch ストリーム ID（`id` フィールド）
    let id: String
    /// 配信者の Twitch ユーザーID
    let userId: String
    /// 配信者のログイン名（英数字小文字、IRC チャンネル名として使用）
    let userLogin: String
    /// 配信者の表示名（日本語名なども含む）
    let userName: String
    /// 配信中のゲーム名
    let gameName: String
    /// 配信タイトル
    let title: String
    /// 現在の視聴者数
    let viewerCount: Int
    /// サムネイル URL テンプレート（{width}x{height} プレースホルダー付き）
    let thumbnailUrl: String
    /// 配信開始日時
    let startedAt: Date
}

// MARK: - Helix API レスポンスモデル

/// Helix API /helix/streams/followed レスポンス
struct HelixFollowedStreamsResponse: Decodable, Sendable {
    let data: [HelixFollowedStreamData]
}

/// Helix API /helix/streams/followed の各ストリームデータ
struct HelixFollowedStreamData: Decodable, Sendable {
    let id: String
    let userId: String
    let userLogin: String
    let userName: String
    let gameId: String
    let gameName: String
    let type: String
    let title: String
    let viewerCount: Int
    let startedAt: String
    let language: String
    let thumbnailUrl: String
    let isMature: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case gameId = "game_id"
        case gameName = "game_name"
        case type
        case title
        case viewerCount = "viewer_count"
        case startedAt = "started_at"
        case language
        case thumbnailUrl = "thumbnail_url"
        case isMature = "is_mature"
    }
}

// MARK: - 変換

extension HelixFollowedStreamData {
    /// `HelixFollowedStreamData` を `FollowedStream` ドメインモデルに変換する
    func toFollowedStream() -> FollowedStream? {
        // ISO8601 日付パース（Twitch API は末尾 Z の UTC 形式）
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: startedAt) else { return nil }
        return FollowedStream(
            id: id,
            userId: userId,
            userLogin: userLogin,
            userName: userName,
            gameName: gameName,
            title: title,
            viewerCount: viewerCount,
            thumbnailUrl: thumbnailUrl,
            startedAt: date
        )
    }
}
