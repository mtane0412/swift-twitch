// SidebarView.swift
// サイドバービュー
// フォロー中の配信中ストリーマー一覧を表示する（接続中チャンネルは先頭に並ぶ）

import SwiftUI

/// サイドバービュー
///
/// セクション構成:
/// - ヘッダー: ログイン状態表示（LoginView）
/// - 「ライブ」: フォロー中の配信中ストリーマー一覧
///   - 接続中チャンネルはリスト先頭に表示し、選択中タブと選択状態が連動する
struct SidebarView: View {
    var authState: AuthState
    var channelManager: ChannelManager
    var followedStreamStore: FollowedStreamStore
    var profileImageStore: ProfileImageStore
    /// blank tab の開閉状態（サイドバーからチャンネル選択時に blank tab を閉じるために使用）
    @Binding var isBlankTabOpen: Bool

    var body: some View {
        List(selection: Binding(
            get: { channelManager.selectedChannel },
            set: { newValue in
                guard let channel = newValue else { return }
                // サイドバーからの選択で blank tab を閉じる
                isBlankTabOpen = false
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
                    // 接続中チャンネルを先頭に並べる（各グループ内は元の順序を維持）
                    let connectedSet = Set(channelManager.channelOrder)
                    let connectedStreams = followedStreamStore.streams.filter {
                        connectedSet.contains($0.userLogin.lowercased())
                    }
                    let otherStreams = followedStreamStore.streams.filter {
                        !connectedSet.contains($0.userLogin.lowercased())
                    }
                    let sortedStreams = connectedStreams + otherStreams
                    ForEach(sortedStreams) { stream in
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
