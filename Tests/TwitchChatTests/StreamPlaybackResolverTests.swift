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

    // MARK: - PlaybackOptions テスト

    @Test("PlaybackOptions.default で resolve すると low_latency=true クエリが付与される")
    func defaultOptionsIncludesLowLatencyParam() async throws {
        // 前提: PlaybackOptions.default の lowLatencyEnabled は true
        // 検証: Usher URL に low_latency=true クエリが含まれること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let lowLatencyValue = components?.queryItems?.first(where: { $0.name == "low_latency" })?.value
        #expect(lowLatencyValue == "true", "low_latency=true が含まれていない: \(manifest.url)")
    }

    @Test("PlaybackOptions(lowLatencyEnabled: false) のとき low_latency クエリは付与されない")
    func disabledLowLatencyExcludesParam() async throws {
        // 前提: lowLatencyEnabled=false の PlaybackOptions を渡したとき
        // 検証: Usher URL に low_latency クエリが含まれないこと
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let options = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["avc1"])
        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: options)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let hasLowLatency = components?.queryItems?.contains(where: { $0.name == "low_latency" }) ?? false
        #expect(!hasLowLatency, "low_latency クエリが含まれてしまっている: \(manifest.url)")
    }

    @Test("supportedCodecs が複数のとき supported_codecs はカンマ連結される")
    func multipleCodecsAreJoinedWithComma() async throws {
        // 前提: ["avc1", "hevc"] を supportedCodecs に指定したとき
        // 検証: supported_codecs=avc1,hevc としてクエリに含まれること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let options = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["avc1", "hevc"])
        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: options)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let codecsValue = components?.queryItems?.first(where: { $0.name == "supported_codecs" })?.value
        #expect(codecsValue == "avc1,hevc", "supported_codecs が期待値と異なる: \(codecsValue ?? "nil")")
    }

    // MARK: - 広告サーブパラメータテスト

    @Test("PlaybackOptions.default で resolve すると platform=web クエリが付与される")
    func defaultBuildsUsherWithPlatformWeb() async throws {
        // 前提: adServingEnabled=true（PlaybackOptions.default）で resolve したとき
        // 検証: Usher URL に platform=web クエリが含まれること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: { $0.name == "platform" })?.value
        #expect(value == "web", "platform=web クエリが含まれていない: \(manifest.url)")
    }

    @Test("PlaybackOptions.default で resolve すると player_type=site クエリが付与される")
    func defaultBuildsUsherWithPlayerTypeSite() async throws {
        // 前提: adServingEnabled=true（PlaybackOptions.default）で resolve したとき
        // 検証: Usher URL に player_type=site クエリが含まれること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: { $0.name == "player_type" })?.value
        #expect(value == "site", "player_type=site クエリが含まれていない: \(manifest.url)")
    }

    @Test("PlaybackOptions.default で resolve すると server_ads=true クエリが付与される")
    func defaultBuildsUsherWithServerAdsTrue() async throws {
        // 前提: adServingEnabled=true（PlaybackOptions.default）で resolve したとき
        // 検証: Usher URL に server_ads=true クエリが含まれること（SSAI 有効化に最重要）
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: { $0.name == "server_ads" })?.value
        #expect(value == "true", "server_ads=true クエリが含まれていない: \(manifest.url)")
    }

    @Test("PlaybackOptions.default で resolve すると allow_audio_only=true クエリが付与される")
    func defaultBuildsUsherWithAllowAudioOnlyTrue() async throws {
        // 前提: adServingEnabled=true（PlaybackOptions.default）で resolve したとき
        // 検証: Usher URL に allow_audio_only=true クエリが含まれること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first(where: { $0.name == "allow_audio_only" })?.value
        #expect(value == "true", "allow_audio_only=true クエリが含まれていない: \(manifest.url)")
    }

    @Test("adServingEnabled=false のとき広告サーブ用クエリ 4 個が全て付与されない")
    func adServingDisabledExcludesAllAdParams() async throws {
        // 前提: adServingEnabled=false の PlaybackOptions で resolve したとき
        // 検証: platform / player_type / server_ads / allow_audio_only クエリが全て含まれないこと
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let options = PlaybackOptions(lowLatencyEnabled: true, supportedCodecs: ["avc1"], adServingEnabled: false)
        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: options)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let keys = components?.queryItems?.map { $0.name } ?? []
        #expect(!keys.contains("platform"), "platform クエリが誤って付与されている")
        #expect(!keys.contains("player_type"), "player_type クエリが誤って付与されている")
        #expect(!keys.contains("server_ads"), "server_ads クエリが誤って付与されている")
        #expect(!keys.contains("allow_audio_only"), "allow_audio_only クエリが誤って付与されている")
    }

    @Test("広告サーブ設定に関わらず token / sig / play_session_id クエリは常に付与される")
    func nonAdParamsAlwaysPresentRegardlessOfAdServing() async throws {
        // 前提: adServingEnabled が true / false のどちらでも既存の必須クエリは失われないこと
        // 検証: token, sig, play_session_id が両方の設定で存在すること
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken(value: "検証用トークン", signature: "検証用シグネチャ"))

        let optionsOn = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["avc1"], adServingEnabled: true)
        let resolverOn = StreamPlaybackResolver(tokenClient: tokenClient, options: optionsOn)
        let manifestOn = try await resolverOn.resolve(login: "forsen")

        let optionsOff = PlaybackOptions(lowLatencyEnabled: false, supportedCodecs: ["avc1"], adServingEnabled: false)
        let resolverOff = StreamPlaybackResolver(tokenClient: tokenClient, options: optionsOff)
        let manifestOff = try await resolverOff.resolve(login: "forsen")

        for manifest in [manifestOn, manifestOff] {
            let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
            let keys = components?.queryItems?.map { $0.name } ?? []
            #expect(keys.contains("token"), "token クエリが消えている: \(manifest.url)")
            #expect(keys.contains("sig"), "sig クエリが消えている: \(manifest.url)")
            #expect(keys.contains("play_session_id"), "play_session_id クエリが消えている: \(manifest.url)")
        }
    }

    @Test("adServingEnabled=true のとき Usher URL のクエリ件数は 17 個である")
    func usherQueryItemCountWithAdServingOn() async throws {
        // 前提: PlaybackOptions.default（adServingEnabled=true、lowLatencyEnabled=true）で resolve
        // 検証: 既存 13 クエリ（基本 12 + low_latency）+ 広告 4 = 17 個であること（現状ロック）
        let tokenClient = MockTwitchPlaybackTokenClient()
        await tokenClient.setToken(makeToken())

        let resolver = StreamPlaybackResolver(tokenClient: tokenClient, options: .default)
        let manifest = try await resolver.resolve(login: "argstar")

        let components = URLComponents(url: manifest.url, resolvingAgainstBaseURL: false)
        let count = components?.queryItems?.count ?? 0
        #expect(count == 17, "クエリ件数が期待値 17 と異なる: 実際は \(count) 件")
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
