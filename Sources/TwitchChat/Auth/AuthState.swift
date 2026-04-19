// AuthState.swift
// 認証状態を管理する Observable クラス
// アプリ全体で共有し、ログイン/ログアウト・トークン自動更新を提供する

import AppKit
import Foundation
import Observation

// MARK: - 認証状態 enum

/// 認証状態
public enum AuthStatus: Equatable {
    /// アプリ起動直後（保存済みトークン確認中）
    case unknown
    /// ログアウト状態
    case loggedOut
    /// ログイン済み
    case loggedIn(userLogin: String)
}

// MARK: - Device Flow 情報

/// Device Code Flow の認証中情報（UI 表示用）
struct DeviceFlowInfo: Sendable {
    /// ユーザーが twitch.tv/activate で入力するコード
    let userCode: String
    /// ユーザーが開く認証ページ URL
    let verificationUri: String
}

// MARK: - AuthState クラス

/// 認証状態を管理する Observable クラス
///
/// - アプリ起動時に Keychain から保存済みトークンを読み込みセッションを復元する
/// - ログイン: Device Code Flow を使用して外部ブラウザで認証する
/// - ログアウト: トークンを失効させ Keychain から削除する
/// - トークン自動リフレッシュ: `validAccessToken()` で期限切れを検出したら自動更新する
@Observable
@MainActor
public final class AuthState {

    // MARK: - パブリックプロパティ

    /// 現在の認証状態
    private(set) var status: AuthStatus = .unknown

    /// 現在のアクセストークン（ログアウト中は `nil`）
    private(set) var accessToken: String?

    /// 現在のユーザーID（ログアウト中は `nil`）
    private(set) var userId: String?

    /// Device Code Flow 中の認証情報（認証中のみ非 nil）
    private(set) var deviceFlowInfo: DeviceFlowInfo?

    /// 直近のログインエラーメッセージ（UI 表示用、成功時は `nil` にリセット）
    private(set) var loginError: String?

    /// 現在のアクセストークンに付与されているスコープ一覧
    ///
    /// `validateToken` レスポンスの `scopes` フィールドを保存する。
    /// ログアウト時は空配列にリセットされる
    private(set) var grantedScopes: [String] = []

    /// コメント投稿（PRIVMSG 送信）に必要な `chat:edit` スコープを保有しているか
    ///
    /// `false` の場合、送信 UI は無効化され再ログインを促す
    var canSendChat: Bool { grantedScopes.contains("chat:edit") }

    /// バン・タイムアウト操作に必要な `moderator:manage:banned_users` スコープを保有しているか
    var canModerate: Bool { grantedScopes.contains("moderator:manage:banned_users") }

    /// エモートオンリー・スロー・サブスクライバーモード等の設定に必要なスコープを保有しているか
    var canManageChatSettings: Bool { grantedScopes.contains("moderator:manage:chat_settings") }

    /// チャットクリア・メッセージ削除に必要なスコープを保有しているか
    var canManageChatMessages: Bool { grantedScopes.contains("moderator:manage:chat_messages") }

    /// ユーザーが使用可能なエモート取得に必要な `user:read:emotes` スコープを保有しているか
    ///
    /// `false` の場合、`/helix/chat/emotes/user` の呼び出しをスキップする（graceful degradation）。
    /// 旧トークンユーザーは再ログイン後にスコープが付与される。
    var canReadUserEmotes: Bool { grantedScopes.contains("user:read:emotes") }

    // MARK: - プライベートプロパティ

    private let authClient: any TwitchAuthClientProtocol
    private let keychainStore: KeychainStore
    /// ブラウザで URL を開く処理（テスト時は no-op を注入して実際のブラウザ起動を抑制する）
    private let openURL: @Sendable (URL) -> Void

    /// 進行中のログインタスク（cancelDeviceFlow() でキャンセルするために保持）
    private var loginTask: Task<Void, Never>?

    // MARK: - 初期化

    /// AuthState を初期化する
    ///
    /// - Parameters:
    ///   - authClient: OAuth クライアント（テスト時はモックを注入）
    ///   - keychainStore: Keychain ストア（テスト時は別サービス名のものを注入）
    ///   - openURL: ブラウザで URL を開く処理（テスト時は no-op を注入）
    init(
        authClient: any TwitchAuthClientProtocol = TwitchAuthClient(),
        keychainStore: KeychainStore = KeychainStore(),
        openURL: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.authClient = authClient
        self.keychainStore = keychainStore
        self.openURL = openURL
    }

    // MARK: - パブリックメソッド

    /// アプリ起動時に保存済みトークンを検証して認証状態を復元する
    ///
    /// - 保存済みトークンがなければ `.loggedOut` に遷移
    /// - トークンが有効であれば `.loggedIn` に遷移
    /// - トークンが期限切れであればリフレッシュを試み、成功すれば `.loggedIn`、失敗すれば `.loggedOut`
    func restoreSession() async {
        #if DEBUG
        print("[AuthState] restoreSession: Keychain からトークンを読み込み中...")
        #endif
        guard let savedToken = await keychainStore.load(key: "access_token") else {
            #if DEBUG
            print("[AuthState] restoreSession: access_token が見つからないため .loggedOut に遷移")
            #endif
            status = .loggedOut
            return
        }
        #if DEBUG
        print("[AuthState] restoreSession: access_token を取得。validateToken を実行中...")
        #endif

        do {
            let validateResponse = try await authClient.validateToken(accessToken: savedToken)
            #if DEBUG
            print("[AuthState] restoreSession: validateToken 成功 — login=\(validateResponse.login)")
            #endif

            // 必須スコープが不足している場合は自動ログアウトして再ログインを促す
            let scopes = validateResponse.scopes
            let missingScopes = missingRequiredChatScopes(in: scopes)
            if !missingScopes.isEmpty {
                #if DEBUG
                print("[AuthState] restoreSession: 必須スコープ不足 \(missingScopes) — 自動ログアウトして再ログインを要求")
                #endif
                await logout()
                return
            }

            grantedScopes = scopes
            accessToken = savedToken
            // validateResponse.userId を優先して設定し、未保存なら Keychain にも保存する
            userId = validateResponse.userId
            let savedUserId = await keychainStore.load(key: "user_id")
            if savedUserId == nil {
                try? await keychainStore.save(key: "user_id", value: validateResponse.userId)
            }
            status = .loggedIn(userLogin: validateResponse.login)
        } catch TwitchAuthError.tokenExpired {
            #if DEBUG
            print("[AuthState] restoreSession: トークン期限切れ。リフレッシュを試みる...")
            #endif
            await tryRefreshToken()
        } catch {
            #if DEBUG
            print("[AuthState] restoreSession: validateToken 失敗 — errorType=\(type(of: error))")
            #endif
            status = .loggedOut
        }
    }

    /// Device Code Flow によるログインを開始する
    ///
    /// ブラウザで twitch.tv/activate を開き、ユーザーがコードを入力するまでポーリングする
    /// `cancelDeviceFlow()` でキャンセル可能
    func startLogin() {
        loginTask?.cancel()
        loginError = nil
        loginTask = Task {
            await login()
        }
    }

    /// Device Code Flow によるログイン処理を実行する
    ///
    /// テストでは直接 `await authState.login()` で呼び出せる
    /// UI からは `startLogin()` を使うこと
    func login() async {
        loginError = nil
        do {
            // デバイスコードを取得してユーザーコードを UI に表示
            let deviceResponse = try await authClient.requestDeviceCode()
            deviceFlowInfo = DeviceFlowInfo(
                userCode: deviceResponse.userCode,
                verificationUri: deviceResponse.verificationUri
            )

            // デフォルトブラウザで認証ページを開く
            if let url = URL(string: deviceResponse.verificationUri) {
                openURL(url)
            }

            // ユーザーが認証するまでポーリング
            let tokenResponse = try await authClient.pollForToken(
                deviceCode: deviceResponse.deviceCode,
                interval: deviceResponse.interval,
                expiresIn: deviceResponse.expiresIn
            )
            let validateResponse = try await authClient.validateToken(accessToken: tokenResponse.accessToken)

            // 必須スコープ不足の場合はロールバックしてログアウト状態に戻す
            let missingScopes = missingRequiredChatScopes(in: validateResponse.scopes)
            guard missingScopes.isEmpty else {
                #if DEBUG
                print("[AuthState] login: 必須スコープ不足 \(missingScopes) — ログインを中断")
                #endif
                deviceFlowInfo = nil
                loginError = "必要なスコープ（\(missingScopes.joined(separator: ", "))）が付与されていません。再ログインしてください。"
                status = .loggedOut
                return
            }

            // Keychain にトークンを保存
            try await keychainStore.save(key: "access_token", value: tokenResponse.accessToken)
            try await keychainStore.save(key: "refresh_token", value: tokenResponse.refreshToken)
            try await keychainStore.save(key: "user_id", value: validateResponse.userId)
            try await keychainStore.save(key: "user_login", value: validateResponse.login)

            deviceFlowInfo = nil
            grantedScopes = validateResponse.scopes
            accessToken = tokenResponse.accessToken
            userId = validateResponse.userId
            status = .loggedIn(userLogin: validateResponse.login)
        } catch is CancellationError {
            // cancelDeviceFlow() が status と deviceFlowInfo を管理するため何もしない
            deviceFlowInfo = nil
        } catch TwitchAuthError.userCancelled {
            // ユーザーが認証を拒否した場合はログアウト状態に戻す
            deviceFlowInfo = nil
            await keychainStore.deleteAll()
            accessToken = nil
            status = .loggedOut
        } catch {
            // 途中で保存されたトークンをロールバックして不整合を防ぐ
            deviceFlowInfo = nil
            await keychainStore.deleteAll()
            accessToken = nil
            loginError = error.localizedDescription
            status = .loggedOut
        }
        loginTask = nil
    }

    /// Device Code Flow をキャンセルしてログアウト状態に戻す
    func cancelDeviceFlow() {
        loginTask?.cancel()
        loginTask = nil
        deviceFlowInfo = nil
        status = .loggedOut
    }

    /// ログアウトする
    ///
    /// アクセストークンを Twitch サーバーで失効させ、Keychain からすべてのトークンを削除する
    func logout() async {
        if let token = accessToken {
            await authClient.revokeToken(accessToken: token)
        }
        await keychainStore.deleteAll()
        accessToken = nil
        userId = nil
        grantedScopes = []
        status = .loggedOut
    }

    /// 有効なアクセストークンを取得する
    ///
    /// ログイン済みであれば現在のアクセストークンを返す
    /// 期限切れであれば自動リフレッシュを試み、新しいトークンを返す
    /// ログアウト中または復元不能な場合は `nil` を返す
    func validAccessToken() async -> String? {
        guard let token = accessToken else { return nil }

        do {
            _ = try await authClient.validateToken(accessToken: token)
            return token
        } catch TwitchAuthError.tokenExpired {
            await tryRefreshToken()
            return accessToken
        } catch {
            return token
        }
    }

    // MARK: - プライベートメソッド

    /// EventSub 購読・チャット投稿に必要な必須スコープ一覧
    private static let requiredChatScopes = ["chat:edit", "user:read:chat"]

    /// 不足している必須スコープを返す
    ///
    /// - Parameter scopes: トークンに付与されているスコープ一覧
    /// - Returns: 不足スコープの配列。すべて揃っている場合は空配列
    private func missingRequiredChatScopes(in scopes: [String]) -> [String] {
        Self.requiredChatScopes.filter { !scopes.contains($0) }
    }

    /// リフレッシュトークンで新しいアクセストークンを取得する

    private func tryRefreshToken() async {
        guard let refreshTokenValue = await keychainStore.load(key: "refresh_token") else {
            // リフレッシュトークンがない場合は認証情報を破棄してログアウト
            await keychainStore.deleteAll()
            accessToken = nil
            status = .loggedOut
            return
        }

        do {
            let tokenResponse = try await authClient.refreshToken(refreshToken: refreshTokenValue)
            let validateResponse = try await authClient.validateToken(accessToken: tokenResponse.accessToken)

            // 必須スコープ不足の場合は認証情報を廃棄してログアウト
            let missingScopes = missingRequiredChatScopes(in: validateResponse.scopes)
            guard missingScopes.isEmpty else {
                #if DEBUG
                print("[AuthState] tryRefreshToken: 必須スコープ不足 \(missingScopes) — ログアウト")
                #endif
                await keychainStore.deleteAll()
                accessToken = nil
                userId = nil
                grantedScopes = []
                status = .loggedOut
                return
            }

            try await keychainStore.save(key: "access_token", value: tokenResponse.accessToken)
            try await keychainStore.save(key: "refresh_token", value: tokenResponse.refreshToken)
            // validateResponse.userId を優先して使用し、Keychain にも上書き保存する
            try await keychainStore.save(key: "user_id", value: validateResponse.userId)

            grantedScopes = validateResponse.scopes
            accessToken = tokenResponse.accessToken
            userId = validateResponse.userId
            status = .loggedIn(userLogin: validateResponse.login)
        } catch {
            await keychainStore.deleteAll()
            accessToken = nil
            userId = nil
            grantedScopes = []
            status = .loggedOut
        }
    }
}

// MARK: - テスト用メソッド

#if DEBUG
extension AuthState {
    /// テスト用: ユーザー ID を直接設定する
    ///
    /// ログインフローをバイパスして userId だけを設定するテスト専用メソッド。
    /// `#if DEBUG` でガードされており、リリースビルドでは使用不可。
    func setUserIdForTesting(_ id: String) {
        userId = id
    }
}
#endif

// MARK: - HelixAPITokenProvider 準拠

extension AuthState: HelixAPITokenProvider {
    /// 現在の有効なアクセストークンを取得する
    ///
    /// プロパティ `accessToken` との名前衝突を避けるため `fetchAccessToken` として定義。
    /// 期限切れの場合は自動リフレッシュを試みる。未ログインまたは復元不能な場合は `nil`
    func fetchAccessToken() async -> String? {
        await validAccessToken()
    }

    /// Twitch アプリの Client ID を返す
    func clientID() async throws -> String {
        try AuthConfig.clientID()
    }
}
