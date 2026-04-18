// EmotePickerView.swift
// エモートピッカービュー
// グリッド表示と検索フィルタでエモートを選択し、入力フォームに挿入できるビュー

import AppKit
import SwiftUI

/// エモートピッカービュー
///
/// - グリッド表示: `LazyVGrid` でエモートサムネイルを並べる
/// - 検索フィルタ: テキストフィールドで名前を絞り込む（大文字小文字非区別）
/// - エモートを選択すると `onSelect` コールバックでエモート名を呼び出し元に通知する
struct EmotePickerView: View {

    var onSelect: (String) -> Void

    @State private var viewModel: EmotePickerViewModel

    init(emoteStore: EmoteStore, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self._viewModel = State(initialValue: EmotePickerViewModel(emoteStore: emoteStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 検索バー
            TextField("エモートを検索", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Divider()

            // エモートグリッド
            if viewModel.filteredEmotes.isEmpty {
                Spacer()
                Text("エモートが見つかりません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 4) {
                        ForEach(viewModel.filteredEmotes) { emote in
                            Button {
                                onSelect(emote.name)
                            } label: {
                                EmoteCellView(emoteId: emote.id, emoteName: emote.name)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(emote.name))
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 320, height: 300)
        .task { await viewModel.loadEmotes() }
    }
}

/// エモートセルビュー
///
/// エモート1件分のサムネイルを表示する。
/// - 画像は `EmoteImageCache.shared` を再利用して非同期取得する
/// - アニメーション GIF は `AnimatedEmoteView` で再生する
/// - `isAnimated` フラグは画像取得時にキャッシュし、毎レンダリングで再計算しない
/// - ホバー時のツールチップでエモート名を表示する
private struct EmoteCellView: View {

    let emoteId: String
    let emoteName: String

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
        .help(emoteName)
        .task(id: emoteId) {
            image = await EmoteImageCache.shared.image(for: emoteId)
            isAnimated = EmoteImageCache.shared.isAnimated(emoteId: emoteId)
        }
    }
}
