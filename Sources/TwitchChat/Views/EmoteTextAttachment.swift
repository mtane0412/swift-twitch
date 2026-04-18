// EmoteTextAttachment.swift
// 入力欄でエモートをインライン表示するための NSTextAttachment サブクラス
// NSAttributedString 内にエモート画像を埋め込み、送信時に元のエモート名を復元できるようにする

import AppKit

/// 入力欄のインラインエモート表示用テキストアタッチメント
///
/// NSTextView の NSAttributedString 内にエモート画像を埋め込むために使用する。
/// `emoteName` を保持することで、送信時に NSAttributedString からプレーンテキストを復元できる。
///
/// TextKit 2（NSTextLayoutManager）環境では `image` プロパティを使った静止画インライン描画を使用する。
/// `viewProvider(for:location:textContainer:)` のオーバーライドによる `NSTextAttachmentViewProvider` は、
/// ポップオーバー閉鎖アニメーション中にビューポートが再計算されて NSImageView が誤配置される問題があるため
/// 現時点では使用しない。
///
/// - Note: 送信時は `EmoteRichTextView.plainText(from:)` で emoteName に変換する
final class EmoteTextAttachment: NSTextAttachment {

    /// 復元用エモート名（IRC 送信時にプレーンテキストとして使用する）
    let emoteName: String

    /// エモートアタッチメントを初期化する
    ///
    /// - Parameters:
    ///   - image: 表示するエモート画像（アニメーション GIF またはスタティック PNG）
    ///   - emoteName: IRC 送信時に復元するエモート名（例: "LUL"）
    ///   - size: 表示サイズ（デフォルトは EmoteImageCache.emoteDisplaySize）
    init(image: NSImage, emoteName: String, size: CGFloat = EmoteImageCache.emoteDisplaySize) {
        self.emoteName = emoteName
        super.init(data: nil, ofType: nil)
        self.image = image
        self.bounds = CGRect(x: 0, y: -3, width: size, height: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使用しない")
    }
}
