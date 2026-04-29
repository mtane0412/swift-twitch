// PlaybackOptions.swift
// HLS 再生時の Usher URL 組み立てオプション
// Low-Latency モードやコーデック指定を一元管理する

import Foundation

/// Twitch ライブ配信 HLS 再生オプション
///
/// Usher URL のクエリパラメータに影響する設定を保持する。
/// 基本設定は `default` だが、テスト用途や将来の UI・機能拡張に備えて差し替え可能。
struct PlaybackOptions: Sendable {

    /// `low_latency=true` クエリを Usher URL に付与するかどうか
    let lowLatencyEnabled: Bool

    /// `supported_codecs` クエリに使用するコーデックリスト（カンマ連結される）
    ///
    /// 空文字・空白のみのエントリは除去される。全て無効な場合は `["avc1"]` にフォールバックする。
    let supportedCodecs: [String]

    /// - Parameters:
    ///   - lowLatencyEnabled: `low_latency=true` を付与するかどうか
    ///   - supportedCodecs: 対応コーデックリスト（空文字・空白は除去、空の場合は `["avc1"]` にフォールバック）
    init(lowLatencyEnabled: Bool, supportedCodecs: [String]) {
        let normalized = supportedCodecs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.lowLatencyEnabled = lowLatencyEnabled
        self.supportedCodecs = normalized.isEmpty ? ["avc1"] : normalized
    }

    /// デフォルト設定（Low Latency 有効、AVC1 のみ）
    static let `default` = PlaybackOptions(
        lowLatencyEnabled: true,
        supportedCodecs: ["avc1"]
    )
}
