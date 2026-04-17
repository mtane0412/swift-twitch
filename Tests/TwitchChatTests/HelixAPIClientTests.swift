// HelixAPIClientTests.swift
// HelixAPIClient の単体テスト
// トークン未設定時のエラー送出など、認証関連の振る舞いを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// テスト用トークンプロバイダーモック
struct MockHelixAPITokenProvider: HelixAPITokenProvider {
    /// 返すアクセストークン（nil の場合は未ログイン状態をシミュレート）
    var token: String?
    /// 返すクライアントID
    var clientId: String = "テストクライアントID"
    /// clientID() で throw するかどうか
    var shouldThrowClientIDError: Bool = false

    func fetchAccessToken() async -> String? { token }

    func clientID() async throws -> String {
        if shouldThrowClientIDError {
            throw AuthConfigError.missingClientID
        }
        return clientId
    }
}

@Suite("HelixAPIClient テスト")
struct HelixAPIClientTests {

    @Test("トークンが未設定の場合、URLError.userAuthenticationRequired を throw する")
    func testThrowsWhenNoToken() async {
        // 前提: token が nil（未ログイン状態）
        let provider = MockHelixAPITokenProvider(token: nil)
        let client = HelixAPIClient(tokenProvider: provider)

        do {
            let _: HelixBadgesResponse = try await client.get(
                url: URL(string: "https://api.twitch.tv/helix/chat/badges/global")!,
                queryItems: nil
            )
            Issue.record("エラーが throw されなかった")
        } catch let error as URLError {
            // URLError.userAuthenticationRequired が throw されること
            #expect(error.code == .userAuthenticationRequired)
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
    }

    @Test("Client ID が未設定の場合、AuthConfigError を throw する")
    func testThrowsWhenClientIDMissing() async {
        // 前提: token はあるが clientID() が throw する
        let provider = MockHelixAPITokenProvider(
            token: "テストトークン",
            shouldThrowClientIDError: true
        )
        let client = HelixAPIClient(tokenProvider: provider)

        do {
            let _: HelixBadgesResponse = try await client.get(
                url: URL(string: "https://api.twitch.tv/helix/chat/badges/global")!,
                queryItems: nil
            )
            Issue.record("エラーが throw されなかった")
        } catch AuthConfigError.missingClientID {
            // 期待通りのエラーが throw されること
            #expect(Bool(true))
        } catch {
            Issue.record("予期しないエラー: \(error)")
        }
    }
}
