// AnimatedEmoteView.swift
// アニメーション対応のエモート画像ビュー
// NSImageView をラップして GIF アニメーションを再生する SwiftUI ビュー

import AppKit
import SwiftUI

/// アニメーション対応のエモート画像ビュー
///
/// `NSImageView` を `NSViewRepresentable` でラップし、GIF アニメーションを再生する。
/// スタティック画像の場合は通常の静止画として表示する。
///
/// - Note: `Text(Image(nsImage:))` ではアニメーションが再生できないため、
///   アニメーション版エモートにはこのビューを使用する
struct AnimatedEmoteView: NSViewRepresentable {

    /// 表示する NSImage（アニメーション GIF またはスタティック PNG）
    let image: NSImage

    /// アニメーションを再生するかどうか
    let isAnimated: Bool

    /// 表示サイズ（ポイント）。デフォルトは `EmoteImageCache.emoteDisplaySize`
    var size: CGFloat = EmoteImageCache.emoteDisplaySize

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        // 縦横比を保ちながらフレームに収める
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.image = image
        // アニメーション GIF の場合は自動再生を有効にする
        imageView.animates = isAnimated
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}
