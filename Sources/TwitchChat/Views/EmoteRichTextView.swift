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

    /// @メンション補完の状態管理 ViewModel
    var mentionCompletionViewModel: MentionCompletionViewModel

    /// / スラッシュコマンド補完の状態管理 ViewModel
    var slashCommandCompletionViewModel: SlashCommandCompletionViewModel

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
        Coordinator(
            draft: $draft,
            emoteStore: emoteStore,
            onSubmit: onSubmit,
            mentionCompletionViewModel: mentionCompletionViewModel,
            slashCommandCompletionViewModel: slashCommandCompletionViewModel
        )
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
        // 縦方向は固定（1行固定高さ）、テキストコンテナの高さをビュー高さに追従させる
        textView.isVerticallyResizable = false
        textView.textContainer?.heightTracksTextView = true
        // TextKit の標準行高とインライン emote の高さを考慮してインセットを計算し縦方向に中央揃えにする
        // ChatInputBar.inputFieldHeight（contentHeight + 6）と連動しているため、この計算式を変更する場合は両方を更新すること
        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let defaultLineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? font.boundingRectForFont.height
        let contentHeight = ceil(max(defaultLineHeight, EmoteImageCache.emoteDisplaySize))
        let fieldHeight = contentHeight + 6  // 上下インセット各 3pt（inputFieldHeight と一致）
        let verticalInset = max(0, floor((fieldHeight - contentHeight) / 2))
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)
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

    /// NSTextView の UTF-16 カーソル位置を plainText 上の文字数インデックスに変換する
    ///
    /// エモートアタッチメントが存在する場合、NSTextView 上では1文字（U+FFFC）だが
    /// plainText ではエモート名の文字数分になるためオフセットのずれが生じる。
    /// この変換を行うことで `MentionCompletionViewModel.updateFromText` に正確な
    /// カーソル位置を渡せる。
    ///
    /// - Parameters:
    ///   - nsViewOffset: NSTextView の selectedRange().location（UTF-16 オフセット）
    ///   - attributedString: NSTextView の現在の attributedString
    /// - Returns: plainText 上の文字数インデックス
    static func plainTextCursorPosition(from nsViewOffset: Int, in attributedString: NSAttributedString) -> Int {
        var plainOffset = 0
        var nsOffset = 0

        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attrs, range, stop in
            guard nsOffset < nsViewOffset else {
                stop.pointee = true
                return
            }

            if let attachment = attrs[.attachment] as? EmoteTextAttachment {
                // アタッチメントは NSTextView 上では range.length (通常1) 、plainText ではエモート名の長さ
                let remaining = nsViewOffset - nsOffset
                plainOffset += attachment.emoteName.count
                nsOffset += range.length
                if remaining < range.length {
                    stop.pointee = true
                }
            } else {
                let segmentNSLen = range.length
                let remaining = nsViewOffset - nsOffset
                let partRange = NSRange(location: range.location, length: min(remaining, segmentNSLen))
                let partStr = (attributedString.string as NSString).substring(with: partRange)
                plainOffset += partStr.count
                nsOffset += partRange.length
                if remaining < segmentNSLen {
                    stop.pointee = true
                }
            }
        }

        return plainOffset
    }

    /// plainText 上の NSRange（Character 数基準）を NSTextView の NSRange（UTF-16 オフセット）に変換する
    ///
    /// `replaceMentionToken` で `NSTextView.insertText(_:replacementRange:)` に渡す範囲を
    /// plainText 座標から NSTextView 座標に変換するために使用する。
    ///
    /// - Parameters:
    ///   - plainRange: plainText 上の NSRange（Character 数基準）
    ///   - attributedString: NSTextView の現在の attributedString
    /// - Returns: NSTextView 座標の NSRange（UTF-16 オフセット）
    static func nsViewRange(from plainRange: NSRange, in attributedString: NSAttributedString) -> NSRange {
        let startNS = nsViewOffset(for: plainRange.location, in: attributedString)
        let endNS = nsViewOffset(for: plainRange.location + plainRange.length, in: attributedString)
        return NSRange(location: startNS, length: endNS - startNS)
    }

    /// plainText 上の Character インデックスを NSTextView の UTF-16 オフセットに変換する
    ///
    /// - Parameters:
    ///   - plainCharIndex: plainText 上の Character 数インデックス
    ///   - attributedString: NSTextView の現在の attributedString
    /// - Returns: NSTextView の UTF-16 オフセット
    private static func nsViewOffset(for plainCharIndex: Int, in attributedString: NSAttributedString) -> Int {
        var nsOffset = 0
        var plainOffset = 0

        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { attrs, range, stop in
            guard plainOffset < plainCharIndex else {
                stop.pointee = true
                return
            }

            if let attachment = attrs[.attachment] as? EmoteTextAttachment {
                let emoteLen = attachment.emoteName.count
                if plainOffset + emoteLen <= plainCharIndex {
                    plainOffset += emoteLen
                    nsOffset += range.length
                } else {
                    // インデックスがアタッチメント内 → アタッチメント末尾にスナップ
                    nsOffset += range.length
                    plainOffset = plainCharIndex
                    stop.pointee = true
                }
            } else {
                let segmentStr = (attributedString.string as NSString).substring(with: range)
                let segmentCharLen = segmentStr.count
                let remaining = plainCharIndex - plainOffset
                if remaining >= segmentCharLen {
                    plainOffset += segmentCharLen
                    nsOffset += range.length
                } else {
                    // インデックスがこのテキストセグメント内
                    let partStr = String(segmentStr.prefix(remaining))
                    plainOffset = plainCharIndex
                    nsOffset += partStr.utf16.count
                    stop.pointee = true
                }
            }
        }

        return nsOffset
    }

    // MARK: - Coordinator

    /// NSTextViewDelegate を実装し、エモート検出・置換・draft 更新を担当する
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {

        @Binding var draft: String
        let emoteStore: EmoteStore
        let onSubmit: () -> Void
        let mentionCompletionViewModel: MentionCompletionViewModel
        let slashCommandCompletionViewModel: SlashCommandCompletionViewModel

        /// binding 側からのリセット中フラグ（無限ループ防止）
        var isUpdatingFromBinding = false

        /// アニメーションフレーム更新通知のオブザーバートークン
        ///
        /// `dismantleNSView`（MainActor）で `unsubscribeFromFrameUpdates()` を呼ぶため
        /// `nonisolated(unsafe)` は不要。プロパティは常に MainActor 上でアクセスされる。
        private var frameUpdateObserver: NSObjectProtocol?

        init(
            draft: Binding<String>,
            emoteStore: EmoteStore,
            onSubmit: @escaping () -> Void,
            mentionCompletionViewModel: MentionCompletionViewModel,
            slashCommandCompletionViewModel: SlashCommandCompletionViewModel
        ) {
            self._draft = draft
            self.emoteStore = emoteStore
            self.onSubmit = onSubmit
            self.mentionCompletionViewModel = mentionCompletionViewModel
            self.slashCommandCompletionViewModel = slashCommandCompletionViewModel
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

            // NSTextView の UTF-16 カーソル位置を plainText の文字数インデックスに変換して渡す
            let nsViewOffset = textView.selectedRange().location
            let plainCursorPosition = EmoteRichTextView.plainTextCursorPosition(
                from: nsViewOffset,
                in: textView.attributedString()
            )

            // スラッシュコマンド補完を先に更新する（テキスト先頭 / の場合のみアクティブ化）
            slashCommandCompletionViewModel.updateFromText(plain, cursorPosition: plainCursorPosition)

            // スラッシュ補完がアクティブな場合はメンション補完をスキップする（排他制御）
            if !slashCommandCompletionViewModel.isActive {
                mentionCompletionViewModel.updateFromText(plain, cursorPosition: plainCursorPosition)
            } else {
                mentionCompletionViewModel.cancel()
            }
        }

        /// Enter / Shift+Enter で送信、補完アクティブ時は上下キー・Esc も処理する
        ///
        /// - Note: 入力欄は1行固定高さのため、Shift+Enter による改行挿入は無効化している。
        ///   改行を挿入しても表示領域外にクリップされるだけで混乱を招くため、両キーで送信する。
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // スラッシュコマンド補完が優先（テキスト先頭 / のケース）
            if slashCommandCompletionViewModel.isActive,
               let handled = handleCompletionCommand(
                commandSelector,
                confirm: {
                    guard let range = slashCommandCompletionViewModel.commandRange,
                          let insertion = slashCommandCompletionViewModel.confirmSelection()
                    else { return nil }
                    return (insertion, range)
                },
                cancel: { slashCommandCompletionViewModel.cancel() },
                move: { slashCommandCompletionViewModel.moveSelection(by: $0) },
                replace: { replaceSlashCommandToken(with: $0, range: $1, in: textView) }
               ) { return handled }

            // @メンション補完
            if mentionCompletionViewModel.isActive,
               let handled = handleCompletionCommand(
                commandSelector,
                confirm: {
                    guard let range = mentionCompletionViewModel.mentionRange,
                          let insertion = mentionCompletionViewModel.confirmSelection()
                    else { return nil }
                    return (insertion, range)
                },
                cancel: { mentionCompletionViewModel.cancel() },
                move: { mentionCompletionViewModel.moveSelection(by: $0) },
                replace: { replaceMentionToken(with: $0, range: $1, in: textView) }
               ) { return handled }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter / Shift+Enter いずれも送信（1行固定のため改行を許可しない）
                onSubmit()
                return true
            }
            return false
        }

        /// 補完共通のキーボードコマンドを処理する
        ///
        /// 上下移動・Esc・Enter/Tab を処理して `Bool?` を返す。
        /// 処理した場合は `true`/`false`、処理対象外のセレクタは `nil` を返す。
        ///
        /// - Parameters:
        ///   - commandSelector: NSTextView から渡されるセレクタ
        ///   - confirm: 候補を確定する処理（確定文字列と置換範囲のタプル、または nil を返す）
        ///   - cancel: 補完をキャンセルする処理
        ///   - move: 選択インデックスを移動する処理（引数は offset）
        ///   - replace: テキストを置換する処理
        private func handleCompletionCommand(
            _ commandSelector: Selector,
            confirm: () -> (String, NSRange)?,
            cancel: () -> Void,
            move: (Int) -> Void,
            replace: (String, NSRange) -> Void
        ) -> Bool? {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                move(-1); return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                move(1); return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancel(); return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let (insertion, range) = confirm() {
                    replace(insertion, range)
                } else {
                    cancel()
                    onSubmit()
                }
                return true
            }
            return nil
        }

        /// / スラッシュコマンドトークンを補完候補で置換し draft を更新する
        ///
        /// - Parameters:
        ///   - insertion: 挿入する文字列（`/command ` 形式）
        ///   - range: テキスト内の置換対象範囲（/ から現在クエリ末尾まで）
        ///   - textView: 対象の NSTextView
        private func replaceSlashCommandToken(with insertion: String, range: NSRange, in textView: NSTextView) {
            let nsRange = EmoteRichTextView.nsViewRange(from: range, in: textView.attributedString())
            let nsString = textView.string as NSString
            guard nsRange.location <= nsString.length,
                  nsRange.location + nsRange.length <= nsString.length else { return }

            isUpdatingFromBinding = true
            textView.insertText(insertion, replacementRange: nsRange)

            let plain = EmoteRichTextView.plainText(from: textView.attributedString())
            if draft != plain {
                draft = plain
            }
        }

        /// @メンショントークンを補完候補で置換し draft を更新する
        ///
        /// - Parameters:
        ///   - insertion: 挿入する文字列（`@username ` 形式）
        ///   - range: テキスト内の置換対象範囲（@ から現在クエリ末尾まで）
        ///   - textView: 対象の NSTextView
        private func replaceMentionToken(with insertion: String, range: NSRange, in textView: NSTextView) {
            // mentionRange は plainText 座標（Character 数）で保持されているため
            // NSTextView.insertText の replacementRange に渡す前に UTF-16 座標に変換する
            let nsRange = EmoteRichTextView.nsViewRange(from: range, in: textView.attributedString())
            let nsString = textView.string as NSString
            guard nsRange.location <= nsString.length,
                  nsRange.location + nsRange.length <= nsString.length else { return }

            isUpdatingFromBinding = true
            textView.insertText(insertion, replacementRange: nsRange)

            // draft を更新
            let plain = EmoteRichTextView.plainText(from: textView.attributedString())
            if draft != plain {
                draft = plain
            }
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
