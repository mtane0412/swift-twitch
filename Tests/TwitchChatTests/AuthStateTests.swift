// AuthStateTests.swift
// AuthState の認証状態遷移テスト
// 外部 API 通信は MockTwitchAuthClient を使用する

import Testing
import AppKit
@testable import TwitchChat

@Suite("AuthState", .serialized)
@MainActor
struct AuthStateTests {

    // MARK: - 初期状態

    @Test("初期状態は .unknown である")
    func 初期状態はunknownである() {
        let authState = makeAuthState()
        #expect(authState.status == .unknown)
        #expect(authState.accessToken == nil)
    }

    // MARK: - restoreSession

    @Test("保存済みの有効なトークンがある場合はログイン状態に復元される")
    func 保存済みの有効なトークンがある場合はログイン状態に復元される() async throws {
        let store = makeTestKeychainStore()

        // アクセストークン・ユーザー情報を事前保存
        try await store.save(key: "access_token", value: "保存済みアクセストークン")
        try await store.save(key: "refresh_token", value: "保存済みリフレッシュトークン")
        try await store.save(key: "user_login", value: "テスト配信者")

        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "テスト配信者",
                userId: "12345678",
                scopes: ["chat:read", "chat:edit", "user:read:follows"],
                expiresIn: 10000
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)

        // セッション復元を実行
        await authState.restoreSession()

        // ログイン状態に復元されることを確認
        #expect(authState.status == .loggedIn(userLogin: "テスト配信者"))
        #expect(authState.accessToken == "保存済みアクセストークン")

        await store.deleteAll()
    }

    @Test("保存済みトークンが期限切れの場合はリフレッシュしてログイン状態に復元される")
    func 保存済みトークンが期限切れの場合はリフレッシュしてログイン状態に復元される() async throws {
        let store = makeTestKeychainStore()

        try await store.save(key: "access_token", value: "期限切れアクセストークン")
        try await store.save(key: "refresh_token", value: "有効なリフレッシュトークン")
        try await store.save(key: "user_login", value: "テスト配信者")

        // validateToken は最初の呼び出しで tokenExpired を返すモックを設定
        // refreshToken 後の validateToken は成功するよう別途設定する
        let mockClient = MockTwitchAuthClientWithFirstCallExpiry(
            refreshResponse: TwitchTokenResponse(
                accessToken: "新しいアクセストークン",
                refreshToken: "新しいリフレッシュトークン",
                expiresIn: 14400,
                tokenType: "bearer",
                scope: ["chat:read"]
            ),
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "テスト配信者",
                userId: "12345678",
                scopes: ["chat:read"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)

        // restoreSession: 保存済みトークンを検証 → 期限切れ → リフレッシュ → 新しいトークンで再検証
        await authState.restoreSession()

        // リフレッシュ成功によりログイン状態に復元されることを確認
        #expect(authState.status == AuthStatus.loggedIn(userLogin: "テスト配信者"))
        #expect(authState.accessToken == "新しいアクセストークン")

        // Keychain に新しいトークンが保存されることを確認
        #expect(await store.load(key: "access_token") == "新しいアクセストークン")
        #expect(await store.load(key: "refresh_token") == "新しいリフレッシュトークン")

        await store.deleteAll()
    }

    @Test("保存済みトークンがない場合はログアウト状態になる")
    func 保存済みトークンがない場合はログアウト状態になる() async {
        let store = makeTestKeychainStore()
        let mockClient = MockTwitchAuthClient()
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)

        await authState.restoreSession()

        #expect(authState.status == .loggedOut)
        #expect(authState.accessToken == nil)
    }

    // MARK: - login（Device Code Flow）

    @Test("ログインが成功するとログイン状態に遷移しトークンが保存される")
    func ログインが成功するとログイン状態に遷移しトークンが保存される() async throws {
        let store = makeTestKeychainStore()

        // デバイスコード → トークン → 検証 の順に成功するモックを設定
        let mockClient = MockTwitchAuthClient(
            deviceCodeResponse: TwitchDeviceCodeResponse(
                deviceCode: "テスト用デバイスコード",
                userCode: "ABC-12345",
                verificationUri: "https://www.twitch.tv/activate",
                expiresIn: 1800,
                interval: 0
            ),
            tokenResponse: TwitchTokenResponse(
                accessToken: "テスト用アクセストークン",
                refreshToken: "テスト用リフレッシュトークン",
                expiresIn: 14400,
                tokenType: "bearer",
                scope: ["chat:read"]
            ),
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "テスト配信者",
                userId: "12345678",
                scopes: ["chat:read"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)

        // login() を直接 await する（startLogin() のタスク管理なしで検証）
        await authState.login()

        // ログイン状態に遷移することを確認
        #expect(authState.status == .loggedIn(userLogin: "テスト配信者"))
        #expect(authState.accessToken == "テスト用アクセストークン")
        // Keychain にトークンが保存されることを確認
        #expect(await store.load(key: "access_token") == "テスト用アクセストークン")
        #expect(await store.load(key: "refresh_token") == "テスト用リフレッシュトークン")
        // deviceFlowInfo はログイン完了後にクリアされることを確認
        #expect(authState.deviceFlowInfo == nil)

        await store.deleteAll()
    }

    @Test("デバイスコード取得でエラーが発生した場合はログアウト状態になる")
    func デバイスコード取得でエラーが発生した場合はログアウト状態になる() async {
        // requestDeviceCode がネットワークエラーを返すケースをシミュレート
        let mockClient = MockTwitchAuthClient(errorToThrow: TwitchAuthError.networkError)
        let authState = makeAuthState(authClient: mockClient, keychainStore: makeTestKeychainStore())

        await authState.login()

        // エラー発生時はログアウト状態に遷移し、エラーメッセージが設定されることを確認
        #expect(authState.status == .loggedOut)
        #expect(authState.deviceFlowInfo == nil)
        #expect(authState.loginError != nil)
    }

    @Test("ユーザーが認証を拒否した場合はログアウト状態になる")
    func ユーザーが認証を拒否した場合はログアウト状態になる() async {
        // requestDeviceCode で access_denied 相当のエラーが返るケースをシミュレート
        let mockClient = MockTwitchAuthClient(errorToThrow: TwitchAuthError.userCancelled)
        let authState = makeAuthState(authClient: mockClient, keychainStore: makeTestKeychainStore())

        await authState.login()

        // ユーザー拒否時はログアウト状態に遷移し、エラーメッセージは設定されないことを確認
        #expect(authState.status == .loggedOut)
        #expect(authState.deviceFlowInfo == nil)
        #expect(authState.loginError == nil)
    }

    @Test("cancelDeviceFlow を呼ぶとログアウト状態に戻る")
    func cancelDeviceFlowを呼ぶとログアウト状態に戻る() async {
        let mockClient = MockTwitchAuthClient()
        let authState = makeAuthState(authClient: mockClient, keychainStore: makeTestKeychainStore())

        // cancelDeviceFlow を呼んでもクラッシュせず、ログアウト状態になることを確認
        authState.cancelDeviceFlow()

        #expect(authState.status == .loggedOut)
        #expect(authState.deviceFlowInfo == nil)
    }

    // MARK: - logout

    @Test("ログアウトするとトークンが削除されてログアウト状態になる")
    func ログアウトするとトークンが削除されてログアウト状態になる() async throws {
        let store = makeTestKeychainStore()

        try await store.save(key: "access_token", value: "ログアウト対象アクセストークン")
        try await store.save(key: "refresh_token", value: "ログアウト対象リフレッシュトークン")
        try await store.save(key: "user_login", value: "テスト配信者")

        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "テスト配信者",
                userId: "12345678",
                scopes: ["chat:read"],
                expiresIn: 10000
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)
        await authState.restoreSession()

        // ログアウト実行
        await authState.logout()

        // ログアウト状態に遷移し、Keychain からトークンが削除されることを確認
        #expect(authState.status == .loggedOut)
        #expect(authState.accessToken == nil)
        #expect(await store.load(key: "access_token") == nil)
        #expect(await store.load(key: "refresh_token") == nil)

        await store.deleteAll()
    }

    // MARK: - スコープ管理・canSendChat

    @Test("restoreSession 成功時に grantedScopes が保存される")
    func restoreSession成功時にgrantedScopesが保存される() async throws {
        let store = makeTestKeychainStore()
        try await store.save(key: "access_token", value: "テスト用トークン")

        // 前提: chat:read と chat:edit を含む validateResponse を返すモック
        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "配信者ユーザー",
                userId: "99999",
                scopes: ["chat:read", "chat:edit"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)
        await authState.restoreSession()

        // 検証: grantedScopes にスコープが保存される
        #expect(authState.grantedScopes.contains("chat:read"))
        #expect(authState.grantedScopes.contains("chat:edit"))
        // 検証: canSendChat が true になる
        #expect(authState.canSendChat == true)

        await store.deleteAll()
    }

    @Test("login 成功時に grantedScopes が保存される")
    func login成功時にgrantedScopesが保存される() async throws {
        let store = makeTestKeychainStore()

        let mockClient = MockTwitchAuthClient(
            deviceCodeResponse: TwitchDeviceCodeResponse(
                deviceCode: "テスト用デバイスコード",
                userCode: "XYZ-67890",
                verificationUri: "https://www.twitch.tv/activate",
                expiresIn: 1800,
                interval: 0
            ),
            tokenResponse: TwitchTokenResponse(
                accessToken: "テスト用ログイントークン",
                refreshToken: "テスト用リフレッシュトークン",
                expiresIn: 14400,
                tokenType: "bearer",
                scope: ["chat:read", "chat:edit"]
            ),
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "新規ログイン者",
                userId: "11111",
                scopes: ["chat:read", "chat:edit"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)
        await authState.login()

        // 検証: grantedScopes にスコープが保存される
        #expect(authState.grantedScopes.contains("chat:edit"))
        #expect(authState.canSendChat == true)

        await store.deleteAll()
    }

    @Test("chat:edit を含まないスコープの場合 canSendChat は false になる")
    func chatEditを含まないスコープの場合canSendChatはfalseになる() async throws {
        let store = makeTestKeychainStore()
        try await store.save(key: "access_token", value: "スコープ不足トークン")

        // 前提: chat:edit を含まない validateResponse
        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "旧バージョンユーザー",
                userId: "22222",
                scopes: ["chat:read"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)
        // restoreSession では chat:edit がない場合に自動ログアウト
        await authState.restoreSession()

        // 検証: 自動ログアウトされて canSendChat は false
        #expect(authState.canSendChat == false)
        #expect(authState.status == .loggedOut)

        await store.deleteAll()
    }

    @Test("restoreSession で chat:edit がない場合は自動ログアウトされる")
    func restoreSessionでchatEditがない場合は自動ログアウトされる() async throws {
        let store = makeTestKeychainStore()
        try await store.save(key: "access_token", value: "スコープ不足のトークン")

        // 前提: chat:edit を含まない validateResponse（旧スコープのトークン）
        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "testclientid",
                login: "既存ユーザー",
                userId: "33333",
                scopes: ["chat:read", "user:read:follows"],
                expiresIn: 14400
            )
        )
        let authState = makeAuthState(authClient: mockClient, keychainStore: store)
        await authState.restoreSession()

        // 検証: chat:edit がないため自動ログアウト
        #expect(authState.status == .loggedOut)
        #expect(authState.accessToken == nil)

        await store.deleteAll()
    }

    // MARK: - ヘルパー

    private func makeAuthState(
        authClient: (any TwitchAuthClientProtocol)? = nil,
        keychainStore: KeychainStore? = nil
    ) -> AuthState {
        // openURL に no-op を渡し、テスト中に実際のブラウザが開かないようにする
        AuthState(
            authClient: authClient ?? MockTwitchAuthClient(),
            keychainStore: keychainStore ?? makeTestKeychainStore(),
            openURL: { _ in }
        )
    }

    private func makeTestKeychainStore() -> KeychainStore {
        // テストごとに一意のサービス名を使用して干渉を防ぐ
        KeychainStore(service: "com.test.AuthState.\(UUID().uuidString)")
    }
}
