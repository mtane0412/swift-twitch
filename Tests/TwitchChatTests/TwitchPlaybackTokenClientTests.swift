// TwitchPlaybackTokenClientTests.swift
// TwitchPlaybackTokenClient の単体テスト
// MockURLSessionDataFetcher を使ってネットワーク通信なしで GQL リクエスト整形・レスポンスデコード・エラーパスを検証する

import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// URLSessionDataFetcher のモック実装
///
/// スタブレスポンスを返し、受け取ったリクエストをキャプチャして検証に使用する
actor MockURLSessionDataFetcher: URLSessionDataFetcher {

    /// 返すレスポンスデータと HTTP ステータスコード（正常ケース用）
    struct Stub {
        let statusCode: Int
        let data: Data
    }

    /// スタブとして返す成功レスポンス（nil の場合はエラーを投げる）
    var stub: Stub?
    /// 投げる URLError（nil の場合はスタブデータを返す）
    var stubbedError: URLError?
    /// キャプチャしたリクエスト（検証用）
    private(set) var capturedRequests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)

        if let error = stubbedError {
            throw error
        }

        guard let stub else {
            throw URLError(.badServerResponse)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (stub.data, response)
    }
}

// MARK: - テストデータファクトリ

/// 正常な GQL PlaybackAccessToken レスポンス JSON データを生成する
private func makeSuccessResponseData(value: String = "テスト用トークン値", signature: String = "テスト用シグネチャ") -> Data {
    let json = """
    {
        "data": {
            "streamPlaybackAccessToken": {
                "value": "\(value)",
                "signature": "\(signature)"
            }
        }
    }
    """
    return json.data(using: .utf8)!
}

// MARK: - テスト

@Suite("TwitchPlaybackTokenClient テスト")
struct TwitchPlaybackTokenClientTests {

    // MARK: - デコードテスト

    @Test("GQL レスポンスから value と signature をデコードできる")
    func decodesValueAndSignatureFromSuccessResponse() async throws {
        // 前提: 正常な GQL レスポンスを返すモック
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: makeSuccessResponseData(
            value: "テスト用トークン値",
            signature: "テスト用シグネチャabc123"
        )))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")
        let token = try await client.fetchLiveToken(login: "テストチャンネル")

        #expect(token.value == "テスト用トークン値")
        #expect(token.signature == "テスト用シグネチャabc123")
    }

    @Test("login が大文字を含む場合も小文字化して GQL に送信する")
    func normalizesLoginToLowercase() async throws {
        // 前提: 大文字混じりの login を渡した場合も、リクエストボディは小文字になること
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: makeSuccessResponseData()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")
        _ = try await client.fetchLiveToken(login: "NijisanjiJP")

        // キャプチャしたリクエストボディで login が小文字化されているか確認
        let requests = await fetcher.capturedRequests
        guard let bodyData = requests.first?.httpBody,
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            Issue.record("リクエストボディが nil")
            return
        }
        #expect(bodyString.contains("\"nijisanjijp\""), "login が小文字化されていない: \(bodyString)")
    }

    @Test("GQL リクエストに Client-Id ヘッダーが付与される")
    func addsClientIdHeader() async throws {
        // 前提: 任意の clientID を指定したとき、リクエストヘッダーに反映されること
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: makeSuccessResponseData()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テスト専用クライアントID")
        _ = try await client.fetchLiveToken(login: "argstar")

        let requests = await fetcher.capturedRequests
        let headers = requests.first?.allHTTPHeaderFields ?? [:]
        #expect(headers["Client-Id"] == "テスト専用クライアントID", "Client-Id ヘッダーが設定されていない: \(headers)")
    }

    @Test("GQL リクエストのメソッドは POST である")
    func requestMethodIsPost() async throws {
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: makeSuccessResponseData()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")
        _ = try await client.fetchLiveToken(login: "forsen")

        let requests = await fetcher.capturedRequests
        #expect(requests.first?.httpMethod == "POST")
    }

    // MARK: - エラーパステスト

    @Test("HTTP 401 のとき tokenRequestFailed(statusCode: 401) を投げる")
    func throws401Error() async throws {
        // 前提: 401 レスポンスを返すモック
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 401, data: Data()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")

        do {
            _ = try await client.fetchLiveToken(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenRequestFailed(statusCode: 401))
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("HTTP 403 のとき tokenRequestFailed(statusCode: 403) を投げる")
    func throws403Error() async throws {
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 403, data: Data()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")

        do {
            _ = try await client.fetchLiveToken(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenRequestFailed(statusCode: 403))
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("空ボディが返ったとき tokenDecodingFailed を投げる")
    func throwsDecodingFailedOnEmptyBody() async throws {
        // 前提: ステータス 200 だがボディが空（デコード不能）
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: Data()))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")

        do {
            _ = try await client.fetchLiveToken(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenDecodingFailed)
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("不正な JSON が返ったとき tokenDecodingFailed を投げる")
    func throwsDecodingFailedOnMalformedJSON() async throws {
        // 前提: 200 だが GQL レスポンス形式と異なる JSON
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStub(.init(statusCode: 200, data: #"{"unexpected": "structure"}"#.data(using: .utf8)!))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")

        do {
            _ = try await client.fetchLiveToken(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .tokenDecodingFailed)
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }

    @Test("ネットワーク切断時は network(URLError) を投げる")
    func throwsNetworkErrorOnConnectionFailure() async throws {
        // 前提: ネットワーク接続なし（notConnectedToInternet）をシミュレート
        let fetcher = MockURLSessionDataFetcher()
        await fetcher.setStubbedError(URLError(.notConnectedToInternet))

        let client = TwitchPlaybackTokenClient(dataFetcher: fetcher, clientID: "テストクライアントID")

        do {
            _ = try await client.fetchLiveToken(login: "テストチャンネル")
            Issue.record("エラーが throw されなかった")
        } catch let error as PlaybackError {
            #expect(error == .network(URLError(.notConnectedToInternet)))
        } catch {
            Issue.record("予期しないエラー型: \(error)")
        }
    }
}

// MARK: - MockURLSessionDataFetcher セッターヘルパー

extension MockURLSessionDataFetcher {
    func setStub(_ stub: Stub) {
        self.stub = stub
        self.stubbedError = nil
    }

    func setStubbedError(_ error: URLError) {
        self.stubbedError = error
        self.stub = nil
    }
}

// MARK: - StreamPlaybackToken デコードテスト

@Suite("GQLPlaybackTokenResponse デコードテスト")
struct GQLPlaybackTokenResponseTests {

    @Test("正常な GQL JSON を GQLPlaybackTokenResponse にデコードできる")
    func decodesFullGQLResponse() throws {
        // Twitch GQL の実際のレスポンス形式に近いデータ
        let json = """
        {
            "data": {
                "streamPlaybackAccessToken": {
                    "value": "{\\"channel\\":\\"argstar\\",\\"exp\\":9999999999}",
                    "signature": "abcdef1234567890"
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GQLPlaybackTokenResponse.self, from: data)

        #expect(response.data.streamPlaybackAccessToken.value.contains("argstar"))
        #expect(response.data.streamPlaybackAccessToken.signature == "abcdef1234567890")
    }

    @Test("streamPlaybackAccessToken フィールドがないとデコードエラーになる")
    func failsDecodingWhenFieldMissing() {
        let json = #"{"data": {}}"#.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(GQLPlaybackTokenResponse.self, from: json)
            Issue.record("デコードエラーが throw されなかった")
        } catch {
            // DecodingError が throw されればよい
            #expect(error is DecodingError)
        }
    }
}
