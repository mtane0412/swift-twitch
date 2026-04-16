// SidebarView.swift
// サイドバービュー
// フォロー中の配信中ストリーマー一覧と、接続中チャンネルのアイコン横並びを表示する

import SwiftUI

/// サイドバービュー
///
/// セクション構成:
/// - ヘッダー: ログイン状態表示（LoginView）
/// - 「ライブ」: 接続中チャンネルのアイコン横並び + フォロー中の配信中ストリーマー一覧
///   - 接続中チャンネルはリストから除外し、アイコンストリップのみで表示する
struct SidebarView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore
    var profileImageStore: ProfileImageStore

    var body: some View {
        List(selection: Binding(
            get: { channelManager.selectedChannel },
            set: { newValue in
                guard let channel = newValue else { return }
                if channelManager.isJoined(channel) {
                    // 既接続: 選択のみ切り替え（再接続させない）
                    channelManager.selectChannel(channel)
                } else {
                    // 未接続: 新規接続
                    Task { await channelManager.joinChannel(channel) }
                }
            }
        )) {
            // ログイン状態ヘッダー
            LoginView(authState: authState, profileImageStore: profileImageStore)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            // フォロー中ライブセクション
            Section {
                // 接続中チャンネルのアイコン横並び（セクション先頭に表示）
                if !channelManager.channelOrder.isEmpty {
                    ConnectedChannelIconStrip(
                        channelManager: channelManager,
                        followedStreamStore: followedStreamStore,
                        profileImageStore: profileImageStore
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.clear)
                    .selectionDisabled(true)
                }

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
                    // 接続中チャンネルはアイコンストリップで表示済みのため、ライブリストから除外する
                    let connectedChannels = Set(channelManager.channelOrder)
                    ForEach(followedStreamStore.streams.filter { !connectedChannels.contains($0.userLogin.lowercased()) }) { stream in
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
}
