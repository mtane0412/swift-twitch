// HelixAPIClient.swift
// Twitch Helix API への汎用アクセスクライアント
// 認証ヘッダーの組み立てと JSON デコードを一元管理する

import Foundation

// MARK: - トークンプロバイダープロトコル

/// Helix API 呼び出しに必要な認証情報を提供するプロトコル
///
/// `HelixAPIClient`（actor）と `AuthState`（@MainActor クラス）の分離境界を吸収するため、
/// 最小限のインターフェースとして切り出している。テスト時のモック差し替えも容易。
protocol HelixAPITokenProvider: Sendable {
    /// 現在の有効なアクセストークンを取得する。未ログインまたは取得失敗の場合は `nil`
    func fetchAccessToken() async -> String?

    /// Twitch アプリの Client ID を返す
    ///
    /// - Throws: `AuthConfigError.missingClientID` が未設定の場合
    func clientID() async throws -> String
}

// MARK: - Helix API クライアントプロトコル

/// Helix API クライアントの抽象化プロトコル
///
/// テスト時にモックを注入できるよう、actor 実装を抽象化する
protocol HelixAPIClientProtocol: Sendable {
    /// Helix API に GET リクエストを送信してレスポンスをデコードする
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    /// - Returns: デコードされたレスポンス型 `T`
    /// - Throws: トークン未設定時は `URLError(.userAuthenticationRequired)`、
    ///           HTTP エラー時は `HelixAPIError`
    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T

    /// Helix API に POST リクエストを送信してレスポンスをデコードする
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    ///   - body: JSON エンコードするリクエストボディ
    /// - Returns: デコードされたレスポンス型 `T`
    /// - Throws: `URLError(.userAuthenticationRequired)`、`HelixAPIError`
    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T

    /// Helix API に POST リクエストを送信する（レスポンスボディなし）
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    ///   - body: JSON エンコードするリクエストボディ
    /// - Throws: `URLError(.userAuthenticationRequired)`、`HelixAPIError`
    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws

    /// Helix API に PATCH リクエストを送信する（レスポンスボディなし）
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    ///   - body: JSON エンコードするリクエストボディ
    /// - Throws: `URLError(.userAuthenticationRequired)`、`HelixAPIError`
    func patch<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws

    /// Helix API に DELETE リクエストを送信する
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    /// - Throws: `URLError(.userAuthenticationRequired)`、`HelixAPIError`
    func delete(url: URL, queryItems: [URLQueryItem]?) async throws
}

// MARK: - Helix API クライアント実装

/// Twitch Helix API への汎用クライアント
///
/// 認証ヘッダー（`Authorization: Bearer <token>` と `Client-Id`）の組み立て、
/// JSON デコードを一元管理する。`BadgeStore` と `FollowedStreamStore` が共用する。
actor HelixAPIClient: HelixAPIClientProtocol {

    // MARK: - 定数

    /// リクエストのタイムアウト秒数
    private static let requestTimeout: TimeInterval = 10

    // MARK: - プロパティ

    private let tokenProvider: any HelixAPITokenProvider

    // MARK: - 初期化

    /// HelixAPIClient を初期化する
    ///
    /// - Parameter tokenProvider: Helix API 認証情報プロバイダー
    init(tokenProvider: any HelixAPITokenProvider) {
        self.tokenProvider = tokenProvider
    }

    // MARK: - 公開メソッド

    /// Helix API に GET リクエストを送信してレスポンスをデコードする
    ///
    /// - Parameters:
    ///   - url: リクエスト先エンドポイント URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    /// - Returns: デコードされたレスポンス型 `T`
    /// - Throws: トークン未設定時は `URLError(.userAuthenticationRequired)`、
    ///           HTTP エラー時は `HelixAPIError`
    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        let request = try await buildRequest(url: url, queryItems: queryItems, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Helix API に POST リクエストを送信してレスポンスをデコードする
    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws -> T {
        let request = try await buildRequest(url: url, queryItems: queryItems, method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Helix API に POST リクエストを送信する（レスポンスボディなし）
    func postNoContent<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        let request = try await buildRequest(url: url, queryItems: queryItems, method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data, allowNoContent: true)
    }

    /// Helix API に PATCH リクエストを送信する（レスポンスボディなし）
    func patch<Body: Encodable & Sendable>(
        url: URL, queryItems: [URLQueryItem]?, body: Body
    ) async throws {
        let request = try await buildRequest(url: url, queryItems: queryItems, method: "PATCH", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data, allowNoContent: true)
    }

    /// Helix API に DELETE リクエストを送信する
    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        let request = try await buildRequest(url: url, queryItems: queryItems, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data, allowNoContent: true)
    }

    // MARK: - プライベートヘルパー

    /// 認証済み URLRequest を構築する（ボディなし: GET/DELETE 用）
    ///
    /// - Parameters:
    ///   - url: リクエスト先 URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    ///   - method: HTTP メソッド（GET/DELETE）
    private func buildRequest(
        url: URL,
        queryItems: [URLQueryItem]?,
        method: String
    ) async throws -> URLRequest {
        guard let token = await tokenProvider.fetchAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let clientId = try await tokenProvider.clientID()
        return try buildURLRequest(url: url, queryItems: queryItems, method: method, token: token, clientId: clientId)
    }

    /// 認証済み URLRequest を構築する（ボディあり: POST/PATCH 用）
    ///
    /// - Parameters:
    ///   - url: リクエスト先 URL
    ///   - queryItems: クエリパラメータ（nil の場合はなし）
    ///   - method: HTTP メソッド（POST/PATCH）
    ///   - body: JSON エンコードするリクエストボディ
    private func buildRequest<Body: Encodable>(
        url: URL,
        queryItems: [URLQueryItem]?,
        method: String,
        body: Body
    ) async throws -> URLRequest {
        guard let token = await tokenProvider.fetchAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let clientId = try await tokenProvider.clientID()
        var request = try buildURLRequest(url: url, queryItems: queryItems, method: method, token: token, clientId: clientId)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// URLRequest の共通部分を構築する
    private func buildURLRequest(
        url: URL,
        queryItems: [URLQueryItem]?,
        method: String,
        token: String,
        clientId: String
    ) throws -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems

        guard let safeURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: safeURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = Self.requestTimeout
        return request
    }

    /// HTTP レスポンスのステータスコードを検証する
    ///
    /// - Parameters:
    ///   - response: URLResponse
    ///   - data: レスポンスボディ（エラーメッセージの抽出に使用）
    ///   - allowNoContent: true の場合、204 No Content を成功とみなす
    /// - Throws: `HelixAPIError` ステータスコードが 200/204 以外の場合
    private func validateResponse(_ response: URLResponse, data: Data, allowNoContent: Bool = false) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let statusCode = httpResponse.statusCode
        let isSuccess = statusCode == 200 || (allowNoContent && statusCode == 204)
        guard isSuccess else {
            // Helix API のエラーメッセージを抽出する（"message" フィールド）
            let message = extractHelixErrorMessage(from: data)
            throw HelixAPIError.from(statusCode: statusCode, message: message)
        }
    }

    /// Helix API のエラーレスポンスボディからメッセージを抽出する
    ///
    /// - Parameter data: レスポンスボディ
    /// - Returns: エラーメッセージ文字列（取得できない場合は空文字）
    private func extractHelixErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return ""
        }
        return message
    }
}
