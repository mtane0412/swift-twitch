// HelixVideo.swift
// Helix API /helix/videos レスポンスの DTO 定義
// video_id（VOD の一意識別子）をチャットメッセージと紐付けるために使用する

import Foundation

// MARK: - Helix /videos レスポンス

/// Helix GET /helix/videos のレスポンス全体
struct HelixVideosResponse: Decodable, Sendable {
    let data: [HelixVideoData]
}

/// Helix /helix/videos の各動画エントリー
struct HelixVideoData: Decodable, Sendable {
    /// VOD の一意識別子（video_id）
    let id: String
    /// 配信者のユーザー ID
    let userId: String
    /// この VOD に対応するストリーム ID（nil の場合はハイライト等）
    let streamId: String?
    /// 動画の種別（"archive" = 過去配信、"highlight"、"upload" など）
    let type: String
    /// 動画タイトル
    let title: String

    enum CodingKeys: String, CodingKey {
        case id, type, title
        case userId = "user_id"
        case streamId = "stream_id"
    }
}
