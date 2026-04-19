// EmotePickerView.swift
// エモートピッカービュー
// グリッド表示・チャンネルごとのセクション・検索フィルタでエモートを選択し入力フォームに挿入できるビュー

import AppKit
import SwiftUI

/// エモートピッカービュー
///
/// - セクション表示: チャンネルごとにエモートをグループ化し、ヘッダーにアイコン＋名前を表示する
/// - グリッド表示: `LazyVGrid` でエモートサムネイルを並べる
/// - 検索フィルタ: テキストフィールドで名前を絞り込む（大文字小文字非区別・全セクション横断）
/// - エモートを選択すると `onSelect` コールバックでエモート名を呼び出し元に通知する
struct EmotePickerView: View {

    var onSelect: (String) -> Void

    @State private var viewModel: EmotePickerViewModel

    /// プロフィール画像・表示名ストア（セクションヘッダーのアイコン表示に使用）
    var profileImageStore: ProfileImageStore

    init(
        emoteStore: EmoteStore,
        profileImageStore: ProfileImageStore,
        currentBroadcasterId: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.onSelect = onSelect
        self.profileImageStore = profileImageStore
        self._viewModel = State(initialValue: EmotePickerViewModel(
            emoteStore: emoteStore,
            profileImageStore: profileImageStore,
            currentBroadcasterId: currentBroadcasterId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            TextField("エモートを検索", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            // エモートグリッド（セクション分け）
            if viewModel.filteredSections.isEmpty {
                Spacer()
                Text("エモートが見つかりません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.filteredSections) { section in
                            Section {
                                ForEach(section.emotes) { emote in
                                    let available = viewModel.isAvailable(emote)
                                    Button {
                                        onSelect(emote.name)
                                    } label: {
                                        EmoteCellView(emoteId: emote.id, emoteName: emote.name, isAvailable: available)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!available)
                                    .accessibilityLabel(Text(emote.name))
                                    .accessibilityValue(available ? "" : "使用不可")
                                }
                            } header: {
                                EmoteSectionHeader(section: section, profileImageStore: profileImageStore)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 320, height: 380)
        .task { await viewModel.loadEmotes() }
        // ピッカー表示中に USERSTATE が届いた場合の使用可否リアルタイム更新
        .task { await viewModel.observeUserEmoteSetsUpdates() }
    }
}

/// エモートセクションヘッダービュー
///
/// チャンネルアイコン（ProfileImageStore から取得）とセクション名を横並びに表示する。
/// グローバル・HYPE・その他セクションはアイコンなし。
private struct EmoteSectionHeader: View {

    let section: EmotePickerSection
    let profileImageStore: ProfileImageStore

    var body: some View {
        HStack(spacing: 4) {
            // チャンネルアイコン（currentChannel / subscribedChannel のみ表示）
            if let userId = section.iconUserId,
               let iconUrl = profileImageStore.profileImageUrl(for: userId) {
                AsyncImage(url: iconUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .frame(width: 14, height: 14)
                .clipShape(Circle())
            }

            Text(section.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.windowBackgroundColor))
    }
}

/// エモートセルビュー
///
/// エモート1件分のサムネイルを表示する。
/// - 画像は `EmoteImageCache.shared` を再利用して非同期取得する
/// - アニメーション GIF は `AnimatedEmoteView` で再生する
/// - `isAnimated` フラグは画像取得時にキャッシュし、毎レンダリングで再計算しない
/// - `isAvailable` が false の場合は半透明表示し、右下にロックアイコンを重ねる
/// - ホバー時のツールチップでエモート名（使用不可時はサブスク必要の旨）を表示する
private struct EmoteCellView: View {

    let emoteId: String
    let emoteName: String
    let isAvailable: Bool

    @State private var image: NSImage?
    @State private var isAnimated: Bool = false

    var body: some View {
        Group {
            if let image {
                if isAnimated {
                    AnimatedEmoteView(image: image, isAnimated: isAnimated, size: 28)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
            } else {
                // 読み込み中はプログレスインジケータを表示
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            }
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        // 使用不可エモートは半透明でグレーアウト表示する
        .opacity(isAvailable ? 1.0 : 0.35)
        // 使用不可エモートは右下にロックアイコンを表示してサブスク必要を示す
        .overlay(alignment: .bottomTrailing) {
            if !isAvailable {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .help(isAvailable ? emoteName : "\(emoteName)（サブスクライブが必要です）")
        .task(id: emoteId) {
            image = await EmoteImageCache.shared.image(for: emoteId)
            isAnimated = EmoteImageCache.shared.isAnimated(emoteId: emoteId)
        }
    }
}
