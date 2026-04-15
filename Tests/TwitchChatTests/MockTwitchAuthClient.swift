// MockTwitchAuthClient.swift
// TwitchAuthClient のモック実装
// AuthState などのテストで外部 API 通信を行わずに認証フローをシミュレートする

import Foundation
@testable import TwitchChat

/// TwitchAuthClient のモック実装
@MainActor
final class MockTwitchAuthClient: TwitchAuthClientProtocol {

    // MARK: - モック設定プロパティ

    /// `requestDeviceCode()` の返却値
    var deviceCodeResponse: TwitchDeviceCodeResponse?

    /// `pollForToken()` / `refreshToken()` の返却値
    var tokenResponse: TwitchTokenResponse?

    /// `validateToken()` の返却値
    var validateResponse: TwitchValidateResponse?

    /// スローするエラー（設定時はすべてのメソッドがこのエラーをスロー）
    var errorToThrow: Error?

    // MARK: - 呼び出し記録

    /// `requestDeviceCode()` の呼び出し回数
    private(set) var requestDeviceCodeCallCount = 0

    /// `pollForToken()` の呼び出し回数
    private(set) var pollForTokenCallCount = 0

    /// `validateToken()` の呼び出し回数
    private(set) var validateCallCount = 0

    /// `revokeToken()` の呼び出し回数
    private(set) var revokeCallCount = 0

    /// `refreshToken()` の呼び出し回数
    private(set) var refreshCallCount = 0

    // MARK: - 初期化

    init(
        deviceCodeResponse: TwitchDeviceCodeResponse? = nil,
        tokenResponse: TwitchTokenResponse? = nil,
        validateResponse: TwitchValidateResponse? = nil,
        errorToThrow: Error? = nil
    ) {
        self.deviceCodeResponse = deviceCodeResponse
        self.tokenResponse = tokenResponse
        self.validateResponse = validateResponse
        self.errorToThrow = errorToThrow
    }

    // MARK: - TwitchAuthClientProtocol

    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse {
        requestDeviceCodeCallCount += 1
        if let error = errorToThrow { throw error }
        guard let response = deviceCodeResponse else {
            throw TwitchAuthError.networkError
        }
        return response
    }

    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int? = nil) async throws -> TwitchTokenResponse {
        pollForTokenCallCount += 1
        if let error = errorToThrow { throw error }
        guard let response = tokenResponse else {
            throw TwitchAuthError.networkError
        }
        return response
    }

    func refreshToken(refreshToken: String) async throws -> TwitchTokenResponse {
        refreshCallCount += 1
        if let error = errorToThrow { throw error }
        guard let response = tokenResponse else {
            throw TwitchAuthError.networkError
        }
        return response
    }

    func validateToken(accessToken: String) async throws -> TwitchValidateResponse {
        validateCallCount += 1
        if let error = errorToThrow { throw error }
        guard let response = validateResponse else {
            throw TwitchAuthError.networkError
        }
        return response
    }

    func revokeToken(accessToken: String) async {
        revokeCallCount += 1
    }
}

// MARK: - 期限切れ → リフレッシュ成功シナリオ用モック

/// 最初の validateToken 呼び出しのみ tokenExpired を返し、
/// 以降は正常レスポンスを返すモック
///
/// restoreSession のリフレッシュフローをテストするために使用する
@MainActor
final class MockTwitchAuthClientWithFirstCallExpiry: TwitchAuthClientProtocol {

    private let refreshResponse: TwitchTokenResponse
    private let validateResponse: TwitchValidateResponse
    private var validateCallCount = 0

    init(refreshResponse: TwitchTokenResponse, validateResponse: TwitchValidateResponse) {
        self.refreshResponse = refreshResponse
        self.validateResponse = validateResponse
    }

    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse {
        throw TwitchAuthError.networkError
    }

    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int? = nil) async throws -> TwitchTokenResponse {
        throw TwitchAuthError.networkError
    }

    func refreshToken(refreshToken: String) async throws -> TwitchTokenResponse {
        return refreshResponse
    }

    func validateToken(accessToken: String) async throws -> TwitchValidateResponse {
        validateCallCount += 1
        // 1回目は期限切れ（restoreSession での初回検証）、2回目以降は成功
        if validateCallCount == 1 {
            throw TwitchAuthError.tokenExpired
        }
        return validateResponse
    }

    func revokeToken(accessToken: String) async {}
}
