// SidebarView.swift
// サイドバービュー
// フォロー中の配信中ストリーマー一覧と接続中チャンネル一覧を表示する

import SwiftUI

/// サイドバービュー
///
/// セクション構成:
/// - ヘッダー: ログイン状態表示（LoginView）
/// - 「接続中」: 現在接続しているチャンネルの一覧（コンテキストメニューで切断可能）
/// - 「ライブ」: フォロー中の配信中ストリーマー一覧（選択でチャット接続）
struct SidebarView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore

    var body: some View {
        List(selection: Binding(
            get: { channelManager.selectedChannel },
            set: { newValue in
                if let channel = newValue {
                    Task { await channelManager.joinChannel(channel) }
                }
            }
        )) {
            // ログイン状態ヘッダー
            LoginView(authState: authState)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            // 接続中チャンネルセクション
            if !channelManager.channelOrder.isEmpty {
                Section("接続中") {
                    ForEach(channelManager.channelOrder, id: \.self) { channel in
                        connectedChannelRow(channel: channel)
                            .tag(channel)
                    }
                }
            }

            // フォロー中ライブセクション
            Section {
                if authState.status == .unknown {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(8)
                        .listRowBackground(Color.clear)
                } else if case .loggedOut = authState.status {
                    Text("ログインしてフォロー中のストリーマーを表示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else if followedStreamStore.isLoading && followedStreamStore.streams.isEmpty {
                    ProgressView("読み込み中...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(8)
                        .listRowBackground(Color.clear)
                } else if followedStreamStore.streams.isEmpty {
                    Text("配信中のフォロー中チャンネルはありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(followedStreamStore.streams) { stream in
                        StreamRow(stream: stream)
                            .tag(stream.userLogin)
                    }
                }
            } header: {
                HStack {
                    Text("ライブ")
                    Spacer()
                    Button {
                        Task { await followedStreamStore.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// 接続中チャンネルの行（コンテキストメニューで切断可能）
    @ViewBuilder
    private func connectedChannelRow(channel: String) -> some View {
        HStack {
            // 接続状態インジケーター
            let vm = channelManager.channels[channel]
            Circle()
                .fill(connectionColor(for: vm?.connectionState ?? .disconnected))
                .frame(width: 8, height: 8)
            Text(channel)
                .font(.body)
            Spacer()
        }
        .contextMenu {
            Button("切断", role: .destructive) {
                Task { await channelManager.leaveChannel(channel) }
            }
        }
    }

    /// 接続状態に対応する色を返す
    private func connectionColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }
}
