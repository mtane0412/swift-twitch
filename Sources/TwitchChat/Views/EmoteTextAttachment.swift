// EmoteTextAttachment.swift
// 入力欄でエモートをインライン表示するための NSTextAttachment サブクラス
// NSAttributedString 内にエモート画像を埋め込み、送信時に元のエモート名を復元できるようにする

import AppKit

/// 入力欄のインラインエモート表示用テキストアタッチメント
///
/// NSTextView の NSAttributedString 内にエモート画像を埋め込むために使用する。
/// `emoteName` を保持することで、送信時に NSAttributedString からプレーンテキストを復元できる。
///
/// TextKit 2（NSTextLayoutManager）環境では `viewProvider(forParentView:location:textContainer:)`
/// のオーバーライドを通じて `AnimatedEmoteAttachmentViewProvider` が使用され、
/// NSImageView（animates = true）でアニメーション GIF が再生される。
/// TextKit 1 環境では `image` プロパティによる静止画描画にフォールバックする。
///
/// - Note: `image` プロパティを設定すると `fileType` が nil になる（AppKit の仕様）。
///   そのため fileType ベースのビュープロバイダ登録ではなく、
///   `viewProvider(forParentView:location:textContainer:)` を直接オーバーライドして
///   `AnimatedEmoteAttachmentViewProvider` を返す方式を採用している。
/// - Note: 送信時は `EmoteRichTextView.plainText(from:)` で emoteName に変換する
final class EmoteTextAttachment: NSTextAttachment {

    /// 復元用エモート名（IRC 送信時にプレーンテキストとして使用する）
    let emoteName: String

    /// アニメーションビュープロバイダ用の画像（image プロパティとは独立して保持）
    ///
    /// NSTextAttachment では `image` プロパティを設定すると `fileType` が nil になり、
    /// `fileType` を設定すると `image` が nil になる。これらは互いに排他的なため、
    /// アニメーション再生に使用する画像を専用プロパティで別途保持する。
    let emoteImage: NSImage

    /// TextKit 2 用のアニメーションビュープロバイダを返す
    ///
    /// fileType ベースの登録に依存せず、このメソッドをオーバーライドして
    /// `AnimatedEmoteAttachmentViewProvider` を直接返すことでアニメーション再生を実現する。
    /// TextKit 1（NSLayoutManager）環境ではこのメソッドは呼ばれず、`image` による静止画描画にフォールバックする。
    @available(macOS 12.0, *)
    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        AnimatedEmoteAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
    }

    /// エモートアタッチメントを初期化する
    ///
    /// - Parameters:
    ///   - image: 表示するエモート画像（アニメーション GIF またはスタティック PNG）
    ///   - emoteName: IRC 送信時に復元するエモート名（例: "LUL"）
    ///   - size: 表示サイズ（デフォルトは EmoteImageCache.emoteDisplaySize）
    init(image: NSImage, emoteName: String, size: CGFloat = EmoteImageCache.emoteDisplaySize) {
        self.emoteName = emoteName
        self.emoteImage = image
        super.init(data: nil, ofType: nil)
        // TextKit 1 フォールバック用に image プロパティも設定する
        // （image 設定により fileType は nil になるが、viewProvider オーバーライドで TextKit 2 は動作する）
        self.image = image
        self.bounds = CGRect(x: 0, y: -3, width: size, height: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使用しない")
    }
}
