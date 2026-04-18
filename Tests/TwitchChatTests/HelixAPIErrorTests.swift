// HelixAPIErrorTests.swift
// HelixAPIError のファクトリメソッドおよびエラー説明のテスト

import Testing
@testable import TwitchChat

@Suite("HelixAPIErrorTests")
struct HelixAPIErrorTests {

    // MARK: - from(statusCode:message:)

    @Test("ステータスコード 401 は unauthorized になること")
    func testUnauthorized() {
        #expect(HelixAPIError.from(statusCode: 401) == .unauthorized)
    }

    @Test("ステータスコード 403 は forbidden になること")
    func testForbidden() {
        #expect(HelixAPIError.from(statusCode: 403, message: "モデレーター権限が必要です") == .forbidden("モデレーター権限が必要です"))
    }

    @Test("ステータスコード 404 は notFound になること")
    func testNotFound() {
        #expect(HelixAPIError.from(statusCode: 404) == .notFound)
    }

    @Test("ステータスコード 429 は rateLimited になること")
    func testRateLimited() {
        #expect(HelixAPIError.from(statusCode: 429) == .rateLimited)
    }

    @Test("ステータスコード 500 は serverError になること", arguments: [500, 503, 599])
    func testServerError(statusCode: Int) {
        #expect(HelixAPIError.from(statusCode: statusCode) == .serverError(statusCode))
    }

    @Test("未知のステータスコードは unexpectedStatus になること")
    func testUnexpectedStatus() {
        #expect(HelixAPIError.from(statusCode: 422) == .unexpectedStatus(422))
    }

    // MARK: - errorDescription

    @Test("unauthorized の errorDescription が設定されていること")
    func testUnauthorizedDescription() {
        #expect(HelixAPIError.unauthorized.errorDescription != nil)
    }

    @Test("forbidden の errorDescription にメッセージが含まれること")
    func testForbiddenDescription() {
        let error = HelixAPIError.forbidden("権限なし")
        #expect(error.errorDescription?.contains("権限なし") == true)
    }

    @Test("notFound の errorDescription が設定されていること")
    func testNotFoundDescription() {
        #expect(HelixAPIError.notFound.errorDescription != nil)
    }

    @Test("serverError の errorDescription にステータスコードが含まれること")
    func testServerErrorDescription() {
        let error = HelixAPIError.serverError(503)
        #expect(error.errorDescription?.contains("503") == true)
    }

    @Test("rateLimited の errorDescription が設定されていること")
    func testRateLimitedDescription() {
        #expect(HelixAPIError.rateLimited.errorDescription != nil)
    }

    @Test("unexpectedStatus の errorDescription にステータスコードが含まれること")
    func testUnexpectedStatusDescription() {
        let error = HelixAPIError.unexpectedStatus(422)
        #expect(error.errorDescription?.contains("422") == true)
    }
}
