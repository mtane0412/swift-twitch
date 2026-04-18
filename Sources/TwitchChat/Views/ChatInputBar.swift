// ChatInputBar.swift
// コメント投稿用入力バー
// テキスト入力・文字数カウント・送信ボタン・認証状態に応じた UI 切り替えを担当する

import AppKit
import SwiftUI

/// コメント投稿用入力バー
///
/// - ログイン済み + chat:edit スコープあり + 接続済みの場合のみ入力可能
/// - Twitch IRC のメッセージ上限（500 文字）をカウントして超過時に警告表示
/// - 送信エラーは 3 秒後に自動クリア
struct ChatInputBar: View {
    var viewModel: ChatViewModel
    var authState: AuthState

    /// 入力テキスト（下書き）
    @State private var draft: String = ""

    /// エモートピッカーの表示状態
    @State private var showEmotePicker = false

    /// @メンション補完の状態管理 ViewModel
    ///
    /// `viewModel.mentionStore` を使って初期化する。
    /// `@State` プロパティは init 引数で初期値を設定することで不要な再作成を防ぐ。
    @State private var mentionCompletionVM: MentionCompletionViewModel

    /// / スラッシュコマンド補完の状態管理 ViewModel
    @State private var slashCommandCompletionVM: SlashCommandCompletionViewModel

    init(viewModel: ChatViewModel, authState: AuthState) {
        self.viewModel = viewModel
        self.authState = authState
        self._mentionCompletionVM = State(
            initialValue: MentionCompletionViewModel(mentionStore: viewModel.mentionStore)
        )
        self._slashCommandCompletionVM = State(
            initialValue: SlashCommandCompletionViewModel()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 認証エラーバナー（chat:edit スコープ不足またはログアウト）
            authBanner

            // 返信先バナー（返信モード中のみ表示）
            if let replyTarget = viewModel.replyingTo {
                replyBanner(target: replyTarget)
            }

            // 入力フォーム（接続中のみ表示、送信不可の場合は disabled）
            if isConnected {
                inputForm
            }
        }
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - サブビュー

    /// 認証状態に応じたバナー
    @ViewBuilder
    private var authBanner: some View {
        switch authState.status {
        case .loggedOut:
            // ログアウト状態: ログインを促すバナー
            HStack {
                Text("コメントを投稿するにはログインしてください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("ログイン") {
                    authState.startLogin()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

        case .loggedIn where !authState.canSendChat:
            // ログイン済みだが chat:edit スコープなし（旧スコープのトークン）
            // 注意: このケースは restoreSession で自動ログアウトされるため通常は表示されない
            HStack {
                Text("コメント投稿には再ログインが必要です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("再ログイン") {
                    Task {
                        await authState.logout()
                        authState.startLogin()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))
            Divider()

        default:
            EmptyView()
        }
    }

    /// 返信先バナー（返信モード中に表示）
    ///
    /// - Parameter target: 返信先の ChatMessage
    private func replyBanner(target: ChatMessage) -> some View {
        HStack {
            Image(systemName: "arrowshape.turn.up.left")
                .foregroundStyle(.secondary)
            Text("\(target.displayName) に返信中")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// テキスト入力フォーム
    private var inputForm: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // エモートピッカーボタン（丸い円形ボタン）
            Button {
                showEmotePicker.toggle()
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .modifier(CircularIconBackground(backgroundColor: Color(.controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("エモートピッカーを開く")
            .popover(isPresented: $showEmotePicker, arrowEdge: .bottom) {
                EmotePickerView(emoteStore: viewModel.emoteStore) { emoteName in
                    insertEmote(emoteName)
                    showEmotePicker = false
                }
            }
            .disabled(!viewModel.canSendMessage)

            // リッチテキスト入力欄（カプセル型）
            EmoteRichTextView(
                draft: $draft,
                emoteStore: viewModel.emoteStore,
                onSubmit: submit,
                isDisabled: !viewModel.canSendMessage,
                mentionCompletionViewModel: mentionCompletionVM,
                slashCommandCompletionViewModel: slashCommandCompletionVM
            )
            .frame(height: Self.inputFieldHeight)
            .padding(.leading, 14)
            // 文字数カウンタ（幅 約 50pt）が表示中は trailing に余白を確保して重なりを防ぐ
            .padding(.trailing, draft.isEmpty ? 14 : 60)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(.separatorColor), lineWidth: 0.5)
                    )
            )
            // 文字数カウンタ（450 文字超で警告、入力フィールド内右下に表示）
            .overlay(alignment: .bottomTrailing) {
                if !draft.isEmpty {
                    Text("\(draft.count)/500")
                        .font(.caption2)
                        .foregroundStyle(counterColor)
                        .monospacedDigit()
                        .padding(.trailing, 10)
                        .padding(.bottom, 4)
                }
            }

            // 送信ボタン（丸い円形ボタン）
            Button(action: submit) {
                if viewModel.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .modifier(CircularIconBackground(backgroundColor: Color(.controlBackgroundColor)))
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(canSubmit ? .white : .secondary)
                        .modifier(CircularIconBackground(
                            backgroundColor: canSubmit ? Color.accentColor : Color(.controlBackgroundColor),
                            showBorder: !canSubmit
                        ))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("送信")
            .accessibilityValue(viewModel.isSending ? "送信中" : (canSubmit ? "" : "無効"))
            .accessibilityHint(
                viewModel.isSending
                    ? "コメントを送信しています"
                    : (canSubmit ? "コメントを送信します" : "コメントを送信できません。入力内容または接続状態を確認してください")
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // 送信エラー表示
        .overlay(alignment: .topLeading) {
            if let error = viewModel.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .offset(y: -20)
                    .task(id: viewModel.sendError) {
                        // 3 秒後にエラーを自動クリア
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        viewModel.clearSendError()
                    }
                    .id(error)
            }
        }
        // / スラッシュコマンド補完ドロップダウン（入力バーの上に表示、@メンション補完と排他的）
        // slashCommandCompletionVM.isActive が true の場合 mentionCompletionVM は必ず非アクティブだが、
        // ビュー層でも明示的に排他制御して安全性を高める
        .overlay(alignment: .top) {
            if slashCommandCompletionVM.isActive && !slashCommandCompletionVM.candidates.isEmpty
                && !mentionCompletionVM.isActive {
                SlashCommandCompletionView(
                    candidates: slashCommandCompletionVM.candidates,
                    selectedIndex: slashCommandCompletionVM.selectedIndex
                ) { index in
                    confirmSlashCommandCandidate(at: index)
                }
                .fixedSize(horizontal: false, vertical: true)
                // listHeight(for:) を使って Divider 高さも含んだ正確なオフセットを計算する
                .offset(y: -SlashCommandCompletionView.listHeight(for: slashCommandCompletionVM.candidates.count))
            }
        }
        // @メンション補完ドロップダウン（入力バーの上に表示、スラッシュ補完と排他的）
        .overlay(alignment: .top) {
            if mentionCompletionVM.isActive && !mentionCompletionVM.candidates.isEmpty
                && !slashCommandCompletionVM.isActive {
                MentionCompletionView(
                    candidates: mentionCompletionVM.candidates,
                    selectedIndex: mentionCompletionVM.selectedIndex
                ) { index in
                    confirmMentionCandidate(at: index)
                }
                .fixedSize(horizontal: false, vertical: true)
                // listHeight(for:) を使って Divider 高さも含んだ正確なオフセットを計算する
                .offset(y: -MentionCompletionView.listHeight(for: mentionCompletionVM.candidates.count))
            }
        }
    }

    // MARK: - ヘルパー

    /// TextKit のデフォルト行高とインライン emote の高さを考慮した1行分の入力フィールド高さを計算する
    ///
    /// - `NSLayoutManager.defaultLineHeight` を使用して leading を含む実際の行高を取得する
    /// - インライン emote（`EmoteImageCache.emoteDisplaySize` = 20pt）がテキスト行高を超える場合は emote 高さを優先する
    /// - 上下インセット各 3pt を加算した値。EmoteRichTextView の textContainerInset（verticalInset）と連動する
    private static let inputFieldHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let layoutManager = NSLayoutManager()
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        let contentHeight = max(lineHeight, EmoteImageCache.emoteDisplaySize)
        return contentHeight + 6  // 上下インセット各 3pt
    }()

    /// 接続中かどうか（入力フォームの表示判定用）
    private var isConnected: Bool {
        viewModel.connectionState == .connected
    }

    /// 送信可能かどうか（ボタン有効化条件）
    private var canSubmit: Bool {
        viewModel.canSendMessage
            && !viewModel.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= 500
    }

    /// 文字数カウンタの色
    private var counterColor: Color {
        if draft.count > 500 { return .red }
        if draft.count > 450 { return .yellow }
        return .secondary
    }

    /// エモート名を draft に挿入する
    ///
    /// Twitch IRC ではエモートはスペース区切りで認識されるため、
    /// 前後に空白を入れてエモート名を挿入する。
    /// 空のエモート名は挿入しない。
    private func insertEmote(_ emoteName: String) {
        guard !emoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if draft.isEmpty || (draft.last?.isWhitespace == true) {
            draft += emoteName + " "
        } else {
            draft += " " + emoteName + " "
        }
    }

    /// メッセージを送信する
    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        Task {
            try? await viewModel.sendMessage(text)
        }
    }

    /// クリックで / スラッシュコマンド候補を選択確定する
    ///
    /// - Parameter index: 選択した候補のインデックス
    private func confirmSlashCommandCandidate(at index: Int) {
        slashCommandCompletionVM.setSelection(to: index)
        // commandRange は confirmSelection() の前に取得する（確定後に nil になるため）
        let range = slashCommandCompletionVM.commandRange
        guard let insertion = slashCommandCompletionVM.confirmSelection() else { return }

        // draft の / トークン部分を挿入文字列で置換する
        if let range {
            let nsString = draft as NSString
            draft = nsString.replacingCharacters(in: range, with: insertion)
        } else {
            draft += insertion
        }
    }

    /// クリックで @メンション候補を選択確定する
    ///
    /// - Parameter index: 選択した候補のインデックス
    private func confirmMentionCandidate(at index: Int) {
        mentionCompletionVM.setSelection(to: index)
        // mentionRange は confirmSelection() の前に取得する（確定後に nil になるため）
        let range = mentionCompletionVM.mentionRange
        guard let insertion = mentionCompletionVM.confirmSelection() else { return }

        // draft の @ トークン部分を挿入文字列で置換する
        // draft はプレーンテキストなので NSString で直接置換できる
        if let range {
            let nsString = draft as NSString
            draft = nsString.replacingCharacters(in: range, with: insertion)
        } else {
            draft += insertion
        }
    }

}

// MARK: - CircularIconBackground

/// 円形背景付きアイコンのスタイルを適用する ViewModifier
///
/// エモートピッカーボタン・送信ボタンに共通して使用する 28×28pt の円形スタイルを提供する。
private struct CircularIconBackground: ViewModifier {
    /// 背景の塗りつぶし色
    var backgroundColor: Color
    /// 境界線を表示するかどうか
    var showBorder: Bool = true

    func body(content: Content) -> some View {
        content
            .frame(width: 28, height: 28)
            .background(Circle().fill(backgroundColor))
            .overlay {
                if showBorder {
                    Circle().stroke(Color(.separatorColor), lineWidth: 0.5)
                }
            }
    }
}
