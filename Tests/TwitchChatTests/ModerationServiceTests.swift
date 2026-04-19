// ModerationServiceTests.swift
// ModerationService の単体テスト
// MockHelixAPIClient を使ってネットワーク通信なしでモデレーション API 呼び出しを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// ModerationService テスト専用の HelixAPIClientProtocol モック
///
/// GET /users のユーザー解決と POST/PATCH/DELETE の呼び出し記録に対応する
actor MockModerationAPIClient: HelixAPIClientProtocol {
    // MARK: - スタブ設定

    /// GET /users?login= に返すユーザーデータ（ログイン名 → ユーザーID のマップ）
    var usersByLogin: [String: HelixUserData] = [:]

    /// true の場合、全呼び出しで .unauthorized を throw する
    var shouldThrowUnauthorized: Bool = false

    /// true の場合、全呼び出しで .forbidden を throw する
    var shouldThrowForbidden: Bool = false

    // MARK: - 呼び出し記録

    /// postNoContent が呼ばれた回数
    private(set) var postNoContentCallCount = 0
    /// patch が呼ばれた回数
    private(set) var patchCallCount = 0
    /// delete が呼ばれた回数
    private(set) var deleteCallCount = 0

    /// 最後に postNoContent に渡された URL
    private(set) var lastPostNoContentURL: URL?
    /// 最後に postNoContent に渡されたクエリパラメータ
    private(set) var lastPostNoContentQueryItems: [URLQueryItem]?
    /// 最後に postNoContent に渡されたリクエストボディ（HelixBanRequest）
    private(set) var lastPostNoContentBody: HelixBanRequest?

    /// 最後に patch に渡された URL
    private(set) var lastPatchURL: URL?
    /// 最後に patch に渡されたクエリパラメータ
    private(set) var lastPatchQueryItems: [URLQueryItem]?
    /// 最後に patch に渡されたボディ（HelixChatSettingsRequest）
    private(set) var lastPatchBody: HelixChatSettingsRequest?

    /// 最後に delete に渡された URL
    private(set) var lastDeleteURL: URL?
    /// 最後に delete に渡されたクエリパラメータ
    private(set) var lastDeleteQueryItems: [URLQueryItem]?

    // MARK: - HelixAPIClientProtocol 実装

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        if shouldThrowUnauthorized { throw HelixAPIError.unauthorized }
        if shouldThrowForbidden { throw HelixAPIError.forbidden("テスト用権限エラー") }

        // GET /users のシミュレート
        if T.self == HelixUsersResponse.self {
            let requestedLogins = queryItems?.filter { $0.name == "login" }.compactMap { $0.value } ?? []
            let matched = requestedLogins.compactMap { usersByLogin[$0] }
            let response = HelixUsersResponse(data: matched)
            return response as! T  // swiftlint:disable:this force_cast
        }
        throw URLError(.badServerResponse)
    }

    func post<Body: Encodable & Sendable, T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws -> T {
        if shouldThrowUnauthorized { throw HelixAPIError.unauthorized }
        if shouldThrowForbidden { throw HelixAPIError.forbidden("テスト用権限エラー") }
        throw URLError(.badServerResponse)
    }

    func postNoContent<Body: Encodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws {
        if shouldThrowUnauthorized { throw HelixAPIError.unauthorized }
        if shouldThrowForbidden { throw HelixAPIError.forbidden("テスト用権限エラー") }
        postNoContentCallCount += 1
        lastPostNoContentURL = url
        lastPostNoContentQueryItems = queryItems
        // HelixBanRequest にキャストしてボディを記録する
        if let banRequest = body as? HelixBanRequest {
            lastPostNoContentBody = banRequest
        }
    }

    func patch<Body: Encodable & Sendable>(url: URL, queryItems: [URLQueryItem]?, body: Body) async throws {
        if shouldThrowUnauthorized { throw HelixAPIError.unauthorized }
        if shouldThrowForbidden { throw HelixAPIError.forbidden("テスト用権限エラー") }
        patchCallCount += 1
        lastPatchURL = url
        lastPatchQueryItems = queryItems
        // HelixChatSettingsRequest にキャストして記録する
        if let settings = body as? HelixChatSettingsRequest {
            lastPatchBody = settings
        } else {
            Issue.record("patch に予期しない型が渡されました: \(type(of: body))")
        }
    }

    func delete(url: URL, queryItems: [URLQueryItem]?) async throws {
        if shouldThrowUnauthorized { throw HelixAPIError.unauthorized }
        if shouldThrowForbidden { throw HelixAPIError.forbidden("テスト用権限エラー") }
        deleteCallCount += 1
        lastDeleteURL = url
        lastDeleteQueryItems = queryItems
    }

    // MARK: - ヘルパー

    func addUser(id: String, login: String) {
        usersByLogin[login] = HelixUserData(id: id, login: login, displayName: login, profileImageUrl: nil)
    }

    func setUnauthorized(_ value: Bool) {
        shouldThrowUnauthorized = value
    }
}

// MARK: - テスト本体

@Suite("ModerationServiceTests")
struct ModerationServiceTests {

    /// テスト共通設定
    let broadcasterID = "配信者ID_001"
    let moderatorID = "モデレーターID_002"

    // MARK: - /ban コマンド

    @Test("/ban コマンドが POST /moderation/bans を呼び出すこと")
    func testBanCallsPostBans() async throws {
        let mock = MockModerationAPIClient()
        await mock.addUser(id: "ユーザーID_001", login: "あらし太郎")
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .ban(username: "あらし太郎", reason: "荒らし行為"),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let callCount = await mock.postNoContentCallCount
        #expect(callCount == 1)

        let url = await mock.lastPostNoContentURL
        #expect(url?.absoluteString.contains("/moderation/bans") == true)

        let queryItems = await mock.lastPostNoContentQueryItems
        #expect(queryItems?.contains(URLQueryItem(name: "broadcaster_id", value: broadcasterID)) == true)
        #expect(queryItems?.contains(URLQueryItem(name: "moderator_id", value: moderatorID)) == true)
    }

    @Test("/ban コマンドで存在しないユーザーは notFound エラーになること")
    func testBanWithNonExistentUser() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        await #expect(throws: HelixAPIError.notFound) {
            try await service.execute(
                command: .ban(username: "存在しないユーザー", reason: nil),
                broadcasterId: broadcasterID,
                moderatorId: moderatorID
            )
        }
    }

    // MARK: - /timeout コマンド

    @Test("/timeout コマンドが POST /moderation/bans を呼び出すこと")
    func testTimeoutCallsPostBans() async throws {
        let mock = MockModerationAPIClient()
        await mock.addUser(id: "ユーザーID_001", login: "スパマー")
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .timeout(username: "スパマー", duration: 600, reason: "スパム行為"),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let callCount = await mock.postNoContentCallCount
        #expect(callCount == 1)

        let url = await mock.lastPostNoContentURL
        #expect(url?.absoluteString.contains("/moderation/bans") == true)
    }

    // MARK: - /unban コマンド

    @Test("/unban コマンドが DELETE /moderation/bans を呼び出すこと")
    func testUnbanCallsDeleteBans() async throws {
        let mock = MockModerationAPIClient()
        await mock.addUser(id: "ユーザーID_001", login: "解除ユーザー")
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .unban(username: "解除ユーザー"),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let callCount = await mock.deleteCallCount
        #expect(callCount == 1)

        let url = await mock.lastDeleteURL
        #expect(url?.absoluteString.contains("/moderation/bans") == true)

        let queryItems = await mock.lastDeleteQueryItems
        #expect(queryItems?.contains(URLQueryItem(name: "user_id", value: "ユーザーID_001")) == true)
    }

    // MARK: - /emoteonly コマンド

    @Test("/emoteonly コマンドが PATCH /chat/settings を呼び出すこと")
    func testEmoteOnlyCallsPatchChatSettings() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .emoteOnly(enabled: true),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let callCount = await mock.patchCallCount
        #expect(callCount == 1)

        let url = await mock.lastPatchURL
        #expect(url?.absoluteString.contains("/chat/settings") == true)

        let body = await mock.lastPatchBody
        #expect(body?.emoteMode == true)
    }

    @Test("/emoteonlyoff コマンドが emote_mode: false で PATCH を呼び出すこと")
    func testEmoteOnlyOffCallsPatchChatSettings() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .emoteOnly(enabled: false),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let body = await mock.lastPatchBody
        #expect(body?.emoteMode == false)
    }

    // MARK: - /slow コマンド

    @Test("/slow コマンドが PATCH /chat/settings を呼び出すこと")
    func testSlowCallsPatchChatSettings() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .slow(seconds: 30),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let body = await mock.lastPatchBody
        #expect(body?.slowMode == true)
        #expect(body?.slowModeWaitTime == 30)
    }

    @Test("/slowoff コマンドが slow_mode: false で PATCH を呼び出すこと")
    func testSlowOffCallsPatchChatSettings() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .slowOff,
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let body = await mock.lastPatchBody
        #expect(body?.slowMode == false)
    }

    // MARK: - /clear コマンド

    @Test("/clear コマンドが DELETE /chat/messages を呼び出すこと")
    func testClearCallsDeleteMessages() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .clear,
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let callCount = await mock.deleteCallCount
        #expect(callCount == 1)

        let url = await mock.lastDeleteURL
        #expect(url?.absoluteString.contains("/chat/messages") == true)

        // message_id クエリパラメータが含まれないこと（全消去の場合）
        let queryItems = await mock.lastDeleteQueryItems
        #expect(queryItems?.contains(where: { $0.name == "message_id" }) == false)
    }

    // MARK: - /delete コマンド

    @Test("/delete コマンドが message_id 付きで DELETE /chat/messages を呼び出すこと")
    func testDeleteCallsDeleteMessagesWithId() async throws {
        let mock = MockModerationAPIClient()
        let service = ModerationService(apiClient: mock)

        try await service.execute(
            command: .delete(messageId: "メッセージID_abc123"),
            broadcasterId: broadcasterID,
            moderatorId: moderatorID
        )

        let queryItems = await mock.lastDeleteQueryItems
        #expect(queryItems?.contains(URLQueryItem(name: "message_id", value: "メッセージID_abc123")) == true)
    }

    // MARK: - エラー伝播

    @Test("API が unauthorized エラーを返した場合は HelixAPIError.unauthorized が throw されること")
    func testUnauthorizedErrorPropagates() async throws {
        let mock = MockModerationAPIClient()
        // shouldThrowUnauthorized = true にすると get メソッドも含む全呼び出しで throw するため、
        // addUser で登録したユーザーを解決する前に unauthorized が伝播することを検証する
        await mock.setUnauthorized(true)
        await mock.addUser(id: "ID", login: "ユーザー")
        let service = ModerationService(apiClient: mock)

        await #expect(throws: HelixAPIError.unauthorized) {
            try await service.execute(
                command: .ban(username: "ユーザー", reason: nil),
                broadcasterId: broadcasterID,
                moderatorId: moderatorID
            )
        }
    }
}
