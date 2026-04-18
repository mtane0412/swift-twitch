// MentionStore.swift
// @メンション補完用のユーザー名リストを管理するサービス
// 受信メッセージからユーザーを記録し、クエリによるフィルタリングを提供する

import Observation

/// @メンション補完用ユーザー名リスト管理サービス
///
/// - `recordUser(username:displayName:)` でメッセージ受信のたびにユーザーを記録する
/// - 同一ユーザーは重複排除し、最新発言者が先頭に来る順序で管理する
/// - `candidates(matching:)` で前方一致フィルタリングした候補一覧を取得する
/// - メモリ使用量を抑えるため最大 `maxMentionsCount` 件のみ保持する
@Observable
@MainActor
final class MentionStore {

    // MARK: - 型定義

    /// ユーザー候補の一件分
    struct UserCandidate: Identifiable {
        /// SwiftUI リスト用の安定識別子（username を使用）
        var id: String { username }
        /// IRC ログイン名（小文字）
        let username: String
        /// 表示名（大文字・日本語を含む場合あり）
        let displayName: String
    }

    // MARK: - 定数

    /// ユーザー名リストの最大保持件数
    ///
    /// メモリ肥大化を防ぐため、超過分は最も古い発言者から削除する。
    static let maxMentionsCount = 200

    // MARK: - プライベートプロパティ

    /// 最新発言順のユーザー名リスト（先頭が最新）
    private var orderedUsernames: [String] = []

    /// O(1) 重複チェック用の Set
    private var usernameSet: Set<String> = []

    /// username → displayName のマッピング
    private var displayNames: [String: String] = [:]

    // MARK: - パブリックメソッド

    /// ユーザーを記録する
    ///
    /// 同一 username が既に存在する場合は先頭に移動する。
    /// `maxMentionsCount` を超えた場合は末尾（最も古い発言者）を削除する。
    ///
    /// - Parameters:
    ///   - username: IRC ログイン名（小文字）
    ///   - displayName: 表示名
    func recordUser(username: String, displayName: String) {
        // 既存エントリの削除（O(1) で存在確認してから O(n) で除去）
        if usernameSet.contains(username) {
            orderedUsernames.removeAll { $0 == username }
        } else {
            usernameSet.insert(username)
        }

        // 先頭に追加（最新発言順を維持）
        orderedUsernames.insert(username, at: 0)
        displayNames[username] = displayName

        // 上限超過分を末尾から削除
        while orderedUsernames.count > Self.maxMentionsCount {
            let old = orderedUsernames.removeLast()
            usernameSet.remove(old)
            displayNames.removeValue(forKey: old)
        }
    }

    /// クエリに前方一致するユーザー候補を返す
    ///
    /// username または displayName の先頭がクエリと一致するユーザーを最新発言順で返す。
    /// クエリが空の場合は全件を返す。大文字小文字は区別しない。
    ///
    /// - Parameter query: フィルタリング文字列（前方一致）
    /// - Returns: マッチしたユーザー候補の配列（最新発言順）
    func candidates(matching query: String) -> [UserCandidate] {
        orderedUsernames
            .compactMap { username -> UserCandidate? in
                guard let displayName = displayNames[username] else { return nil }
                return UserCandidate(username: username, displayName: displayName)
            }
            .filter { candidate in
                guard !query.isEmpty else { return true }
                // 前方一致（大文字小文字非区別）
                let usernameMatch = candidate.username.range(
                    of: query, options: [.caseInsensitive, .anchored]
                ) != nil
                let displayNameMatch = candidate.displayName.range(
                    of: query, options: [.caseInsensitive, .anchored]
                ) != nil
                return usernameMatch || displayNameMatch
            }
    }
}
