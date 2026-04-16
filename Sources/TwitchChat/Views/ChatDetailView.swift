// ChatDetailView.swift
// チャット詳細ペイン
// 選択中チャンネルのメッセージリストとエラー表示を担当する

import SwiftUI

/// 選択中チャンネルのチャット詳細ペイン
///
/// - エラー時はエラーメッセージを表示
/// - チャットメッセージを ScrollView + LazyVStack で表示
/// - 新メッセージ到着時に自動スクロール
struct ChatDetailView: View {
    var viewModel: ChatViewModel

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
