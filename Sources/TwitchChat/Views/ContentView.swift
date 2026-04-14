// ContentView.swift
// メインレイアウトビュー
// チャンネル入力エリアとチャットメッセージリストを縦に配置する

import SwiftUI

/// アプリのメインコンテンツビュー
///
/// レイアウト:
/// - 上部: チャンネル名入力 + 接続/切断ボタン（ChannelInputView）
/// - 中央: チャットメッセージリスト（ScrollView + LazyVStack）
/// - エラー時: エラーメッセージを表示
struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @State private var inputChannel: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // チャンネル入力エリア
            ChannelInputView(
                channelName: $inputChannel,
                connectionState: viewModel.connectionState,
                onConnect: {
                    Task {
                        await viewModel.connect(to: inputChannel)
                    }
                },
                onDisconnect: {
                    Task {
                        await viewModel.disconnect()
                    }
                }
            )

            Divider()

            // エラー表示
            if case .error(let message) = viewModel.connectionState {
                Text("エラー: \(message)")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
            }

            // チャットメッセージリスト
            chatListView
        }
        .background(.background)
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
