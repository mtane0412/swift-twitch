// StreamPlaybackResolver.swift
// Twitch ライブ配信 HLS マニフェスト URL の解決
// GQL トークン取得から Usher URL 組み立てまでを一元管理する

import Foundation

// MARK: - プロトコル

/// Twitch ライブ配信の HLS マニフェスト URL を解決するプロトコル
///
/// テスト時にモックを注入できるよう抽象化する
protocol StreamPlaybackResolverProtocol: Sendable {
    /// 指定チャンネルの HLS マニフェスト URL を解決する
    ///
    /// - Parameter login: チャンネルログイン名
    /// - Returns: `StreamPlaybackManifest`
    /// - Throws: `PlaybackError`
    func resolve(login: String) async throws -> StreamPlaybackManifest
}

// MARK: - 実装

/// Twitch ライブ配信の HLS マニフェスト URL を解決する
///
/// 1. GQL PlaybackAccessToken を取得（`TwitchPlaybackTokenClientProtocol`）
/// 2. Usher URL を組み立てて `StreamPlaybackManifest` を返す
///
/// AVPlayer にはこの URL をそのまま渡して再生できる。
actor StreamPlaybackResolver: StreamPlaybackResolverProtocol {

    // MARK: - 定数

    /// Usher HLS マニフェストエンドポイントのベース URL
    private static let usherBaseURL = "https://usher.ttvnw.net/api/channel/hls"

    // MARK: - プロパティ

    private let tokenClient: any TwitchPlaybackTokenClientProtocol
    private let options: PlaybackOptions

    // MARK: - 初期化

    /// `StreamPlaybackResolver` を初期化する
    ///
    /// - Parameters:
    ///   - tokenClient: GQL アクセストークン取得クライアント（`nil` のとき `options.adServingEnabled` を反映して生成する）
    ///   - options: HLS 再生オプション（省略時は `.default`）
    init(
        tokenClient: (any TwitchPlaybackTokenClientProtocol)? = nil,
        options: PlaybackOptions = .default
    ) {
        self.tokenClient = tokenClient ?? TwitchPlaybackTokenClient(adServingEnabled: options.adServingEnabled)
        self.options = options
    }

    // MARK: - 公開メソッド

    /// 指定チャンネルの HLS マニフェスト URL を解決する
    ///
    /// - Parameter login: チャンネルログイン名（大小文字不問、内部で小文字化する）
    /// - Returns: AVPlayer に渡せる `StreamPlaybackManifest`
    /// - Throws: `PlaybackError`
    func resolve(login: String) async throws -> StreamPlaybackManifest {
        let normalizedLogin = login.lowercased()
        let token = try await tokenClient.fetchLiveToken(login: normalizedLogin)
        let url = try buildUsherURL(login: normalizedLogin, token: token)
        return StreamPlaybackManifest(url: url, fetchedAt: Date())
    }

    // MARK: - プライベートヘルパー

    private func buildUsherURL(login: String, token: StreamPlaybackToken) throws -> URL {
        guard var components = URLComponents(string: "\(Self.usherBaseURL)/\(login).m3u8") else {
            throw PlaybackError.badURL
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "fast_bread", value: "true"),
            URLQueryItem(name: "p", value: String(Int.random(in: 100000...999999))),
            URLQueryItem(name: "play_session_id", value: UUID().uuidString.lowercased()),
            URLQueryItem(name: "player_backend", value: "mediaplayer"),
            URLQueryItem(name: "playlist_include_framerate", value: "true"),
            URLQueryItem(name: "reassignments_supported", value: "true"),
            URLQueryItem(name: "sig", value: token.signature),
            URLQueryItem(name: "supported_codecs", value: options.supportedCodecs.joined(separator: ",")),
            URLQueryItem(name: "token", value: token.value),
            URLQueryItem(name: "cdm", value: "wv"),
            URLQueryItem(name: "player_version", value: "1.27.0")
        ]

        if options.lowLatencyEnabled {
            queryItems.append(URLQueryItem(name: "low_latency", value: "true"))
        }

        if options.adServingEnabled {
            queryItems.append(URLQueryItem(name: "platform", value: "web"))
            queryItems.append(URLQueryItem(name: "player_type", value: "site"))
            queryItems.append(URLQueryItem(name: "server_ads", value: "true"))
            queryItems.append(URLQueryItem(name: "allow_audio_only", value: "true"))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw PlaybackError.badURL
        }
        return url
    }
}
