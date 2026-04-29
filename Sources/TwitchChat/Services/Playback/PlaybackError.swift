// PlaybackError.swift
// Twitch ライブ配信 HLS 再生に関するエラー型

import Foundation

/// Twitch ライブ配信の HLS 再生中に発生するエラー
enum PlaybackError: Error, Equatable {

    /// GQL PlaybackAccessToken リクエストが HTTP エラーを返した
    case tokenRequestFailed(statusCode: Int)

    /// GQL レスポンスのデコードに失敗した（形式変更などで発生する可能性がある）
    case tokenDecodingFailed

    /// Usher マニフェスト URL の組み立てに失敗した（内部ロジックの誤りで発生する）
    case badURL

    /// Usher マニフェストの取得に失敗した（想定外のステータスコード）
    case manifestUnreachable(statusCode: Int)

    /// チャンネルがオフライン（Usher が 404 を返した）
    case channelOffline

    /// 地域制限またはサブスクライバー限定配信のため視聴不可（Usher が 403 を返した）
    case geoOrSubscriberRestricted

    /// ネットワークエラー
    case network(URLError)

    static func == (lhs: PlaybackError, rhs: PlaybackError) -> Bool {
        switch (lhs, rhs) {
        case let (.tokenRequestFailed(l), .tokenRequestFailed(r)): return l == r
        case (.tokenDecodingFailed, .tokenDecodingFailed): return true
        case (.badURL, .badURL): return true
        case let (.manifestUnreachable(l), .manifestUnreachable(r)): return l == r
        case (.channelOffline, .channelOffline): return true
        case (.geoOrSubscriberRestricted, .geoOrSubscriberRestricted): return true
        case let (.network(l), .network(r)): return l.code == r.code
        default: return false
        }
    }
}
