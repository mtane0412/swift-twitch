// TwitchAuthClient.swift
// Twitch OAuth Device Code Flow を管理するクライアント
// デバイスコードを取得し、ユーザーが twitch.tv/activate で認証するまでポーリングする

import Foundation
import AppKit

// MARK: - プロトコル

/// Twitch OAuth クライアントのプロトコル
///
/// テスト時にモックへの差し替えを可能にするため抽象化する
@MainActor
protocol TwitchAuthClientProtocol: AnyObject {
    /// デバイスコードを取得する
    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse

    /// デバイスコードが認証されるまでポーリングしてトークンを取得する
    ///
    /// - Parameters:
    ///   - deviceCode: `requestDeviceCode()` で取得したデバイスコード
    ///   - interval: ポーリング間隔（秒）
    func pollForToken(deviceCode: String, interval: Int) async throws -> TwitchTokenResponse

    /// リフレッシュトークンで新しいアクセストークンを取得する
    func refreshToken(refreshToken: String) async throws -> TwitchTokenResponse

    /// アクセストークンの有効性を検証する
    func validateToken(accessToken: String) async throws -> TwitchValidateResponse

    /// アクセストークンを失効させる
    func revokeToken(accessToken: String) async throws
}

// MARK: - 実装

/// Twitch OAuth クライアント（Device Code Flow）
///
/// **認証フロー:**
/// 1. `requestDeviceCode()` でデバイスコードとユーザーコードを取得
/// 2. ユーザーコードを UI に表示し、デフォルトブラウザで `verification_uri` を開く
/// 3. ユーザーが `twitch.tv/activate` でコードを入力して認証
/// 4. `pollForToken()` が認証完了を検出してアクセストークンを返す
@MainActor
final class TwitchAuthClient: TwitchAuthClientProtocol {

    // MARK: - プロパティ

    private let urlSession: URLSession

    // MARK: - 初期化

    /// TwitchAuthClient を初期化する
    ///
    /// - Parameter urlSession: HTTP リクエスト用セッション（テスト時はモックを注入）
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - パブリックメソッド

    /// デバイスコードを取得する
    ///
    /// - Returns: デバイスコード・ユーザーコード・認証 URL などを含むレスポンス
    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse {
        let clientID = try AuthConfig.clientID()
        var request = URLRequest(url: AuthConfig.deviceURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Twitch Device Code エンドポイントは `scopes`（複数形）を使用する
        let scopeString = AuthConfig.scopes
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
            .joined(separator: "+")
        request.httpBody = "client_id=\(clientID)&scopes=\(scopeString)".data(using: .utf8)

        #if DEBUG
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("[TwitchAuth] Device code request body: \(bodyString)")
        }
        #endif

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchAuthError.networkError
        }

        #if DEBUG
        print("[TwitchAuth] Device code response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("[TwitchAuth] Device code response: \(responseString)")
        }
        #endif

        guard httpResponse.statusCode == 200 else {
            if let oauthError = try? JSONDecoder().decode(TwitchOAuthError.self, from: data) {
                throw TwitchAuthError.oauthError(oauthError)
            }
            throw TwitchAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(TwitchDeviceCodeResponse.self, from: data)
    }

    /// デバイスコードが認証されるまでポーリングしてトークンを取得する
    ///
    /// Twitch の `authorization_pending` レスポンスを受け取る間はポーリングを継続する
    /// `slow_down` レスポンス時はポーリング間隔を 5 秒延長する
    ///
    /// - Parameters:
    ///   - deviceCode: `requestDeviceCode()` で取得したデバイスコード
    ///   - interval: 初期ポーリング間隔（秒）
    func pollForToken(deviceCode: String, interval: Int) async throws -> TwitchTokenResponse {
        let clientID = try AuthConfig.clientID()
        var currentInterval = interval

        while true {
            // ポーリング間隔を待機（キャンセル時は CancellationError をスロー）
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            var request = URLRequest(url: AuthConfig.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TwitchAuthError.networkError
            }

            if httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(TwitchTokenResponse.self, from: data)
            }

            // エラーレスポンスを解析してポーリング継続・終了を判断
            guard let oauthError = try? JSONDecoder().decode(TwitchOAuthError.self, from: data) else {
                throw TwitchAuthError.httpError(statusCode: httpResponse.statusCode)
            }

            switch oauthError.message {
            case "authorization_pending":
                // ユーザーがまだ認証していない → 次のポーリングまで待機
                continue
            case "slow_down":
                // サーバーの要求に応じてポーリング間隔を延長
                currentInterval += 5
                continue
            case "expired_token":
                throw TwitchAuthError.tokenExpired
            case "access_denied":
                throw TwitchAuthError.userCancelled
            default:
                throw TwitchAuthError.oauthError(oauthError)
            }
        }
    }

    /// リフレッシュトークンで新しいアクセストークンを取得する
    func refreshToken(refreshToken: String) async throws -> TwitchTokenResponse {
        let clientID = try AuthConfig.clientID()
        var request = URLRequest(url: AuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        if let secret = AuthConfig.clientSecret() {
            body["client_secret"] = secret
        }
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        return try await performTokenRequest(request)
    }

    /// アクセストークンの有効性を検証する
    func validateToken(accessToken: String) async throws -> TwitchValidateResponse {
        var request = URLRequest(url: AuthConfig.validateURL)
        request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchAuthError.networkError
        }
        if httpResponse.statusCode == 401 {
            throw TwitchAuthError.tokenExpired
        }
        guard httpResponse.statusCode == 200 else {
            throw TwitchAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(TwitchValidateResponse.self, from: data)
    }

    /// アクセストークンを失効させる
    func revokeToken(accessToken: String) async throws {
        let clientID = try AuthConfig.clientID()
        var request = URLRequest(url: AuthConfig.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "client_id=\(clientID)&token=\(accessToken)"
        request.httpBody = body.data(using: .utf8)

        // 失効は失敗してもログアウト処理を続行するため、エラーは無視する
        _ = try? await urlSession.data(for: request)
    }

    // MARK: - プライベートメソッド

    /// トークンエンドポイントへのリクエストを実行し、レスポンスをデコードする
    private func performTokenRequest(_ request: URLRequest) async throws -> TwitchTokenResponse {
        #if DEBUG
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("[TwitchAuth] Token request body: \(bodyString)")
        }
        #endif

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchAuthError.networkError
        }

        #if DEBUG
        print("[TwitchAuth] Token response status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("[TwitchAuth] Token response body: \(responseString)")
        }
        #endif

        guard httpResponse.statusCode == 200 else {
            if let oauthError = try? JSONDecoder().decode(TwitchOAuthError.self, from: data) {
                throw TwitchAuthError.oauthError(oauthError)
            }
            throw TwitchAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(TwitchTokenResponse.self, from: data)
    }
}

// MARK: - エラー定義

/// Twitch OAuth 認証エラー
enum TwitchAuthError: Error, LocalizedError, Equatable {
    case missingAuthorizationCode
    case userCancelled
    case networkError
    case httpError(statusCode: Int)
    case tokenExpired
    case oauthError(TwitchOAuthError)

    var errorDescription: String? {
        switch self {
        case .missingAuthorizationCode: return "認可コードが取得できませんでした"
        case .userCancelled: return "ログインがキャンセルされました"
        case .networkError: return "ネットワークエラーが発生しました"
        case .httpError(let code): return "HTTP エラー: \(code)"
        case .tokenExpired: return "アクセストークンの有効期限が切れています"
        case .oauthError(let err): return "OAuth エラー: \(err.message)"
        }
    }
}
