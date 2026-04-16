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
    var profileImageStore: ProfileImageStore

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
            LoginView(authState: authState, profileImageStore: profileImageStore)
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
                    // 接続中チャンネルはライブリストから除外（接続中セクションに移動済みのため）
                    ForEach(followedStreamStore.streams.filter { !channelManager.channelOrder.contains($0.userLogin) }) { stream in
                        StreamRow(stream: stream, profileImageStore: profileImageStore)
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
        // ストリーム一覧が更新されたら新しい配信者のプロフィール画像を取得する
        // （fetchUsers は取得済みユーザーを内部でフィルタリングするため重複APIコールは発生しない）
        .onChange(of: followedStreamStore.streams) { _, streams in
            let userIds = streams.map(\.userId)
            Task { await profileImageStore.fetchUsers(userIds: userIds) }
        }
        // ログイン時に自分自身のプロフィール画像を取得する
        .onChange(of: authState.userId) { _, userId in
            guard let userId else { return }
            Task { await profileImageStore.fetchUsers(userIds: [userId]) }
        }
        // 起動時にすでにログイン済みの場合のプロフィール画像取得
        .task {
            if let userId = authState.userId {
                await profileImageStore.fetchUsers(userIds: [userId])
            }
        }
    }

    /// 接続中チャンネルの行（コンテキストメニューで切断可能）
    ///
    /// FollowedStreamStore からプロフィール情報を引き、プロフィールアイコン＋接続状態ボーダーで表示する。
    /// フォロー外のチャンネルの場合はプレースホルダーアイコンを表示する。
    @ViewBuilder
    private func connectedChannelRow(channel: String) -> some View {
        let vm = channelManager.channels[channel]
        let stream = followedStreamStore.stream(forUserLogin: channel)
        let userId = stream?.userId
        HStack(spacing: 8) {
            // プロフィールアイコン + 接続状態ボーダー
            ProfileImageView(
                userId: userId ?? channel,
                imageUrl: userId.flatMap { profileImageStore.profileImageUrl(for: $0) }
            )
            .overlay(
                Circle()
                    .stroke(connectionColor(for: vm?.connectionState ?? .disconnected), lineWidth: 2)
            )
            Text(stream?.userName ?? channel)
                .font(.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
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
