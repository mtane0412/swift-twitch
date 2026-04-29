// StreamPlaybackResolverTests.swift
// StreamPlaybackResolver の単体テスト
// MockTwitchPlaybackTokenClient を使ってネットワーク通信なしで URL 構築・エラー伝搬・login 正規化を検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// TwitchPlaybackTokenClient のモック実装
actor MockTwitchPlaybackTokenClient: TwitchPlaybackTokenClientProtocol {

    /// 返すトークン（正常ケース用）
    var tokenToReturn: StreamPlaybackToken?
    /// 投げるエラー（nil の場合はトークンを返す）
    var errorToThrow: PlaybackError?
    /// fetchLiveToken が呼ばれたときの login キャプチャ（検証用）
    private(set) var capturedLogins: [String] = []

    func fetchLiveToken(login: String) async throws -> StreamPlaybackToken {
        capturedLogins.append(login)
        if let error = errorToThrow {
            throw error
        }
        guard let token = tokenToReturn else {
            throw PlaybackError.tokenDecodingFailed
        }
        return token
    }
}

// MARK: - テストデータファクトリ

/// テスト用 StreamPlaybackToken を生成する
private func makeToken(
    value: String = "テスト用トークン値",
    signature: String = "テスト用シグネチャ"
) -> StreamPlaybackToken {
    StreamPlaybackToken(value: value, signature: signature)
}

// MARK: - テスト

@Suite("StreamPlaybackResolver テスト")
struct StreamPlaybackResolverTests {

    // MARK: - login 正規化テスト

    @Test("login が大文字を含む場合も小文字化して GQL クライアントに渡す")
    func normalizesLoginToLowercase() async throws {
        // 前提: 大文字混じりの login を渡したとき、GQL クライアントには小文字で渡ること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        _ = try await resolver.resolve(login: "NijisanjiJP")

        let logins = await tokenClient.capturedLogins
        #expect(logins.first == "nijisanjijp", "小文字化されていない: \(logins.first ?? "nil")")
    }

    @Test("小文字のみの login はそのまま渡される")
    func keepsLowercaseLogin() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        _ = try await resolver.resolve(login: "argstar")

        let logins = await tokenClient.capturedLogins
        #expect(logins.first == "argstar")
    }

    // MARK: - Usher URL 構築テスト

    @Test("Usher URL のホストが usher.ttvnw.net である")
    func usherUrlHasCorrectHost() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken(value: "テストトークン", signature: "テストシグネチャ"))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "配信者テスト")

        #expect(manifest.url.host == "usher.ttvnw.net")
    }

    @Test("Usher URL に login が含まれる")
    func usherUrlContainsLogin() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "forsen")

        #expect(manifest.url.path.contains("forsen"), "URL に login が含まれていない: \(manifest.url)")
    }

    @Test("Usher URL に sig クエリパラメータが含まれる")
    func usherUrlContainsSigParam() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken(value: "テストトークン", signature: "シグネチャabc123"))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "テストチャンネル")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let sigValue = components?.queryItems?.first(where: { $0.name == "sig" })?.value
        #expect(sigValue == "シグネチャabc123", "sig クエリが見つからない: \(manifest.url)")
    }

    @Test("Usher URL に token クエリパラメータが含まれる")
    func usherUrlContainsTokenParam() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken(value: "jwt.テスト.トークン", signature: "sig"))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "テストチャンネル")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let tokenValue = components?.queryItems?.first(where: { $0.name == "token" })?.value
        #expect(tokenValue == "jwt.テスト.トークン", "token クエリが見つからない: \(manifest.url)")
    }

    @Test("token に + や / が含まれていても URL クエリとして正しくエンコードされる")
    func encodesSpecialCharactersInToken() async throws {
        // Twitch の JWT トークンは Base64url 文字を含む場合がある
        let specialToken = "eyJhb+GCI6IkpXV/CJ9.payload.sig"
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken(value: specialToken, signature: "sig"))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "テストチャンネル")

        // URL として有効であること（パース可能）
        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let tokenValue = components?.queryItems?.first(where: { $0.name == "token" })?.value
        // URLComponents がデコードして元の値に戻ること
        #expect(tokenValue == specialToken, "特殊文字のエンコードが不正: \(manifest.url)")
    }

    @Test("play_session_id クエリパラメータが呼び出しごとに別 UUID になる")
    func playSessionIdIsUniquePerCall() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest1 = try await resolver.resolve(login: "argstar")
        let manifest2 = try await resolver.resolve(login: "argstar")

        let components1 = URLComponents(url: manifest1.url, resolvingAgainstBaseURL: false)
        let components2 = URLComponents(url: manifest2.url, resolvingAgainstBaseURL: false)
        let sessionId1 = components1?.queryItems?.first(where: { $0.name == "play_session_id" })?.value
        let sessionId2 = components2?.queryItems?.first(where: { $0.name == "play_session_id" })?.value

        #expect(sessionId1 != nil, "play_session_id が nil")
        #expect(sessionId2 != nil, "play_session_id が nil")
        #expect(sessionId1 != sessionId2, "play_session_id が毎回同じ値: \(sessionId1 ?? "")")
    }

    @Test("返却された manifest に fetchedAt タイムスタンプが設定される")
    func manifestHasFetchedAt() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let before = Date()
        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)
        let manifest = try await resolver.resolve(login: "argstar")
        let after = Date()

        #expect(manifest.fetchedAt >= before)
        #expect(manifest.fetchedAt <= after)
    }

    // MARK: - エラー伝搬テスト

    @Test("tokenDecodingFailed はそのまま再スローされる")
    func propagatesTokenDecodingFailed() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setError(.tokenDecodingFailed)

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)

        do {
            _ = try await resolver.resolve(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenDecodingFailed)
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("tokenRequestFailed はそのまま再スローされる")
    func propagatesTokenRequestFailed() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setError(.tokenRequestFailed(statusCode: 500))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)

        do {
            _ = try await resolver.resolve(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenRequestFailed(statusCode: 500))
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("network エラーはそのまま再スローされる")
    func propagatesNetworkError() async throws {
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setError(.network(URLError(.notConnectedToInternet)))

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient)

        do {
            _ = try await resolver.resolve(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .network(URLError(.notConnectedToInternet)))
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }
}

// MARK: - MockTwitchPlaybackTokenClient セッターヘルパー

extension MockTwitchPlaybackTokenClient {
    func setToken(_ token: StreamPlaybackToken) {
        self.tokenToReturn = token
        self.errorToThrow = nil
    }

    func setError(_ error: PlaybackError) {
        self.errorToThrow = error
        self.tokenToReturn = nil
    }
}
