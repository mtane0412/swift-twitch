// EmoteRichTextView.swift
// エモートインライン表示対応のリッチテキスト入力ビュー
// NSTextView をラップし、エモート名を自動検出して画像に置換する NSViewRepresentable

import AppKit
import SwiftUI

/// エモートインライン表示対応の入力ビュー
///
/// SwiftUI の `TextField` の代替として使用する。
/// スペース入力後に直前の単語が既知のエモート名と一致する場合、
/// `EmoteTextAttachment` で画像に置換してインライン表示する。
///
/// - 送信時は `draft` バインディングに格納されたプレーンテキスト（エモート名を含む）を使用する
/// - プレーンテキストへの変換は `plainText(from:)` が担当する
struct EmoteRichTextView: NSViewRepresentable {

    /// エモート名を含むプレーンテキスト（文字数カウント・送信テキストとして使用）
    @Binding var draft: String

    /// エモート名の検索に使用するエモートストア
    var emoteStore: EmoteStore

    /// Enter キー押下時のコールバック
    var onSubmit: () -> Void

    /// 入力無効フラグ
    var isDisabled: Bool

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        configureTextView(textView, coordinator: context.coordinator)
        // アニメーションフレーム更新通知を購読して NSTextView を再描画する
        context.coordinator.subscribeToFrameUpdates(textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // 無効化状態を反映
        textView.isEditable = !isDisabled

        // NSTextView のプレーンテキスト（アタッチメント → エモート名）と draft を比較して外部変更を検出する
        let currentPlainText = EmoteRichTextView.plainText(from: textView.attributedString())
        guard draft != currentPlainText else { return }

        context.coordinator.isUpdatingFromBinding = true
        if draft.isEmpty {
            // 送信後クリア: NSTextView をリセット
            textView.string = ""
        } else if draft.hasPrefix(currentPlainText) {
            // エモートピッカーによる追記: 差分のみ末尾に挿入し、既存アタッチメントを保持する
            let newPart = String(draft.dropFirst(currentPlainText.count))
            let endRange = NSRange(location: textView.string.utf16.count, length: 0)
            textView.insertText(newPart, replacementRange: endRange)
            // 末尾にスペースがある場合は直前のトークンをエモート置換する
            if draft.hasSuffix(" ") {
                context.coordinator.detectAndReplaceEmote(in: textView)
            }
        } else {
            // その他の外部変更: テキスト全体を置き換えてエモート置換を実行する
            textView.string = draft
            if draft.hasSuffix(" ") {
                context.coordinator.detectAndReplaceEmote(in: textView)
            }
        }
        // NSTextView のフレーム更新（サイズ変更）が完了した後でビューポートをレイアウトする。
        // insertText 直後に呼ぶと NSTextView のフレームがまだ古い状態でアタッチメント位置がずれるため
        // 次のランループで実行する。
        DispatchQueue.main.async { [weak textView] in
            textView?.textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(draft: $draft, emoteStore: emoteStore, onSubmit: onSubmit)
    }

    /// ビュー破棄前に呼ばれるクリーンアップ（@MainActor 上で実行される）
    ///
    /// `Coordinator.deinit` は任意スレッドから呼ばれる可能性があるため、
    /// 代わりにここで通知購読を解除する。これにより `nonisolated(unsafe)` を使わずに済む。
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.unsubscribeFromFrameUpdates()
    }

    // MARK: - NSTextView 設定

    private func configureTextView(_ textView: NSTextView, coordinator: Coordinator) {
        textView.delegate = coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        // 水平スクロールを無効にして折り返し
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // 縦方向のみ拡張
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    // MARK: - プレーンテキスト変換

    /// NSAttributedString をプレーンテキスト（エモート名を含む）に変換する
    ///
    /// - `EmoteTextAttachment` は `emoteName` に変換する
    /// - 通常の文字はそのまま保持する
    ///
    /// - Parameter attributedString: 変換対象の NSAttributedString
    /// - Returns: エモート名を含むプレーンテキスト文字列
    static func plainText(from attributedString: NSAttributedString) -> String {
        var result = ""
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attrs, range, _ in
            if let attachment = attrs[.attachment] as? EmoteTextAttachment {
                result += attachment.emoteName
            } else {
                result += (attributedString.string as NSString).substring(with: range)
            }
        }
        return result
    }

    // MARK: - Coordinator

    /// NSTextViewDelegate を実装し、エモート検出・置換・draft 更新を担当する
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {

        @Binding var draft: String
        let emoteStore: EmoteStore
        let onSubmit: () -> Void

        /// binding 側からのリセット中フラグ（無限ループ防止）
        var isUpdatingFromBinding = false

        /// アニメーションフレーム更新通知のオブザーバートークン
        ///
        /// `dismantleNSView`（MainActor）で `unsubscribeFromFrameUpdates()` を呼ぶため
        /// `nonisolated(unsafe)` は不要。プロパティは常に MainActor 上でアクセスされる。
        private var frameUpdateObserver: NSObjectProtocol?

        init(draft: Binding<String>, emoteStore: EmoteStore, onSubmit: @escaping () -> Void) {
            self._draft = draft
            self.emoteStore = emoteStore
            self.onSubmit = onSubmit
        }

        /// アニメーションフレーム更新通知を購読し、textView に再描画を要求する
        ///
        /// `EmoteAnimationDriver` がフレームを更新した後に通知が届き、
        /// `textStorage.edited(.editedAttributes)` で TextKit 2 に属性変更を通知して
        /// レイアウトフラグメントを無効化し、attachment.image の再取得をトリガーする。
        func subscribeToFrameUpdates(textView: NSTextView) {
            frameUpdateObserver = NotificationCenter.default.addObserver(
                forName: .emoteFrameDidUpdate,
                object: EmoteAnimationDriver.shared,
                queue: .main
            ) { [weak textView] _ in
                // queue: .main で呼ばれるため MainActor 上での実行を安全に前提できる
                MainActor.assumeIsolated {
                    guard let textView,
                          let textStorage = textView.textStorage,
                          textStorage.length > 0 else { return }
                    // attachment.image を変更しても TextKit 2 はフラグメントを有効と判断し続ける。
                    // textStorage.edited(.editedAttributes) でストレージレベルから「属性が変わった」と
                    // 通知することで、layout manager が該当範囲を無効化→再レイアウト→attachment.image
                    // を再取得する一連のパイプラインをトリガーする。
                    // パフォーマンス最適化: EmoteTextAttachment を持つ range のみを無効化する
                    var attachmentRanges: [NSRange] = []
                    textStorage.enumerateAttribute(
                        .attachment,
                        in: NSRange(location: 0, length: textStorage.length),
                        options: []
                    ) { value, range, _ in
                        if value is EmoteTextAttachment {
                            attachmentRanges.append(range)
                        }
                    }
                    guard !attachmentRanges.isEmpty else { return }
                    textStorage.beginEditing()
                    for range in attachmentRanges {
                        textStorage.edited(.editedAttributes, range: range, changeInLength: 0)
                    }
                    textStorage.endEditing()
                }
            }
        }

        /// アニメーションフレーム更新通知の購読を解除する
        ///
        /// `dismantleNSView` から呼ばれる（MainActor 上）。
        func unsubscribeFromFrameUpdates() {
            if let observer = frameUpdateObserver {
                NotificationCenter.default.removeObserver(observer)
                frameUpdateObserver = nil
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdatingFromBinding else {
                isUpdatingFromBinding = false
                return
            }

            // スペースが入力されたとき、直前のトークンがエモート名かチェックする
            let text = textView.string
            if text.hasSuffix(" ") {
                detectAndReplaceEmote(in: textView)
            }

            // draft バインディングをプレーンテキストで更新
            let plain = EmoteRichTextView.plainText(from: textView.attributedString())
            if draft != plain {
                draft = plain
            }
        }

        /// Enter キーで送信、Shift+Enter で改行
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftPressed = NSEvent.modifierFlags.contains(.shift)
                if shiftPressed {
                    // Shift+Enter は改行を挿入
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Enter のみで送信
                onSubmit()
                return true
            }
            return false
        }

        // MARK: - エモート検出・置換

        /// テキスト末尾のトークンがエモート名と一致する場合、NSTextAttachment で置換する
        ///
        /// - Note: `updateNSView` からもエモートピッカー挿入時に呼ばれるため `private` ではない
        func detectAndReplaceEmote(in textView: NSTextView) {
            let text = textView.string
            // スペース直前のトークンを取り出す
            // 末尾のスペースを除いて、最後のスペースより後ろの文字列がトークン
            let withoutTrailingSpace = String(text.dropLast())
            guard let lastSpaceIndex = withoutTrailingSpace.lastIndex(of: " ") else {
                // スペースがない = テキスト全体がトークン
                let token = withoutTrailingSpace
                tryReplaceToken(token, range: NSRange(location: 0, length: token.utf16.count), in: textView)
                return
            }

            let tokenStart = withoutTrailingSpace.index(after: lastSpaceIndex)
            let token = String(withoutTrailingSpace[tokenStart...])
            guard !token.isEmpty else { return }

            // トークンの NSRange を計算（末尾スペースの手前まで）
            let tokenStartOffset = withoutTrailingSpace.utf16.distance(
                from: withoutTrailingSpace.utf16.startIndex,
                to: tokenStart.samePosition(in: withoutTrailingSpace.utf16)!
            )
            let tokenRange = NSRange(location: tokenStartOffset, length: token.utf16.count)
            tryReplaceToken(token, range: tokenRange, in: textView)
        }

        /// 指定トークンがエモート名なら NSTextAttachment で置換する
        private func tryReplaceToken(_ token: String, range: NSRange, in textView: NSTextView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                // エモート名でストアを検索
                guard let emote = await self.emoteStore.emote(byName: token) else { return }

                // アニメーション版を含むエモート画像を取得する
                // TextKit 2 環境では AnimatedEmoteAttachmentViewProvider が NSImageView で描画するためアニメーションが動く
                guard let image = await EmoteImageCache.shared.image(for: emote.id) else { return }

                // 置換時点での range が有効か確認（ユーザーがその間に編集した可能性がある）
                let textLength = textView.string.utf16.count
                // trailing space も含めた長さで確認
                let endOfToken = range.location + range.length
                guard endOfToken <= textLength else { return }
                // トークン直後がスペースであることを確認
                let nsString = textView.string as NSString
                guard endOfToken < nsString.length,
                      nsString.character(at: endOfToken) == " ".utf16.first else { return }
                // 置換対象範囲（トークン部分のみ）が現在のテキストと一致するか確認
                guard nsString.substring(with: range) == token else { return }

                // NSAttributedString を変更
                // emoteId を渡してアニメーション駆動に必要な情報を保持させる
                let attachment = EmoteTextAttachment(image: image, emoteName: token, emoteId: emote.id)
                // アニメーション版エモートの場合、EmoteAnimationDriver に登録してフレーム更新を開始する
                EmoteAnimationDriver.shared.register(attachment)
                let attachmentString = NSAttributedString(attachment: attachment)

                // フォントを引き継ぐ
                let mutable = NSMutableAttributedString(attributedString: attachmentString)
                let fullRange = NSRange(location: 0, length: mutable.length)
                mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.systemFontSize), range: fullRange)

                // textDidChange の再入を防ぐフラグを立ててから insertText を呼ぶ
                // insertText は layout manager と表示更新を確実にトリガーする推奨 API
                self.isUpdatingFromBinding = true
                textView.insertText(mutable, replacementRange: range)

                // NSTextView のフレーム更新が完了した後でビューポートをレイアウトする。
                // 現在の実行コンテキスト内で呼ぶと NSTextView のフレームがまだ古い状態で
                // アタッチメントビューの位置がずれるため、次のランループで実行する。
                DispatchQueue.main.async { [weak textView] in
                    textView?.textLayoutManager?.textViewportLayoutController.layoutViewport()
                }

                // draft を更新（textDidChange は isUpdatingFromBinding フラグでスキップ済み）
                let plain = EmoteRichTextView.plainText(from: textView.attributedString())
                if self.draft != plain {
                    self.draft = plain
                }
            }
        }
    }
}
