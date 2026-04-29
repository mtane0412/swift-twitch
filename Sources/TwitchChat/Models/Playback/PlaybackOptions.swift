// PlaybackOptions.swift
// HLS 再生時の Usher URL 組み立てオプション
// Low-Latency モードやコーデック指定を一元管理する

import Foundation

/// Twitch ライブ配信 HLS 再生オプション
///
/// Usher URL のクエリパラメータに影響する設定を保持する。
/// UI なし方針のため、現在は `default` を常時使用する。
struct PlaybackOptions: Sendable {

    /// `low_latency=true` クエリを Usher URL に付与するかどうか
    let lowLatencyEnabled: Bool

    /// `supported_codecs` クエリに使用するコーデックリスト（カンマ連結される）
    let supportedCodecs: [String]

    /// デフォルト設定（Low Latency 有効、AVC1 のみ）
    static let `default` = PlaybackOptions(
        lowLatencyEnabled: true,
        supportedCodecs: ["avc1"]
    )
}
