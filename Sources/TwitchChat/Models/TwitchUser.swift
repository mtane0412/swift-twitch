// TwitchUser.swift
// Twitch ユーザー情報モデル
// Twitch Helix API /helix/users レスポンスを格納し、プロフィール画像URLを提供する

import Foundation

// MARK: - Helix API レスポンスモデル

/// Helix API /helix/users レスポンス
struct HelixUsersResponse: Decodable, Sendable {
    let data: [HelixUserData]
}

/// Helix API /helix/users の各ユーザーデータ（ドメインモデルとしても使用する）
///
/// `TwitchUser` と `HelixUserData` は同一のプロパティを持つため、
/// `HelixUserData` をドメインモデルとして直接利用する。
struct HelixUserData: Decodable, Sendable, Identifiable, Equatable {
    /// Twitch ユーザーID
    let id: String
    /// ログイン名（英数字小文字）
    let login: String
    /// 表示名（日本語名なども含む）
    let displayName: String
    /// プロフィール画像 URL
    let profileImageUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case displayName = "display_name"
        case profileImageUrl = "profile_image_url"
    }
}
