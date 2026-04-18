// MentionStore.swift
// @メンション補完用のユーザー名リストを管理するサービス
// 受信メッセージからユーザーを記録し、クエリによるフィルタリングを提供する

import Observation

/// @メンション補完用ユーザー名リスト管理サービス
///
/// - `recordUser(username:displayName:)` でメッセージ受信のたびにユーザーを記録する
/// - 同一ユーザーは重複排除し、最新発言者が先頭に来る順序で管理する
/// - `candidates(matching:)` で前方一致フィルタリングした候補一覧を取得する
@Observable
@MainActor
final class MentionStore {

    // MARK: - 型定義

    /// ユーザー候補の一件分
    struct UserCandidate {
        /// IRC ログイン名（小文字）
        let username: String
        /// 表示名（大文字・日本語を含む場合あり）
        let displayName: String
    }

    // MARK: - プライベートプロパティ

    /// 最新発言順のユーザー名リスト（先頭が最新）
    private var orderedUsernames: [String] = []

    /// username → displayName のマッピング
    private var displayNames: [String: String] = [:]

    // MARK: - パブリックメソッド

    /// ユーザーを記録する
    ///
    /// 同一 username が既に存在する場合は先頭に移動する。
    ///
    /// - Parameters:
    ///   - username: IRC ログイン名（小文字）
    ///   - displayName: 表示名
    func recordUser(username: String, displayName: String) {
        // 既存のエントリを削除して先頭に追加（最新発言順を維持）
        orderedUsernames.removeAll { $0 == username }
        orderedUsernames.insert(username, at: 0)
        displayNames[username] = displayName
    }

    /// クエリに前方一致するユーザー候補を返す
    ///
    /// username または displayName の先頭がクエリに一致するユーザーを最新発言順で返す。
    /// クエリが空の場合は全件を返す。大文字小文字は区別しない。
    ///
    /// - Parameter query: フィルタリング文字列
    /// - Returns: マッチしたユーザー候補の配列（最新発言順）
    func candidates(matching query: String) -> [UserCandidate] {
        orderedUsernames
            .compactMap { username -> UserCandidate? in
                guard let displayName = displayNames[username] else { return nil }
                return UserCandidate(username: username, displayName: displayName)
            }
            .filter { candidate in
                guard !query.isEmpty else { return true }
                return candidate.username.localizedCaseInsensitiveContains(query)
                    || candidate.displayName.localizedCaseInsensitiveContains(query)
            }
    }
}
