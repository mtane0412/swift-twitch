// ChatDetailView.swift
// チャット詳細ペイン
// 選択中チャンネルのメッセージリスト・エラー表示・コメント入力バーを担当する
// livePlayerEnabled が true のとき上部に 16:9 固定比率のプレイヤーを表示する

import SwiftUI

/// 選択中チャンネルのチャット詳細ペイン
///
/// - エラー時はエラーメッセージを表示
/// - livePlayerEnabled が true のとき上部に 16:9 固定比率の StreamPlayerView を表示
/// - チャットメッセージを ScrollView + LazyVStack で表示
/// - 新メッセージ到着時に自動スクロール
/// - 下部にコメント投稿用入力バーを表示
struct ChatDetailView: View {
    var viewModel: ChatViewModel
    var authState: AuthState
    /// プロフィール画像・表示名ストア（エモートピッカーのセクションヘッダー用）
    var profileImageStore: ProfileImageStore
    /// ライブプレイヤー ViewModel（nil の場合はプレイヤーを表示しない）
    var streamPlayer: StreamPlayerViewModel?

    /// ライブ配信プレイヤー機能の有効・無効（SettingsView から変更可能）
    @AppStorage(AppStorageKeys.livePlayerEnabled) private var livePlayerEnabled = false

    /// プレイヤー横幅（onGeometryChange で計測）
    @State private var playerWidth: CGFloat = 0
    /// コンテナ（VStack 全体）高さ（playerHeight の上限算出に使用）
    @State private var containerHeight: CGFloat = 0

    /// 16:9 比率かつコンテナの 65% 以下に制限したプレイヤー高さ
    ///
    /// 横幅フルの 16:9 をそのまま使うと横長ウィンドウでチャット領域が潰れるため、
    /// コンテナ高さの 65% を上限としてチャットエリアを確保する。
    private var playerHeight: CGFloat {
        guard playerWidth > 0, containerHeight > 0 else { return 0 }
        return min(playerWidth * 9 / 16, containerHeight * 0.65)
    }

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

            // livePlayerEnabled かつ streamPlayer がある場合は横幅フル・16:9 高さでプレイヤーを上部表示
            // aspectRatio(contentMode: .fit) は VStack の高さ制約に負けて幅が縮むため、
            // onGeometryChange で横幅を計測して高さを明示的に設定する
            if livePlayerEnabled, let streamPlayer {
                StreamPlayerView(viewModel: streamPlayer)
                    .frame(maxWidth: .infinity)
                    .frame(height: playerHeight > 0 ? playerHeight : nil)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if newWidth != playerWidth { playerWidth = newWidth }
                    }
                Divider()
                chatListView
            } else {
                // チャットのみ表示（既存挙動）
                chatListView
            }

            // コメント投稿用入力バー
            Divider()
            ChatInputBar(viewModel: viewModel, authState: authState, profileImageStore: profileImageStore)
        }
        // タブバーのアクティブタブ色（controlBackgroundColor）と一致させる
        .background(Color(.controlBackgroundColor))
        // VStack 全体の高さを追跡し、playerHeight の上限計算に使う
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if newHeight != containerHeight { containerHeight = newHeight }
        }
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
