// PlaybackOptions.swift
// HLS 再生時の Usher URL 組み立てオプション
// Low-Latency モード・コーデック指定・広告サーブ設定を一元管理する

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

    /// SSAI 広告セグメントを HLS マニフェストに含めるよう Usher に要求するかどうか
    ///
    /// `true` のとき `platform=web`, `player_type=site`, `server_ads=true`, `allow_audio_only=true` を
    /// Usher URL に付与し、Twitch 側に Web Player 相当の広告サーブを促す。
    let adServingEnabled: Bool

    /// - Parameters:
    ///   - lowLatencyEnabled: `low_latency=true` を付与するかどうか
    ///   - supportedCodecs: 対応コーデックリスト（空文字・空白は除去、空の場合は `["avc1"]` にフォールバック）
    ///   - adServingEnabled: SSAI 広告セグメントを要求するかどうか（デフォルト `true`）
    init(lowLatencyEnabled: Bool, supportedCodecs: [String], adServingEnabled: Bool = true) {
        let normalized = supportedCodecs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.lowLatencyEnabled = lowLatencyEnabled
        self.supportedCodecs = normalized.isEmpty ? ["avc1"] : normalized
        self.adServingEnabled = adServingEnabled
    }

    /// デフォルト設定（Low Latency 有効・AVC1 のみ・広告サーブ有効）
    static let `default` = PlaybackOptions(
        lowLatencyEnabled: true,
        supportedCodecs: ["avc1"],
        adServingEnabled: true
    )
}
