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
    ///           HTTP エラー時は `URLError(.badServerResponse)`
    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T
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
    ///           HTTP エラー時は `URLError(.badServerResponse)`
    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        // トークンが取得できない場合（未ログイン）はリクエストしない
        guard let token = await tokenProvider.fetchAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        // Client ID 未設定の場合は AuthConfigError.missingClientID をそのまま伝播する
        let clientId = try await tokenProvider.clientID()

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems

        guard let safeURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: safeURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.timeoutInterval = Self.requestTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
