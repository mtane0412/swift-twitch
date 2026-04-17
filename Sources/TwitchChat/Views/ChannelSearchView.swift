// ChannelSearchView.swift
// blank tab のコンテンツ領域に表示するチャンネル検索フォーム
// フォロー中ライブチャンネルのインクリメンタルサーチ + 任意チャンネル名の直接入力に対応する

import SwiftUI

// MARK: - フィルタロジック

/// チャンネル検索のフィルタロジック
///
/// ビューから独立した純粋関数として定義し、テスト可能にする
enum ChannelSearchFilter {
    /// クエリ文字列でストリーム一覧をフィルタする
    ///
    /// - Parameters:
    ///   - streams: フィルタ対象のストリーム一覧
    ///   - query: 検索クエリ（空またはスペースのみの場合は全件返す）
    /// - Returns: `userLogin` または `userName` がクエリに前方一致するストリーム
    static func filter(streams: [FollowedStream], query: String) -> [FollowedStream] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return streams }
        return streams.filter {
            $0.userLogin.lowercased().hasPrefix(trimmed) ||
            $0.userName.lowercased().hasPrefix(trimmed)
        }
    }
}

// MARK: - ChannelSearchView

/// チャンネル名を入力してチャットを開くための検索フォームビュー
///
/// 使用箇所:
/// - blank tab（タブバーの「+」ボタン押下後）のコンテンツ領域
/// - アプリ起動時にタブが0個の初期状態
///
/// 機能:
/// - フォロー中ライブチャンネルのインクリメンタルサーチ
/// - 入力確定（Enter）でフォロー外チャンネルにも直接接続可能
/// - Escape で blank tab を閉じる（`onCancel` が nil の場合は閉じない）
struct ChannelSearchView: View {

    /// フォロー中ストリーム一覧（インクリメンタルサーチのデータソース）
    let followedStreamStore: FollowedStreamStore
    /// プロフィール画像ストア（候補行のアイコン表示に使用）
    let profileImageStore: ProfileImageStore
    /// チャンネル確定時のコールバック（channelLogin を渡す）
    let onChannelSelected: (String) -> Void
    /// キャンセル時のコールバック（nil の場合はキャンセル不可 = タブ0個時）
    let onCancel: (() -> Void)?

    @State private var searchText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - 定数

    /// TextField の幅
    private static let textFieldWidth: CGFloat = 320
    /// 候補リストの最大表示件数
    private static let maxCandidates: Int = 8
    /// 候補行のアイコンサイズ
    private static let iconSize: CGFloat = 28
    /// ライブ中縁取りの太さ
    private static let liveBorderWidth: CGFloat = 2

    // MARK: - 算出プロパティ

    /// 検索クエリに一致するストリームの候補リスト（最大 maxCandidates 件）
    private var filteredStreams: [FollowedStream] {
        let filtered = ChannelSearchFilter.filter(
            streams: followedStreamStore.streams,
            query: searchText
        )
        return Array(filtered.prefix(Self.maxCandidates))
    }

    /// Enter キーで確定できるかどうか（空文字列以外）
    private var canSubmit: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - ボディ

    var body: some View {
        VStack(spacing: 16) {
            // チャンネル名入力フィールド
            TextField("チャンネル名を入力", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: Self.textFieldWidth)
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitCurrentText()
                }

            // フォロー中チャンネルの候補リスト
            if !filteredStreams.isEmpty {
                VStack(spacing: 0) {
                    ForEach(filteredStreams) { stream in
                        candidateRow(stream: stream)
                    }
                }
                .frame(width: Self.textFieldWidth)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isTextFieldFocused = true
        }
        // Escape キーで blank tab を閉じる
        .onKeyPress(.escape) {
            guard let onCancel else { return .ignored }
            onCancel()
            return .handled
        }
    }

    // MARK: - サブビュー

    /// フォロー中ストリームの候補行
    private func candidateRow(stream: FollowedStream) -> some View {
        Button {
            onChannelSelected(stream.userLogin)
        } label: {
            HStack(spacing: 10) {
                // プロフィールアイコン（ライブ中は赤い縁取り）
                ProfileImageView(
                    userId: stream.userId,
                    imageUrl: profileImageStore.profileImageUrl(for: stream.userId),
                    size: Self.iconSize
                )
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: Self.liveBorderWidth)
                )

                // チャンネル情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.userName)
                        .font(.body)
                        .lineLimit(1)
                    Text(stream.gameName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 視聴者数
                Text(formatViewerCount(stream.viewerCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }

    // MARK: - プライベートメソッド

    /// 現在の入力テキストをチャンネル名として確定する
    private func submitCurrentText() {
        let normalized = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return }
        onChannelSelected(normalized)
    }

    /// 視聴者数を読みやすい形式にフォーマットする
    ///
    /// - 1000未満: そのまま表示
    /// - 1000以上: 「12.3K」形式
    private func formatViewerCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK", k)
        }
        return "\(count)"
    }
}
