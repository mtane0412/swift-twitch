// BadgeDefinition.swift
// Twitch GQL バッジ定義APIのレスポンスモデル
// gql.twitch.tv からバッジ画像URLを取得するためのDecodable構造体

import Foundation

// MARK: - グローバルバッジレスポンス

/// GQL `{ badges }` クエリのレスポンス全体
struct GQLBadgesResponse: Decodable, Sendable {
    let data: GQLBadgesData
}

/// GQL バッジデータ
struct GQLBadgesData: Decodable, Sendable {
    let badges: [GQLBadgeItem]
}

// MARK: - チャンネルバッジレスポンス

/// GQL `{ user(id:) { broadcastBadges } }` クエリのレスポンス全体
struct GQLChannelBadgesResponse: Decodable, Sendable {
    let data: GQLChannelBadgesData
}

/// GQL チャンネルバッジデータ
struct GQLChannelBadgesData: Decodable, Sendable {
    let user: GQLUserBadges
}

/// GQL ユーザーのバッジ情報
struct GQLUserBadges: Decodable, Sendable {
    let broadcastBadges: [GQLBadgeItem]
}

// MARK: - バッジアイテム

/// GQL バッジアイテム
///
/// GQL のバッジIDは base64 エンコードされた `"{name};{version};"` または
/// `"{name};{version};{channelId}"` の形式。
struct GQLBadgeItem: Decodable, Sendable {
    /// base64エンコードされたバッジ識別子
    let id: String

    /// バッジのタイトル（例: "Broadcaster", "Moderator"）
    let title: String

    /// バッジ画像の URL（2xスケール）
    let imageURL: String

    /// base64エンコードされた id からバッジ名とバージョンを取得する
    ///
    /// - Returns: (name, version) のタプル、デコード失敗時は nil
    var parsedNameAndVersion: (name: String, version: String)? {
        guard let decoded = Data(base64Encoded: id),
              let str = String(data: decoded, encoding: .utf8) else { return nil }
        // フォーマット: "name;version;" または "name;version;channelId"
        let parts = str.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty else { return nil }
        return (name: String(parts[0]), version: String(parts[1]))
    }
}
