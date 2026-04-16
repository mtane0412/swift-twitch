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
    /// プロフィール画像 URL（空文字列・不正URLの場合は nil）
    let profileImageUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case displayName = "display_name"
        case profileImageUrl = "profile_image_url"
    }

    /// カスタムデコードイニシャライザ
    ///
    /// - `profile_image_url` が空文字列または不正URLの場合、`profileImageUrl` を `nil` にする
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        login = try container.decode(String.self, forKey: .login)
        displayName = try container.decode(String.self, forKey: .displayName)
        let urlString = try container.decode(String.self, forKey: .profileImageUrl)
        profileImageUrl = URL(string: urlString)
    }

    /// テスト用メンバーワイズイニシャライザ
    init(id: String, login: String, displayName: String, profileImageUrl: URL?) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.profileImageUrl = profileImageUrl
    }
}
