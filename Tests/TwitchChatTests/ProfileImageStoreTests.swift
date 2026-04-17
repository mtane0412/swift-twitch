// ProfileImageStoreTests.swift
// ProfileImageStore の単体テスト
// MockHelixAPIClient を使ってネットワーク通信なしでストア振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// HelixUsersResponse を返す Helix API クライアントモック
actor MockProfileImageAPIClient: HelixAPIClientProtocol {
    /// 返すユーザーデータ
    var usersToReturn: [HelixUserData] = []
    /// true の場合、URLError.userAuthenticationRequired を throw する
    var shouldThrowAuthError: Bool = false
    /// get() が呼ばれた回数（呼び出し検証用）
    private(set) var callCount = 0
    /// 最後に渡されたクエリパラメータ
    private(set) var lastQueryItems: [URLQueryItem]?

    func get<T: Decodable & Sendable>(url: URL, queryItems: [URLQueryItem]?) async throws -> T {
        callCount += 1
        lastQueryItems = queryItems
        if shouldThrowAuthError {
            throw URLError(.userAuthenticationRequired)
        }
        if T.self == HelixUsersResponse.self {
            // id または login でマッチするユーザーを返す（実際の API の挙動を再現）
            let requestedIds = queryItems?.filter { $0.name == "id" }.compactMap { $0.value } ?? []
            let requestedLogins = queryItems?.filter { $0.name == "login" }.compactMap { $0.value } ?? []
            let filtered = usersToReturn.filter {
                requestedIds.contains($0.id) || requestedLogins.contains($0.login)
            }
            let response = HelixUsersResponse(data: filtered)
            return response as! T  // swiftlint:disable:this force_cast
        }
        throw URLError(.badServerResponse)
    }

    func setUsers(_ users: [HelixUserData]) {
        usersToReturn = users
    }

    func setAuthError(_ value: Bool) {
        shouldThrowAuthError = value
    }
}

// MARK: - テストデータファクトリ

/// テスト用ユーザーデータを生成する
private func makeHelixUser(
    id: String = "111111",
    login: String = "テスト配信者",
    displayName: String = "テスト配信者の表示名",
    profileImageUrl: URL? = URL(string: "https://example.com/profile.png")
) -> HelixUserData {
    HelixUserData(
        id: id,
        login: login,
        displayName: displayName,
        profileImageUrl: profileImageUrl
    )
}

// MARK: - テスト

@Suite("ProfileImageStore テスト")
@MainActor
struct ProfileImageStoreTests {

    // MARK: - 初期状態

    @Test("初期状態はユーザー情報が空")
    func testInitialState() {
        let mockClient = MockProfileImageAPIClient()
        let store = ProfileImageStore(apiClient: mockClient)

        #expect(store.profileImageUrl(for: "999999") == nil)
    }

    // MARK: - ユーザー取得

    @Test("ユーザーIDを指定してプロフィール画像URLを取得できる")
    func testFetchProfileImageUrls() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", profileImageUrl: URL(string: "https://example.com/user1.png")),
            makeHelixUser(id: "222222", profileImageUrl: URL(string: "https://example.com/user2.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(userIds: ["111111", "222222"])

        #expect(store.profileImageUrl(for: "111111") == URL(string: "https://example.com/user1.png"))
        #expect(store.profileImageUrl(for: "222222") == URL(string: "https://example.com/user2.png"))
    }

    @Test("ユーザーIDが空の場合は API を呼ばない")
    func testFetchSkipsWhenEmptyUserIds() async {
        let mockClient = MockProfileImageAPIClient()
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(userIds: [])

        let callCount = await mockClient.callCount
        #expect(callCount == 0)
    }

    @Test("認証エラーの場合はサイレントスキップする")
    func testFetchSilentlySkipsOnAuthError() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setAuthError(true)
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(userIds: ["111111"])

        // エラーがスローされずプロフィール画像URLも nil のまま
        #expect(store.profileImageUrl(for: "111111") == nil)
    }

    @Test("既に取得済みのユーザーは再取得しない")
    func testDoesNotRefetchExistingUsers() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", profileImageUrl: URL(string: "https://example.com/user1.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // 1回目のフェッチ
        await store.fetchUsers(userIds: ["111111"])
        // 2回目は同じユーザーID（再取得不要）
        await store.fetchUsers(userIds: ["111111"])

        // API は1回しか呼ばれていないこと
        let callCount = await mockClient.callCount
        #expect(callCount == 1)
    }

    @Test("プロフィール画像URLが nil のユーザーは再取得しない")
    func testDoesNotRefetchUsersWithNilProfileImageUrl() async {
        let mockClient = MockProfileImageAPIClient()
        // profileImageUrl が nil（空URL）のユーザーを返す
        await mockClient.setUsers([
            makeHelixUser(id: "111111", profileImageUrl: nil)
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // 1回目: APIレスポンスを受信（URL は nil）
        await store.fetchUsers(userIds: ["111111"])
        // 2回目: 同じユーザーID（フェッチ済みのため再取得しない）
        await store.fetchUsers(userIds: ["111111"])

        // API は1回しか呼ばれていないこと
        let callCount = await mockClient.callCount
        #expect(callCount == 1)
        // profileImageUrl は nil のまま
        #expect(store.profileImageUrl(for: "111111") == nil)
    }

    @Test("未取得のユーザーのみ API を呼ぶ")
    func testFetchesOnlyNewUsers() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", profileImageUrl: URL(string: "https://example.com/user1.png")),
            makeHelixUser(id: "333333", profileImageUrl: URL(string: "https://example.com/user3.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // 1回目: 111111 を取得
        await store.fetchUsers(userIds: ["111111"])
        // 2回目: 111111（取得済み）+ 333333（未取得）
        await store.fetchUsers(userIds: ["111111", "333333"])

        // API は2回呼ばれているが、2回目のリクエストには 111111 が含まれないこと
        let callCount = await mockClient.callCount
        #expect(callCount == 2)
        let lastQueryItems = await mockClient.lastQueryItems
        // URLQueryItem.value は String? のため compactMap で nil を除外する
        let requestedIds = lastQueryItems?.filter { $0.name == "id" }.compactMap { $0.value } ?? []
        #expect(!requestedIds.contains("111111"))
        #expect(requestedIds.contains("333333"))
    }

    @Test("ストアをクリアするとユーザー情報がリセットされる")
    func testClearResetsUsers() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", profileImageUrl: URL(string: "https://example.com/user1.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(userIds: ["111111"])
        #expect(store.profileImageUrl(for: "111111") != nil)

        store.clear()

        #expect(store.profileImageUrl(for: "111111") == nil)
    }

    // MARK: - ログイン名による参照（loginToUserId マッピング）

    @Test("fetchUsers(userIds:) 後に profileImageUrl(forLogin:) でURLを取得できる")
    func testProfileImageUrlByLoginAfterUserIdFetch() async {
        // fetchUsers(userIds:) のレスポンスには login も含まれるため loginToUserId が更新される
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "よしおっくす", profileImageUrl: URL(string: "https://example.com/yoshi.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // userId でフェッチ（実際には ChannelSearchView が searchResults の id で呼ぶケース）
        await store.fetchUsers(userIds: ["111111"])

        // ログイン名でも URL が取得できること
        #expect(store.profileImageUrl(forLogin: "よしおっくす") == URL(string: "https://example.com/yoshi.png"))
    }

    @Test("fetchUsers(userIds:) 後に userId(forLogin:) でユーザーIDを取得できる")
    func testUserIdByLoginAfterUserIdFetch() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "よしおっくす")
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(userIds: ["111111"])

        #expect(store.userId(forLogin: "よしおっくす") == "111111")
    }

    @Test("未フェッチのログイン名に対して profileImageUrl(forLogin:) は nil を返す")
    func testProfileImageUrlByLoginReturnsNilWhenNotFetched() {
        let mockClient = MockProfileImageAPIClient()
        let store = ProfileImageStore(apiClient: mockClient)

        #expect(store.profileImageUrl(forLogin: "unknownchannel") == nil)
    }

    // MARK: - ログイン名によるフェッチ

    @Test("fetchUsers(logins:) でログイン名から画像URLを取得できる")
    func testFetchUsersByLogin() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "yoshiox", profileImageUrl: URL(string: "https://example.com/yoshi.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // ログイン名でフェッチ
        await store.fetchUsers(logins: ["yoshiox"])

        // ログイン名・ユーザーID の両方でURLが取得できること
        #expect(store.profileImageUrl(forLogin: "yoshiox") == URL(string: "https://example.com/yoshi.png"))
        #expect(store.userId(forLogin: "yoshiox") == "111111")
        #expect(store.profileImageUrl(for: "111111") == URL(string: "https://example.com/yoshi.png"))
    }

    @Test("fetchUsers(logins:) は login クエリパラメータで API を呼ぶ")
    func testFetchUsersByLoginUsesLoginQueryParam() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "yoshiox")
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(logins: ["yoshiox"])

        // クエリパラメータが "login" であること（"id" ではない）
        let lastQueryItems = await mockClient.lastQueryItems
        let loginParams = lastQueryItems?.filter { $0.name == "login" }.compactMap { $0.value } ?? []
        #expect(loginParams.contains("yoshiox"))
        let idParams = lastQueryItems?.filter { $0.name == "id" }.compactMap { $0.value } ?? []
        #expect(idParams.isEmpty)
    }

    @Test("fetchUsers(logins:) は既にフェッチ済みのログインを再取得しない")
    func testFetchUsersByLoginDoesNotRefetch() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "yoshiox")
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        // 1回目のフェッチ
        await store.fetchUsers(logins: ["yoshiox"])
        // 2回目は同じログイン（再取得不要）
        await store.fetchUsers(logins: ["yoshiox"])

        let callCount = await mockClient.callCount
        #expect(callCount == 1)
    }

    @Test("ストアをクリアすると loginToUserId マッピングもリセットされる")
    func testClearResetsLoginToUserIdMapping() async {
        let mockClient = MockProfileImageAPIClient()
        await mockClient.setUsers([
            makeHelixUser(id: "111111", login: "yoshiox", profileImageUrl: URL(string: "https://example.com/yoshi.png"))
        ])
        let store = ProfileImageStore(apiClient: mockClient)

        await store.fetchUsers(logins: ["yoshiox"])
        #expect(store.profileImageUrl(forLogin: "yoshiox") != nil)

        store.clear()

        // クリア後はログインマッピングもリセットされること
        #expect(store.profileImageUrl(forLogin: "yoshiox") == nil)
        #expect(store.userId(forLogin: "yoshiox") == nil)
    }
}
