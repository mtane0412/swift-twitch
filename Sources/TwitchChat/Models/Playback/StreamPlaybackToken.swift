// StreamPlaybackToken.swift
// Twitch GQL PlaybackAccessToken レスポンスの DTO

import Foundation

/// Twitch GQL から取得した HLS 再生用アクセストークン
struct StreamPlaybackToken: Sendable {
    /// HLS マニフェスト URL に付与するトークン文字列（JWT 形式）
    let value: String
    /// HLS マニフェスト URL に付与する署名文字列
    let signature: String
}

// MARK: - GQL レスポンス DTO（デコード専用）

/// GQL PlaybackAccessToken クエリのルートレスポンス
struct GQLPlaybackTokenResponse: Decodable {
    let data: GQLPlaybackTokenData
}

/// GQL レスポンス data フィールド
struct GQLPlaybackTokenData: Decodable {
    let streamPlaybackAccessToken: GQLAccessToken
}

/// GQL レスポンス内のアクセストークンオブジェクト
struct GQLAccessToken: Decodable {
    let value: String
    let signature: String
}
