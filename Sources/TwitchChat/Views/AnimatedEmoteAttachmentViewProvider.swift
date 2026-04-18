// AnimatedEmoteAttachmentViewProvider.swift
// NSTextAttachmentViewProvider の実装でアニメーション GIF エモートをインライン再生する
// TextKit 2（NSTextLayoutManager）使用時に NSTextAttachment の描画を NSImageView に委譲する
//
// 【現状】
// EmoteTextAttachment.viewProvider(for:) のオーバーライドによる起動を廃止した（ポップオーバー
// 閉鎖アニメーション中に viewport が再計算されて NSImageView が誤配置される問題のため）。
// 現在このクラスは直接使用されていない。将来の animation 実装の参考として残している。

@preconcurrency import AppKit

/// 入力欄のアニメーションエモート表示用テキストアタッチメントビュープロバイダ
///
/// NSTextAttachment の描画を `NSImageView`（animates = true）に委譲し、
/// TextKit 2（NSTextLayoutManager）上でエモートの GIF アニメーションを再生する。
///
/// - Note: TextKit 1（NSLayoutManager）環境では呼ばれず、image プロパティによる静止画描画にフォールバックする
/// - Note: macOS 12 以降で利用可能。本アプリの対象 macOS 15+ では常に有効
@available(macOS 12.0, *)
final class AnimatedEmoteAttachmentViewProvider: NSTextAttachmentViewProvider {

    /// アタッチメントに対応するアニメーション再生可能な NSImageView を生成する
    override func loadView() {
        let size = EmoteImageCache.emoteDisplaySize
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        imageView.image = textAttachment?.image
        // アニメーション GIF を自動再生する
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view = imageView
    }
}
