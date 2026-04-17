// FollowedChannelStore.swift
// フォロー中チャンネル一覧のキャッシュ + チャンネル名検索サービス
// 起動時に /helix/channels/followed で全フォロー済みチャンネル（オフライン含む）を取得し、
// インクリメンタルサーチのデータソースとして提供する

import Foundation
import Observation

/// フォロー中チャンネル一覧のキャッシュとチャンネル名検索を担うストア
///
/// 役割:
/// - 起動時に `/helix/channels/followed` で全フォロー済みチャンネルを取得（ページネーション対応）
/// - `ChannelSearchView` のインクリメンタルサーチに `channels` を提供する
/// - フォロー中チャンネルに一致がない場合は `searchChannels(query:)` で `/helix/search/channels` にフォールバックする
@Observable
@MainActor
final class FollowedChannelStore {

    // MARK: - 定数

    /// 1リクエストあたりの最大取得件数
    private static let maxPerPage = 100
    /// チャンネル検索の最大結果件数
    private static let maxSearchResults = 10

    /// Helix API エンドポイント
    private static let followedChannelsURL = URL(string: "https://api.twitch.tv/helix/channels/followed")!
    private static let searchChannelsURL = URL(string: "https://api.twitch.tv/helix/search/channels")!

    // MARK: - 公開プロパティ

    /// フォロー中の全チャンネル一覧（ライブ中でないチャンネルも含む）
    private(set) var channels: [FollowedChannel] = []

    /// データ取得中フラグ
    private(set) var isLoading = false

    // MARK: - プライベートプロパティ

    private let apiClient: any HelixAPIClientProtocol
    private let authState: AuthState?
    /// AuthState を使わずに直接 userId を指定する場合（テスト用）
    private let overrideUserId: String?

    // MARK: - 初期化

    /// FollowedChannelStore を初期化する（本番用）
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント
    ///   - authState: 認証状態（userId の取得に使用）
    init(apiClient: any HelixAPIClientProtocol, authState: AuthState) {
        self.apiClient = apiClient
        self.authState = authState
        self.overrideUserId = nil
    }

    /// FollowedChannelStore を初期化する（テスト用: userId 直接指定）
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント
    ///   - userId: 対象ユーザーID（nil の場合はフェッチをスキップ）
    init(apiClient: any HelixAPIClientProtocol, userId: String?) {
        self.apiClient = apiClient
        self.authState = nil
        self.overrideUserId = userId
    }

    // MARK: - 公開メソッド

    /// フォロー中の全チャンネルを取得してキャッシュする（ページネーション対応）
    ///
    /// - ページネーションカーソルが返される限り次ページを取得し続ける
    /// - ユーザーIDが未設定の場合はスキップする
    /// - 認証エラーはサイレントスキップする
    func fetchAll() async {
        guard let userId = currentUserId else { return }
        // 既にフェッチ中の場合は重複実行を防ぐ
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        var allChannels: [FollowedChannel] = []
        var cursor: String?

        // カーソルがなくなるまでページを取得する
        repeat {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "first", value: "\(Self.maxPerPage)")
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "after", value: cursor))
            }

            do {
                let response: HelixFollowedChannelsResponse = try await apiClient.get(
                    url: Self.followedChannelsURL,
                    queryItems: queryItems
                )
                allChannels.append(contentsOf: response.data.map { $0.toFollowedChannel() })
                cursor = response.pagination?.cursor
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                // 未ログイン時はサイレントスキップ
                return
            } catch {
                // その他のエラーはページネーションを中断し、取得済み分は保持する
                break
            }
        } while cursor != nil

        // 全ページ取得成功時のみキャッシュを更新する
        // cursor が非 nil で break した場合（途中エラー）は既存キャッシュを保持する
        if cursor == nil {
            channels = allChannels
        }
    }

    /// チャンネル名でチャンネルを検索する（フォロー外も含む）
    ///
    /// - フォロー中チャンネルに一致がない場合のフォールバック用途
    /// - 空文字列/スペースのみのクエリは API を呼ばずに空配列を返す
    ///
    /// - Parameter query: 検索クエリ
    /// - Returns: 検索にヒットした `ChannelSearchResult` の配列
    func searchChannels(query: String) async -> [ChannelSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let response: HelixSearchChannelsResponse = try await apiClient.get(
                url: Self.searchChannelsURL,
                queryItems: [
                    URLQueryItem(name: "query", value: trimmed),
                    URLQueryItem(name: "first", value: "\(Self.maxSearchResults)")
                ]
            )
            return response.data.map { $0.toChannelSearchResult() }
        } catch {
            return []
        }
    }

    /// チャンネル一覧をクリアする
    ///
    /// ログアウト時など、データを消去したい場合に使用する
    func clear() {
        channels = []
    }

    // MARK: - プライベートメソッド

    /// 有効なユーザーIDを取得する
    private var currentUserId: String? {
        overrideUserId ?? authState?.userId
    }
}
