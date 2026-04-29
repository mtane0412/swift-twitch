// TwitchPlaybackTokenClient.swift
// Twitch GQL PlaybackAccessToken 取得クライアント
// HLS 再生に必要な署名付きトークンを gql.twitch.tv から取得する

import Foundation

// MARK: - データフェッチャープロトコル

/// HTTP リクエストを送信してレスポンスデータを返すプロトコル
///
/// テスト時にモックを注入できるよう `URLSession` の依存を抽象化する
protocol URLSessionDataFetcher: Sendable {
    /// URLRequest を送信してレスポンスデータと URLResponse を返す
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataFetcher {}

// MARK: - プロトコル

/// Twitch ライブ配信の再生用アクセストークン取得クライアントプロトコル
///
/// テスト時にモックを注入できるよう抽象化する
protocol TwitchPlaybackTokenClientProtocol: Sendable {
    /// 指定チャンネルのライブ配信用 HLS アクセストークンを取得する
    ///
    /// - Parameter login: チャンネルログイン名（小文字）
    /// - Returns: HLS マニフェスト URL 用の `StreamPlaybackToken`
    /// - Throws: `PlaybackError`
    func fetchLiveToken(login: String) async throws -> StreamPlaybackToken
}

// MARK: - 実装

/// Twitch GQL PlaybackAccessToken 取得クライアント
///
/// `gql.twitch.tv/gql` に `PlaybackAccessToken` persisted query を送信し、
/// HLS 再生に必要な署名付きトークンを返す。Twitch の公開 Web Client-ID を使う匿名アクセス。
///
/// - Important: この API は Twitch 非公開のため、利用規約上グレー。
///              GQL persisted query ハッシュは Twitch Web 更新で変わる可能性がある。
actor TwitchPlaybackTokenClient: TwitchPlaybackTokenClientProtocol {

    // MARK: - 定数

    /// GQL PlaybackAccessToken の persisted query SHA-256 ハッシュ
    ///
    /// Twitch Web の内部 GQL ハッシュ。Web アプリ更新により変更される可能性がある。
    fileprivate static let liveQueryHash = "0828119ded1c13477966434e15800ff57ddacf13ba1911c129dc2200705b0712"

    /// GQL エンドポイント
    private static let gqlEndpoint = URL(string: "https://gql.twitch.tv/gql")!

    /// リクエストタイムアウト秒数
    private static let requestTimeout: TimeInterval = 4

    // MARK: - プロパティ

    private let dataFetcher: any URLSessionDataFetcher
    private let clientID: String
    /// SSAI セッション管理用デバイス識別子（32 文字 lowercase hex、インスタンスごとに生成）
    private let deviceID: String

    // MARK: - 初期化

    /// `TwitchPlaybackTokenClient` を初期化する
    ///
    /// - Parameters:
    ///   - dataFetcher: HTTP リクエストを実行するデータフェッチャー（テスト時はモックを渡す）
    ///   - clientID: GQL リクエストに付与する Client-Id ヘッダー値
    ///   - deviceID: `X-Device-Id` ヘッダー値（`nil` のとき内部でランダム生成する。テスト時に固定値を注入可能）
    init(
        dataFetcher: any URLSessionDataFetcher = TwitchPlaybackTokenClient.makeDefaultSession(),
        clientID: String = TwitchPlaybackTokenClient.webClientID,
        deviceID: String? = nil
    ) {
        self.dataFetcher = dataFetcher
        self.clientID = clientID
        self.deviceID = deviceID ?? TwitchPlaybackTokenClient.makeDeviceID()
    }

    // MARK: - 公開メソッド

    /// 指定チャンネルのライブ配信用 HLS アクセストークンを取得する
    ///
    /// - Parameter login: チャンネルログイン名
    /// - Returns: `StreamPlaybackToken`
    /// - Throws: `PlaybackError`
    func fetchLiveToken(login: String) async throws -> StreamPlaybackToken {
        let request = try buildRequest(login: login.lowercased())
        let (data, response) = try await fetchData(request: request)
        try validateHTTPResponse(response, data: data)
        return try decodeToken(from: data)
    }

    // MARK: - プライベートヘルパー

    private func buildRequest(login: String) throws -> URLRequest {
        var request = URLRequest(url: Self.gqlEndpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = try JSONEncoder().encode(GQLPlaybackTokenBody(login: login))
        return request
    }

    private func fetchData(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await dataFetcher.data(for: request)
        } catch let urlError as URLError {
            throw PlaybackError.network(urlError)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PlaybackError.network(URLError(.badServerResponse))
        }
        guard http.statusCode == 200 else {
            throw PlaybackError.tokenRequestFailed(statusCode: http.statusCode)
        }
    }

    private func decodeToken(from data: Data) throws -> StreamPlaybackToken {
        do {
            let gqlResponse = try JSONDecoder().decode(GQLPlaybackTokenResponse.self, from: data)
            let accessToken = gqlResponse.data.streamPlaybackAccessToken
            return StreamPlaybackToken(value: accessToken.value, signature: accessToken.signature)
        } catch {
            throw PlaybackError.tokenDecodingFailed
        }
    }
}

// MARK: - GQL リクエストボディ

/// GQL PlaybackAccessToken persisted query のリクエストボディ
private struct GQLPlaybackTokenBody: Encodable {
    let operationName = "PlaybackAccessToken"
    let extensions: GQLExtensions
    let variables: GQLVariables

    init(login: String) {
        self.extensions = GQLExtensions(
            persistedQuery: GQLPersistedQuery(sha256Hash: TwitchPlaybackTokenClient.liveQueryHash)
        )
        self.variables = GQLVariables(login: login)
    }
}

private struct GQLExtensions: Encodable {
    let persistedQuery: GQLPersistedQuery
}

private struct GQLPersistedQuery: Encodable {
    let version = 1
    let sha256Hash: String
}

private struct GQLVariables: Encodable {
    let isLive = true
    let login: String
    let isVod = false
    let vodID = ""
    let playerType = "site"
    let platform = "web"
}

// MARK: - ファクトリ

extension TwitchPlaybackTokenClient {

    /// Twitch Web の公開 Client-ID
    ///
    /// Bearer トークンを送らない匿名アクセス用。サブスク限定配信は視聴不可。
    static let webClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

    /// デフォルト URLSession を生成する（OS キャッシュを無効化した独立セッション）
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    /// SSAI セッション管理用デバイス識別子を生成する（32 文字 lowercase hex）
    static func makeDeviceID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
