// TwitchTokenResponse.swift
// Twitch OAuth API のレスポンスモデル定義
// トークン交換・検証・失効の各エンドポイントのレスポンスを表す

import Foundation

// MARK: - トークン交換レスポンス

/// Twitch トークンエンドポイントのレスポンス
///
/// Authorization Code Grant で取得したアクセストークン・リフレッシュトークンを保持する
struct TwitchTokenResponse: Codable, Sendable {
    /// アクセストークン
    let accessToken: String
    /// リフレッシュトークン
    let refreshToken: String
    /// アクセストークンの有効期限（秒）
    let expiresIn: Int
    /// トークンタイプ（通常 "bearer"）
    let tokenType: String
    /// 付与されたスコープ一覧
    let scope: [String]?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

// MARK: - トークン検証レスポンス

/// Twitch トークン検証エンドポイントのレスポンス
///
/// `GET https://id.twitch.tv/oauth2/validate` で取得する
/// トークンの有効期限・ユーザー情報を確認するために使用する
struct TwitchValidateResponse: Codable, Sendable {
    /// アプリの Client ID
    let clientId: String
    /// ユーザーのログイン名（小文字）
    let login: String
    /// ユーザー ID
    let userId: String
    /// 付与されたスコープ一覧
    let scopes: [String]
    /// アクセストークンの残り有効期限（秒）
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case login
        case userId = "user_id"
        case scopes
        case expiresIn = "expires_in"
    }
}

// MARK: - Device Code フローレスポンス

/// Twitch Device Authorization エンドポイントのレスポンス
///
/// `POST https://id.twitch.tv/oauth2/device` で取得する
struct TwitchDeviceCodeResponse: Codable, Sendable {
    /// デバイスコード（トークンポーリングに使用）
    let deviceCode: String
    /// ユーザーが twitch.tv/activate で入力するコード
    let userCode: String
    /// ユーザーが認証ページを開く URL
    let verificationUri: String
    /// デバイスコードの有効期限（秒）
    let expiresIn: Int
    /// ポーリング間隔（秒）
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

// MARK: - OAuth エラーレスポンス

/// Twitch OAuth エラーレスポンス
///
/// Twitch OAuth エンドポイントが返す標準エラー形式
/// 例: `{"error": "Bad Request", "status": 400, "message": "authorization_pending"}`
/// `error` フィールドはエンドポイントによって省略される場合があるため optional
struct TwitchOAuthError: Codable, Sendable, Error, Equatable {
    let error: String?
    let status: Int
    let message: String
}
