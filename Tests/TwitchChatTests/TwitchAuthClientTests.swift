// TwitchAuthClientTests.swift
// TwitchAuthClient の Device Code Flow 関連テスト
// モッククライアントを使用して外部 API 通信なしで振る舞いを検証する

import Testing
import Foundation
@testable import TwitchChat

@Suite("TwitchAuthClient")
struct TwitchAuthClientTests {

    // MARK: - モッククライアント基本動作

    @Test("モッククライアントはデバイスコードレスポンスを返す")
    @MainActor
    func モッククライアントはデバイスコードレスポンスを返す() async throws {
        // 期待するデバイスコードレスポンスを設定
        let mockClient = MockTwitchAuthClient(
            deviceCodeResponse: TwitchDeviceCodeResponse(
                deviceCode: "テスト用デバイスコード",
                userCode: "ABC-12345",
                verificationUri: "https://www.twitch.tv/activate",
                expiresIn: 1800,
                interval: 5
            )
        )

        let response = try await mockClient.requestDeviceCode()

        #expect(response.userCode == "ABC-12345")
        #expect(response.verificationUri == "https://www.twitch.tv/activate")
        #expect(response.interval == 5)
    }

    @Test("モッククライアントはポーリングでトークンを返す")
    @MainActor
    func モッククライアントはポーリングでトークンを返す() async throws {
        // 期待するトークンレスポンスを設定
        let mockClient = MockTwitchAuthClient(
            tokenResponse: TwitchTokenResponse(
                accessToken: "テスト用アクセストークン",
                refreshToken: "テスト用リフレッシュトークン",
                expiresIn: 14400,
                tokenType: "bearer",
                scope: ["chat:read"]
            )
        )

        let response = try await mockClient.pollForToken(deviceCode: "テスト用デバイスコード", interval: 0)

        #expect(response.accessToken == "テスト用アクセストークン")
        #expect(response.refreshToken == "テスト用リフレッシュトークン")
    }

    @Test("モッククライアントはトークン検証レスポンスを返す")
    @MainActor
    func モッククライアントはトークン検証レスポンスを返す() async throws {
        let mockClient = MockTwitchAuthClient(
            validateResponse: TwitchValidateResponse(
                clientId: "テスト用ClientID",
                login: "テスト配信者",
                userId: "12345678",
                scopes: ["chat:read"],
                expiresIn: 10000
            )
        )

        let response = try await mockClient.validateToken(accessToken: "テスト用アクセストークン")

        #expect(response.login == "テスト配信者")
        #expect(response.userId == "12345678")
    }

    @Test("エラー設定時はすべてのメソッドがエラーをスローする")
    @MainActor
    func エラー設定時はすべてのメソッドがエラーをスローする() async {
        let mockClient = MockTwitchAuthClient(errorToThrow: TwitchAuthError.networkError)

        await #expect(throws: TwitchAuthError.networkError) {
            _ = try await mockClient.requestDeviceCode()
        }
        await #expect(throws: TwitchAuthError.networkError) {
            _ = try await mockClient.pollForToken(deviceCode: "コード", interval: 0)
        }
        await #expect(throws: TwitchAuthError.networkError) {
            _ = try await mockClient.validateToken(accessToken: "トークン")
        }
    }
}
