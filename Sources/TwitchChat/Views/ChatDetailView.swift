// ChatDetailView.swift
// チャット詳細ペイン
// 選択中チャンネルのメッセージリスト・エラー表示・コメント入力バーを担当する

import SwiftUI

/// 選択中チャンネルのチャット詳細ペイン
///
/// - エラー時はエラーメッセージを表示
/// - チャットメッセージを ScrollView + LazyVStack で表示
/// - 新メッセージ到着時に自動スクロール
/// - 下部にコメント投稿用入力バーを表示
struct ChatDetailView: View {
    var viewModel: ChatViewModel
    var authState: AuthState

    var body: some View {
        VStack(spacing: 0) {
            // エラー表示
            if case .error(let message) = viewModel.connectionState {
                Text("エラー: \(message)")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
                Divider()
            }

            // チャットメッセージリスト
            chatListView

            // コメント投稿用入力バー
            Divider()
            ChatInputBar(viewModel: viewModel, authState: authState)
        }
        // タブバーのアクティブタブ色（controlBackgroundColor）と一致させる
        .background(Color(.controlBackgroundColor))
    }

    /// チャットメッセージのスクロールビュー
    private var chatListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageView(message: message, badgeStore: viewModel.badgeStore)
                            .id(message.id)
                            .contextMenu {
                                // 楽観的UIメッセージ（自分が送信した未確認メッセージ）には返信不可
                                // Twitch サーバーが認識する本物の message ID を持たないため
                                if viewModel.canSendMessage && !message.isOptimistic {
                                    Button {
                                        viewModel.startReply(to: message)
                                    } label: {
                                        Label("返信", systemImage: "arrowshape.turn.up.left")
                                    }
                                }
                            }
                    }
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                // 新しいメッセージが届いたら最下部にスクロール
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
}
