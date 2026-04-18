// AnimatedEmoteAttachmentViewProvider.swift
// NSTextAttachmentViewProvider の実装でアニメーション GIF エモートをインライン再生する
// TextKit 2（NSTextLayoutManager）使用時に NSTextAttachment の描画を NSImageView に委譲する

import AppKit

/// 入力欄のアニメーションエモート表示用テキストアタッチメントビュープロバイダ
///
/// NSTextAttachment の描画を `NSImageView`（animates = true）に委譲し、
/// TextKit 2（NSTextLayoutManager）上でエモートの GIF アニメーションを再生する。
///
/// NSTextAttachment.image プロパティによる静止画描画とは異なり、
/// このプロバイダを通じてアニメーション GIF が正しく再生される。
///
/// 画像は `EmoteTextAttachment.emoteImage` から取得する。
/// `NSTextAttachment.image` を設定すると `fileType` が nil になる AppKit の仕様のため、
/// アニメーション用画像は `emoteImage` プロパティで独立して保持している。
///
/// - Note: TextKit 1（NSLayoutManager）環境では呼ばれず、image プロパティによる静止画描画にフォールバックする
/// - Note: macOS 12 以降で利用可能。本アプリの対象 macOS 15+ では常に有効
@available(macOS 12.0, *)
@MainActor
final class AnimatedEmoteAttachmentViewProvider: NSTextAttachmentViewProvider {

    /// アタッチメントに対応するアニメーション再生可能な NSImageView を生成する
    ///
    /// TextKit 2 はレイアウトサイクルをメインスレッドで実行するため、
    /// このクラスを `@MainActor` に隔離して NSImageView の操作を安全に行う。
    override func loadView() {
        let size = EmoteImageCache.emoteDisplaySize
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        // EmoteTextAttachment.emoteImage を使用する（image プロパティは fileType と排他的なため）
        let image = (textAttachment as? EmoteTextAttachment)?.emoteImage ?? textAttachment?.image
        imageView.image = image
        // アニメーション GIF を自動再生する
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view = imageView
        // ビュープロバイダ自身が bounds を管理する
        // attachmentBounds(for:...) の戻り値がビューのフレームに使用される
        tracksTextAttachmentViewBounds = true
    }

    /// アタッチメントビューの表示領域を返す
    ///
    /// `tracksTextAttachmentViewBounds = true` のとき、レイアウトエンジンはこのメソッドを呼ぶ。
    /// NSTextAttachment.bounds の代わりにここで bounds を確定させることで、
    /// 挿入直後に NSImageView が正確な位置にフレーム設定される。
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let size = EmoteImageCache.emoteDisplaySize
        // y: -3 でベースラインから 3pt 下にオフセット（テキスト行高に合わせる）
        return CGRect(x: 0, y: -3, width: size, height: size)
    }
}
