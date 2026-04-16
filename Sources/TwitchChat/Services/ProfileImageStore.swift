// ProfileImageStore.swift
// Twitch ユーザーのプロフィール画像URL取得・管理サービス
// Helix API /helix/users を呼び出し、userId → profileImageUrl のマッピングをキャッシュする

import Foundation
import Observation
import os

/// Twitch ユーザーのプロフィール画像URL を管理するストア
///
/// - `fetchUsers(userIds:)` で複数ユーザーのプロフィール画像URLを一括取得する
/// - 取得済みユーザーは再取得しない（キャッシュ済みとして扱う）
/// - Helix API の制限（1リクエスト100件）を超える場合は自動的にチャンク分割する
/// - キャッシュエントリ数は `maxCacheEntries` を上限とする（上限超過時に全消去）
/// - `clear()` でキャッシュをクリアする（ログアウト時など）
@Observable
@MainActor
final class ProfileImageStore {

    // MARK: - 定数

    /// Helix API エンドポイント
    private static let usersURL = URL(string: "https://api.twitch.tv/helix/users")!

    /// 1リクエストあたりの最大ユーザーID数（Twitch Helix API の制限）
    private static let maxIdsPerRequest = 100

    /// キャッシュの最大エントリ数（超過時に全消去してメモリ増大を防ぐ）
    private static let maxCacheEntries = 1000

    // MARK: - プライベートプロパティ

    /// userId → profileImageUrl のキャッシュ
    private var profileImageUrls: [String: URL] = [:]

    /// API レスポンスを受信済みの userId セット
    ///
    /// `profileImageUrl` が nil（空URL）のユーザーも含めて追跡し、繰り返しの API 呼び出しを防ぐ
    private var fetchedUserIds: Set<String> = []

    /// 現在フェッチ中の userId セット
    ///
    /// `@MainActor` の await サスペンション中に別タスクが同じ userId を重複リクエストするのを防ぐ
    private var inFlightUserIds: Set<String> = []

    private let apiClient: any HelixAPIClientProtocol

    private let logger = Logger(subsystem: "dev.mtane.TwitchChat", category: "ProfileImageStore")

    // MARK: - 初期化

    /// ProfileImageStore を初期化する
    ///
    /// - Parameter apiClient: Helix API クライアント
    init(apiClient: any HelixAPIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - 公開メソッド

    /// 指定ユーザーIDのプロフィール画像URLを取得する
    ///
    /// - Parameter userId: Twitch ユーザーID
    /// - Returns: プロフィール画像URL（未取得またはユーザーが存在しない場合は `nil`）
    func profileImageUrl(for userId: String) -> URL? {
        profileImageUrls[userId]
    }

    /// 複数ユーザーのプロフィール画像URLを一括取得する
    ///
    /// - Parameter userIds: 取得対象の Twitch ユーザーID 一覧
    /// - Note: 取得済みユーザーは API を呼ばない。100件超の場合は自動チャンク分割。
    ///         認証エラーはサイレントスキップ（プロフィール画像は必須ではないため）。
    func fetchUsers(userIds: [String]) async {
        // 未取得かつフェッチ中でないユーザーのみ対象にする
        // fetchedUserIds でフェッチ済み（URL が nil のユーザーを含む）を除外し、
        // @MainActor の await サスペンション中に別タスクが同じ ID を重複リクエストする問題を防ぐ
        let newUserIds = userIds.filter { !fetchedUserIds.contains($0) && !inFlightUserIds.contains($0) }
        guard !newUserIds.isEmpty else { return }

        // フェッチ中フラグを設定し、完了後に必ず解除する
        inFlightUserIds.formUnion(newUserIds)
        defer { inFlightUserIds.subtract(newUserIds) }

        // Helix API の100件制限に合わせてチャンク分割してリクエスト
        let chunks = newUserIds.chunked(into: Self.maxIdsPerRequest)
        for chunk in chunks {
            await fetchChunk(userIds: chunk)
        }
    }

    /// プロフィール画像URLキャッシュをクリアする
    ///
    /// ログアウト時など、データを消去したい場合に使用する
    func clear() {
        profileImageUrls = [:]
        fetchedUserIds = []
        inFlightUserIds = []
    }

    // MARK: - プライベートメソッド

    /// ユーザーIDのチャンク（100件以下）に対してAPIを呼び出す
    private func fetchChunk(userIds: [String]) async {
        let queryItems = userIds.map { URLQueryItem(name: "id", value: $0) }

        do {
            let response: HelixUsersResponse = try await apiClient.get(
                url: Self.usersURL,
                queryItems: queryItems
            )
            // キャッシュ上限超過時は全消去してメモリ増大を防ぐ
            // fetchedUserIds も同時にクリアしないと上限超過後に再取得されなくなるため一緒にリセットする
            if profileImageUrls.count + response.data.count > Self.maxCacheEntries {
                profileImageUrls.removeAll()
                fetchedUserIds.removeAll()
            }
            for userData in response.data {
                // レスポンスを受信したユーザーはフェッチ済みとしてマーク（URL が nil でも再取得しない）
                fetchedUserIds.insert(userData.id)
                // profileImageUrl が nil（空文字列・不正URL）のユーザーはURLキャッシュに追加しない
                if let url = userData.profileImageUrl {
                    profileImageUrls[userData.id] = url
                }
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // 未ログイン時はサイレントスキップ
            #if DEBUG
            logger.debug("プロフィール画像取得スキップ: 未認証 userIds=\(userIds)")
            #endif
        } catch {
            // その他のエラーもサイレントスキップ（プロフィール画像は必須ではないため）
            #if DEBUG
            logger.debug("プロフィール画像取得失敗: \(error.localizedDescription) userIds=\(userIds)")
            #endif
        }
    }
}

// MARK: - Array チャンク分割ユーティリティ

private extension Array {
    /// 配列を指定サイズのチャンクに分割する
    ///
    /// - Parameter size: 1チャンクの最大要素数
    /// - Returns: 分割されたチャンクの配列
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
