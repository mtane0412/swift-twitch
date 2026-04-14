// BadgeStore.swift
// Twitch バッジ定義の取得・管理サービス
// Twitch GQL から グローバル・チャンネルバッジ定義をフェッチし、画像URLを解決する

import Foundation

/// バッジ定義の URL マッピング型
/// [バッジ名: [バージョン: 画像URLString]]
typealias BadgeURLMapping = [String: [String: String]]

/// Twitch バッジ定義の取得・管理を行うサービス
///
/// - グローバルバッジ（broadcaster, moderator, vip 等）は接続時に1回フェッチ
/// - チャンネルバッジ（subscriber 等の独自アート）は room-id 取得後にフェッチ
/// - imageURL(for:) はチャンネルバッジを優先し、なければグローバルにフォールバック
actor BadgeStore {

    // MARK: - 定数

    /// Twitch GQL エンドポイント
    private static let gqlEndpoint = URL(string: "https://gql.twitch.tv/gql")!

    /// Twitch GQL Client-ID（公開クライアントID）
    private static let gqlClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

    // MARK: - 状態

    /// グローバルバッジのURLマッピング
    private var globalBadges: BadgeURLMapping = [:]

    /// チャンネルバッジのURLマッピング
    private var channelBadges: BadgeURLMapping = [:]

    /// グローバルバッジ取得済みフラグ
    private var isGlobalLoaded = false

    // MARK: - 公開メソッド

    /// グローバルバッジ定義をフェッチする
    ///
    /// 二重フェッチを防止するため、取得済みの場合はスキップする
    func fetchGlobalBadges() async {
        guard !isGlobalLoaded else { return }
        guard let response = try? await fetchGQL(
            query: "{ badges { id title imageURL(size: DOUBLE) } }",
            responseType: GQLBadgesResponse.self
        ) else { return }
        globalBadges = Self.buildMapping(from: response.data.badges)
        isGlobalLoaded = true
    }

    /// チャンネルバッジ定義をフェッチする
    ///
    /// - Parameter channelId: Twitch チャンネルID（IRCの room-id タグの値）
    func fetchChannelBadges(channelId: String) async {
        let query = "{ user(id: \"\(channelId)\") { broadcastBadges { id title imageURL(size: DOUBLE) } } }"
        guard let response = try? await fetchGQL(
            query: query,
            responseType: GQLChannelBadgesResponse.self
        ) else { return }
        channelBadges = Self.buildMapping(from: response.data.user.broadcastBadges)
    }

    /// バッジの画像 URL を解決する
    ///
    /// チャンネルバッジを優先し、見つからない場合はグローバルバッジにフォールバックする
    ///
    /// - Parameter badge: IRC から取得した Badge
    /// - Returns: バッジ画像の URL、未登録の場合は nil
    func imageURL(for badge: Badge) -> URL? {
        let urlString = channelBadges[badge.name]?[badge.version]
            ?? globalBadges[badge.name]?[badge.version]
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    // MARK: - テスト用メソッド

    /// グローバルバッジのURLマッピングを直接設定する（テスト用）
    func setGlobalBadges(_ mapping: BadgeURLMapping) {
        globalBadges = mapping
        isGlobalLoaded = true
    }

    /// チャンネルバッジのURLマッピングを直接設定する（テスト用）
    func setChannelBadges(_ mapping: BadgeURLMapping) {
        channelBadges = mapping
    }

    // MARK: - 静的ユーティリティ

    /// GQLBadgeItem の配列から URLマッピングを構築する
    ///
    /// - Parameter items: GQL バッジアイテムの配列
    /// - Returns: [バッジ名: [バージョン: URLString]] のマッピング
    static func buildMapping(from items: [GQLBadgeItem]) -> BadgeURLMapping {
        var mapping: BadgeURLMapping = [:]
        for item in items {
            guard let parsed = item.parsedNameAndVersion else { continue }
            if mapping[parsed.name] == nil {
                mapping[parsed.name] = [:]
            }
            mapping[parsed.name]?[parsed.version] = item.imageURL
        }
        return mapping
    }

    // MARK: - プライベートメソッド

    /// GQL リクエストを送信して結果をデコードする
    private func fetchGQL<T: Decodable>(query: String, responseType: T.Type) async throws -> T {
        var request = URLRequest(url: Self.gqlEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.gqlClientID, forHTTPHeaderField: "Client-Id")

        let body = ["query": query]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
