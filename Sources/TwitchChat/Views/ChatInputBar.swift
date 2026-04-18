// ChatInputBar.swift
// コメント投稿用入力バー
// テキスト入力・文字数カウント・送信ボタン・認証状態に応じた UI 切り替えを担当する

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
        HStack(alignment: .bottom, spacing: 8) {
            // エモートピッカーボタン
            Button {
                showEmotePicker.toggle()
            } label: {
                Image(systemName: "face.smiling")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("エモートピッカーを開く")
            .popover(isPresented: $showEmotePicker) {
                EmotePickerView(emoteStore: viewModel.emoteStore) { emoteName in
                    insertEmote(emoteName)
                    showEmotePicker = false
                }
            }
            .disabled(!viewModel.canSendMessage)

            VStack(alignment: .trailing, spacing: 2) {
                // テキストフィールド（複数行対応）
                TextField("コメントを送信", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(.separatorColor), lineWidth: 0.5)
                            )
                    )
                    .disabled(!viewModel.canSendMessage)
                    .onSubmit(submit)

                // 文字数カウンタ（450 文字超で警告）
                if !draft.isEmpty {
                    Text("\(draft.count)/500")
                        .font(.caption2)
                        .foregroundStyle(counterColor)
                        .monospacedDigit()
                }
            }

            // 送信ボタン
            Button(action: submit) {
                if viewModel.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
    }

    // MARK: - ヘルパー

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
}
