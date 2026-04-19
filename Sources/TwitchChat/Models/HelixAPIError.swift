// HelixAPIError.swift
// Twitch Helix API のエラー型
// HTTP ステータスコードをドメイン固有のエラーに変換して上位層に伝達する

import Foundation

/// Twitch Helix API から返されるエラー
///
/// HTTP ステータスコードをドメイン固有のエラーとして表現する。
/// `ModerationService` が API 呼び出し失敗時に throw する。
enum HelixAPIError: Error, LocalizedError, Equatable {

    /// 認証エラー（HTTP 401）: トークン無効またはスコープ不足
    case unauthorized

    /// 権限エラー（HTTP 403）: モデレーター権限がない等
    ///
    /// - Parameter message: Helix API が返すエラーメッセージ
    case forbidden(String)

    /// リソース未発見（HTTP 404）: 対象ユーザーや配信が存在しない
    case notFound

    /// レートリミット超過（HTTP 429）
    case rateLimited

    /// サーバーエラー（HTTP 5xx）
    ///
    /// - Parameter statusCode: HTTP ステータスコード
    case serverError(Int)

    /// 予期しない HTTP ステータスコード
    ///
    /// - Parameter statusCode: HTTP ステータスコード
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "認証エラーです。再ログインしてください。"
        case .forbidden(let message):
            return "権限がありません: \(message)"
        case .notFound:
            return "対象が見つかりませんでした。"
        case .rateLimited:
            return "APIのレートリミットを超過しました。しばらく待ってから再試行してください。"
        case .serverError(let code):
            return "サーバーエラーが発生しました（HTTP \(code)）。"
        case .unexpectedStatus(let code):
            return "予期しないレスポンスです（HTTP \(code)）。"
        }
    }

    /// HTTP ステータスコードから HelixAPIError を生成する
    ///
    /// - Parameters:
    ///   - statusCode: HTTP ステータスコード
    ///   - message: Helix API が返すエラーメッセージ（省略可）
    /// - Returns: 対応する `HelixAPIError`
    static func from(statusCode: Int, message: String = "") -> HelixAPIError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message)
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError(statusCode)
        default:
            return .unexpectedStatus(statusCode)
        }
    }
}
