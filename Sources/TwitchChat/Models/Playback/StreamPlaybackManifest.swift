// StreamPlaybackManifest.swift
// Twitch ライブ配信 HLS マニフェスト URL の DTO

import Foundation

/// Twitch ライブ配信の HLS マスターマニフェスト URL
///
/// `StreamPlaybackResolver` が GQL トークン取得と Usher URL 組み立てを経て返す値。
/// `AVPlayer` にこの URL を渡して再生を開始できる。
struct StreamPlaybackManifest: Sendable {
    /// AVPlayer に渡す HLS マスターマニフェスト URL（usher.ttvnw.net）
    let url: URL
    /// マニフェストを取得した日時（トークン失効の判断に使用する可能性あり）
    let fetchedAt: Date
}
