// ModerationService.swift
// チャットモデレーションコマンドを Twitch Helix API 経由で実行するサービス
// ChatCommand enum を受け取り、対応する Helix API エンドポイントを呼び出す

import Foundation

// MARK: - プロトコル

/// モデレーションコマンドを実行するサービスプロトコル
///
/// テスト時にモックを注入できるよう actor 実装を抽象化する
protocol ModerationServiceProtocol: Sendable {
    /// ChatCommand を実行する
    ///
    /// - Parameters:
    ///   - command: 実行するモデレーションコマンド
    ///   - broadcasterId: 配信チャンネルのユーザー ID（PRIVMSG の room-id から取得）
    ///   - moderatorId: コマンドを実行するモデレーターのユーザー ID（authState.userId）
    /// - Throws: `HelixAPIError`（API エラー）、`URLError`（ネットワークエラー）
    func execute(command: ChatCommand, broadcasterId: String, moderatorId: String) async throws
}

// MARK: - 実装

/// Twitch Helix API を使ってモデレーションコマンドを実行する actor
///
/// 各コマンドに対応する Helix API エンドポイントを呼び出す。
/// ユーザー名が必要なコマンド（ban/timeout 等）は `GET /users` でユーザー ID を解決してから実行する。
actor ModerationService: ModerationServiceProtocol {

    // MARK: - Helix API エンドポイント

    // swiftlint:disable force_unwrapping
    /// リテラル文字列のため実行時クラッシュは発生しない
    private static let bansURL = URL(string: "https://api.twitch.tv/helix/moderation/bans")!
    private static let chatSettingsURL = URL(string: "https://api.twitch.tv/helix/chat/settings")!
    private static let chatMessagesURL = URL(string: "https://api.twitch.tv/helix/chat/messages")!
    private static let usersURL = URL(string: "https://api.twitch.tv/helix/users")!
    // swiftlint:enable force_unwrapping

    // MARK: - プロパティ

    private let apiClient: any HelixAPIClientProtocol

    // MARK: - 初期化

    /// ModerationService を初期化する
    ///
    /// - Parameter apiClient: Helix API クライアント
    init(apiClient: any HelixAPIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - ModerationServiceProtocol

    /// ChatCommand を Helix API 呼び出しにルーティングして実行する
    func execute(command: ChatCommand, broadcasterId: String, moderatorId: String) async throws {
        switch command {
        case .ban(let username, let reason):
            let userId = try await resolveUserId(login: username)
            try await executeBan(userId: userId, duration: nil, reason: reason, broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .timeout(let username, let duration, let reason):
            let userId = try await resolveUserId(login: username)
            try await executeBan(userId: userId, duration: duration, reason: reason, broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .unban(let username), .untimeout(let username):
            let userId = try await resolveUserId(login: username)
            try await executeUnban(userId: userId, broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .emoteOnly(let enabled):
            try await executePatchChatSettings(.emoteOnly(enabled), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .slow(let seconds):
            try await executePatchChatSettings(.slow(enabled: true, waitTime: seconds), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .slowOff:
            try await executePatchChatSettings(.slow(enabled: false, waitTime: nil), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .subscribers(let enabled):
            try await executePatchChatSettings(.subscribers(enabled), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .followers(let duration):
            try await executePatchChatSettings(.followers(enabled: true, duration: duration), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .followersOff:
            try await executePatchChatSettings(.followers(enabled: false, duration: nil), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .uniqueChat(let enabled):
            try await executePatchChatSettings(.uniqueChat(enabled), broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .clear:
            try await executeDeleteMessages(messageId: nil, broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .delete(let messageId):
            try await executeDeleteMessages(messageId: messageId, broadcasterId: broadcasterId, moderatorId: moderatorId)

        case .me, .plainText, .unknown:
            // ModerationService の対象外（ChatViewModel でルーティング済み）
            break
        }
    }

    // MARK: - プライベートヘルパー

    /// ユーザー名（ログイン名）からユーザー ID を解決する
    ///
    /// - Parameter login: Twitch ログイン名（英数字小文字）
    /// - Returns: Twitch ユーザー ID
    /// - Throws: `HelixAPIError.notFound` ユーザーが存在しない場合
    private func resolveUserId(login: String) async throws -> String {
        let response: HelixUsersResponse = try await apiClient.get(
            url: Self.usersURL,
            queryItems: [URLQueryItem(name: "login", value: login)]
        )
        guard let user = response.data.first else {
            throw HelixAPIError.notFound
        }
        return user.id
    }

    /// POST /moderation/bans を実行する（BAN またはタイムアウト）
    private func executeBan(userId: String, duration: Int?, reason: String?, broadcasterId: String, moderatorId: String) async throws {
        let body = HelixBanRequest(data: HelixBanData(userId: userId, duration: duration, reason: reason))
        try await apiClient.postNoContent(
            url: Self.bansURL,
            queryItems: [
                URLQueryItem(name: "broadcaster_id", value: broadcasterId),
                URLQueryItem(name: "moderator_id", value: moderatorId)
            ],
            body: body
        )
    }

    /// DELETE /moderation/bans を実行する（BAN または タイムアウト解除）
    private func executeUnban(userId: String, broadcasterId: String, moderatorId: String) async throws {
        try await apiClient.delete(
            url: Self.bansURL,
            queryItems: [
                URLQueryItem(name: "broadcaster_id", value: broadcasterId),
                URLQueryItem(name: "moderator_id", value: moderatorId),
                URLQueryItem(name: "user_id", value: userId)
            ]
        )
    }

    /// PATCH /chat/settings を実行する
    private func executePatchChatSettings(_ settings: HelixChatSettingsRequest, broadcasterId: String, moderatorId: String) async throws {
        try await apiClient.patch(
            url: Self.chatSettingsURL,
            queryItems: [
                URLQueryItem(name: "broadcaster_id", value: broadcasterId),
                URLQueryItem(name: "moderator_id", value: moderatorId)
            ],
            body: settings
        )
    }

    /// DELETE /chat/messages を実行する（全消去またはメッセージ指定削除）
    private func executeDeleteMessages(messageId: String?, broadcasterId: String, moderatorId: String) async throws {
        var queryItems = [
            URLQueryItem(name: "broadcaster_id", value: broadcasterId),
            URLQueryItem(name: "moderator_id", value: moderatorId)
        ]
        if let messageId {
            queryItems.append(URLQueryItem(name: "message_id", value: messageId))
        }
        try await apiClient.delete(url: Self.chatMessagesURL, queryItems: queryItems)
    }
}
