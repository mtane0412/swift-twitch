// ChannelSearchView.swift
// blank tab のコンテンツ領域に表示するチャンネル検索フォーム
// フォロー中チャンネルのインクリメンタルサーチ + 0件時は /helix/search/channels にフォールバックする

import SwiftUI

// MARK: - フィルタロジック

/// チャンネル検索のフィルタロジック
///
/// ビューから独立した純粋関数として定義し、テスト可能にする
enum ChannelSearchFilter {
    /// クエリ文字列でフォロー済みチャンネル一覧をフィルタする
    ///
    /// - Parameters:
    ///   - channels: フィルタ対象のチャンネル一覧
    ///   - query: 検索クエリ（空またはスペースのみの場合は空配列を返す）
    /// - Returns: `broadcasterLogin` または `broadcasterName` がクエリに前方一致するチャンネル
    static func filter(channels: [FollowedChannel], query: String) -> [FollowedChannel] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return channels.filter {
            $0.broadcasterLogin.lowercased().hasPrefix(trimmed) ||
            $0.broadcasterName.lowercased().hasPrefix(trimmed)
        }
    }
}

// MARK: - キーボードナビゲーションロジック

/// 候補リストのキーボードナビゲーションロジック
///
/// ビューから独立した純粋関数として定義し、テスト可能にする
enum CandidateNavigator {
    /// 現在のインデックスから1つ下（次）の候補に移動する
    ///
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - count: 候補の総件数
    /// - Returns: 末尾を超えない次のインデックス（末尾ではクランプ）
    static func nextIndex(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(current + 1, count - 1)
    }

    /// 現在のインデックスから1つ上（前）の候補に移動する
    ///
    /// - Parameters:
    ///   - current: 現在の選択インデックス
    ///   - count: 候補の総件数
    /// - Returns: 先頭を下回らない前のインデックス（先頭ではクランプ）
    ///
    /// - Note: 候補数が減少して `current` が `count-1` を超えた場合も正しく末尾にクランプする
    static func previousIndex(current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(current, count - 1)
        return max(clamped - 1, 0)
    }
}

// MARK: - ChannelSearchView

/// チャンネル名を入力してチャットを開くための検索フォームビュー
///
/// 使用箇所:
/// - blank tab（タブバーの「+」ボタン押下後）のコンテンツ領域
/// - アプリ起動時にタブが0個の初期状態
///
/// 候補表示の優先順位:
/// 1. フォロー中チャンネル（`FollowedChannelStore.channels` を前方一致でフィルタ）
/// 2. フォロー中0件かつ入力あり → `/helix/search/channels` の検索結果（300ms デバウンス）
///
/// ライブ状態は `FollowedStreamStore` との cross-reference で判定し、赤い縁取りで表示する
struct ChannelSearchView: View {

    /// フォロー中チャンネル一覧（候補フィルタのデータソース + 検索 API フォールバック）
    let followedChannelStore: FollowedChannelStore
    /// フォロー中ライブストリーム一覧（ライブ状態の判定に使用）
    let followedStreamStore: FollowedStreamStore
    /// プロフィール画像ストア（候補行のアイコン表示に使用）
    let profileImageStore: ProfileImageStore
    /// チャンネル確定時のコールバック（channelLogin を渡す）
    let onChannelSelected: (String) -> Void
    /// キャンセル時のコールバック（nil の場合はキャンセル不可 = タブ0個時）
    let onCancel: (() -> Void)?

    @State private var searchText: String = ""
    @State private var searchResults: [ChannelSearchResult] = []
    @State private var isSearching: Bool = false
    /// キーボード選択中の候補インデックス（候補が出現したとき 0 にリセット）
    @State private var selectedCandidateIndex: Int = 0
    @FocusState private var isTextFieldFocused: Bool

    // MARK: - 定数

    /// TextField / 候補リストの幅
    private static let formWidth: CGFloat = 480
    /// TextField のフォントサイズ
    private static let textFieldFontSize: CGFloat = 20
    /// 候補リストの最大表示件数
    private static let maxCandidates: Int = 6
    /// 候補行のアイコンサイズ
    private static let iconSize: CGFloat = 32
    /// ライブ中縁取りの太さ
    private static let liveBorderWidth: CGFloat = 2

    // MARK: - 算出プロパティ

    /// クエリにマッチするフォロー中チャンネル（最大 maxCandidates 件）
    private var filteredChannels: [FollowedChannel] {
        let filtered = ChannelSearchFilter.filter(
            channels: followedChannelStore.channels,
            query: searchText
        )
        return Array(filtered.prefix(Self.maxCandidates))
    }

    /// 候補リストを表示するかどうか
    private var shouldShowCandidates: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        return !filteredChannels.isEmpty || isSearching || !searchResults.isEmpty
    }

    /// キーボードナビゲーション対象の候補ログイン名一覧
    ///
    /// filteredChannels と searchResults は排他表示のためどちらか一方のみ返す
    private var candidateLogins: [String] {
        if !filteredChannels.isEmpty {
            return filteredChannels.map(\.broadcasterLogin)
        }
        return searchResults.prefix(Self.maxCandidates).map(\.broadcasterLogin)
    }

    // MARK: - ボディ

    var body: some View {
        VStack(spacing: 0) {
            // 上下均等の Spacer で TextField を中央に固定する
            Spacer()

            TextField("チャンネル名を入力", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Self.textFieldFontSize))
                .frame(width: Self.formWidth)
                .focused($isTextFieldFocused)
                .onSubmit {
                    // 候補が選択中ならそのチャンネルを開く。なければ入力テキストを確定する
                    if candidateLogins.indices.contains(selectedCandidateIndex) {
                        onChannelSelected(candidateLogins[selectedCandidateIndex])
                    } else {
                        submitCurrentText()
                    }
                }
                // 下矢印キー: 次の候補に移動
                .onKeyPress(.downArrow) {
                    selectedCandidateIndex = CandidateNavigator.nextIndex(
                        current: selectedCandidateIndex,
                        count: candidateLogins.count
                    )
                    return .handled
                }
                // 上矢印キー: 前の候補に移動
                .onKeyPress(.upArrow) {
                    selectedCandidateIndex = CandidateNavigator.previousIndex(
                        current: selectedCandidateIndex,
                        count: candidateLogins.count
                    )
                    return .handled
                }

            // ゼロ高さのアンカービュー: Spacer のバランスに影響せず TextField が常に中央に固定される
            // overlay の内容は候補リストをテキストフィールド直下に表示する起点として機能する
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .top) {
                    if shouldShowCandidates {
                        candidateList
                            .frame(width: Self.formWidth)
                            .padding(.top, 8)
                    }
                }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isTextFieldFocused = true
            // フォロー中チャンネルのプロフィール画像を事前取得する
            let userIds = followedChannelStore.channels.map(\.broadcasterId)
            if !userIds.isEmpty {
                Task { await profileImageStore.fetchUsers(userIds: userIds) }
            }
        }
        // フォロー中チャンネルが更新されたらプロフィール画像を取得する
        .onChange(of: followedChannelStore.channels) { _, channels in
            let userIds = channels.map(\.broadcasterId)
            if !userIds.isEmpty {
                Task { await profileImageStore.fetchUsers(userIds: userIds) }
            }
        }
        // 検索テキスト変化時: フォロー中0件なら検索 API にフォールバックする（300ms デバウンス）
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespaces)

            // 空文字列、またはフォロー中チャンネルにクエリが一致した → 検索 API を使わない
            // フォロー中チャンネルに一致がない場合のみ /helix/search/channels にフォールバックする
            guard !query.isEmpty, filteredChannels.isEmpty else {
                searchResults = []
                isSearching = false
                return
            }

            // 300ms デバウンス（タイピング途中の API リクエストを防ぐ）
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            // 検索 API を呼び出す
            isSearching = true
            let results = await followedChannelStore.searchChannels(query: query)
            guard !Task.isCancelled else { return }

            // 取得した検索結果のプロフィール画像を非同期で取得する
            let userIds = results.map(\.id)
            if !userIds.isEmpty {
                await profileImageStore.fetchUsers(userIds: userIds)
            }
            searchResults = results
            isSearching = false
        }
        // テキスト入力変化時: filteredChannels が即時更新されるため選択インデックスをリセットする
        .onChange(of: searchText) { _, _ in
            selectedCandidateIndex = 0
        }
        // 検索 API 結果が到着したとき: 最初の候補を選択状態にする
        .onChange(of: searchResults) { _, _ in
            selectedCandidateIndex = 0
        }
        // Escape キーで blank tab を閉じる
        .onKeyPress(.escape) {
            guard let onCancel else { return .ignored }
            onCancel()
            return .handled
        }
    }

    // MARK: - 候補リスト

    /// フォロー中チャンネルまたは検索結果の候補リスト
    ///
    /// - `fixedSize(horizontal: false, vertical: true)` でゼロ高さアンカーから提案される 0pt を無視し、
    ///   VStack が常にコンテンツ高さを使うようにする
    /// - background は Shape fill を使用することで、view の実際のサイズのみ塗りつぶす
    private var candidateList: some View {
        VStack(spacing: 0) {
            if !filteredChannels.isEmpty {
                // フォロー中チャンネルの候補（インデックスで選択ハイライトを判定）
                ForEach(Array(filteredChannels.enumerated()), id: \.element.id) { index, channel in
                    followedChannelRow(channel, isSelected: index == selectedCandidateIndex)
                }
            } else if isSearching {
                // 検索 API 取得中
                ProgressView()
                    .padding(16)
            } else if !searchResults.isEmpty {
                // 検索 API のフォールバック結果
                Text("チャンネル検索結果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                ForEach(
                    Array(searchResults.prefix(Self.maxCandidates).enumerated()),
                    id: \.element.id
                ) { index, result in
                    searchResultRow(result, isSelected: index == selectedCandidateIndex)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 1)
        }
    }

    // MARK: - 候補行: フォロー中チャンネル

    /// フォロー中チャンネルの候補行
    ///
    /// - Parameters:
    ///   - channel: 表示するチャンネル
    ///   - isSelected: キーボードで選択中かどうか（ハイライト表示に使用）
    ///
    /// ライブ中かどうかは `followedStreamStore` との cross-reference で判定する
    private func followedChannelRow(_ channel: FollowedChannel, isSelected: Bool) -> some View {
        let liveStream = followedStreamStore.stream(forUserLogin: channel.broadcasterLogin)
        let isLive = liveStream != nil

        return Button {
            onChannelSelected(channel.broadcasterLogin)
        } label: {
            HStack(spacing: 10) {
                // プロフィールアイコン（ライブ中は赤い縁取り）
                ProfileImageView(
                    userId: channel.broadcasterId,
                    imageUrl: profileImageStore.profileImageUrl(for: channel.broadcasterId),
                    size: Self.iconSize
                )
                .overlay {
                    if isLive {
                        Circle().stroke(Color.red, lineWidth: Self.liveBorderWidth)
                    }
                }

                // チャンネル情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.broadcasterName)
                        .font(.body)
                        .lineLimit(1)
                    if let gameName = liveStream?.gameName, !gameName.isEmpty {
                        Text(gameName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 視聴者数（ライブ中のみ表示）
                if let viewerCount = liveStream?.viewerCount {
                    Text(formatViewerCount(viewerCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // キーボード選択中の行をアクセントカラーで薄くハイライトする
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 候補行: チャンネル検索結果

    /// チャンネル検索結果（検索 API フォールバック）の候補行
    ///
    /// - Parameters:
    ///   - result: 表示する検索結果
    ///   - isSelected: キーボードで選択中かどうか（ハイライト表示に使用）
    private func searchResultRow(_ result: ChannelSearchResult, isSelected: Bool) -> some View {
        Button {
            onChannelSelected(result.broadcasterLogin)
        } label: {
            HStack(spacing: 10) {
                // プロフィールアイコン（ライブ中は赤い縁取り）
                ProfileImageView(
                    userId: result.id,
                    imageUrl: profileImageStore.profileImageUrl(for: result.id),
                    size: Self.iconSize
                )
                .overlay {
                    if result.isLive {
                        Circle().stroke(Color.red, lineWidth: Self.liveBorderWidth)
                    }
                }

                // チャンネル情報
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if !result.gameName.isEmpty {
                        Text(result.gameName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // キーボード選択中の行をアクセントカラーで薄くハイライトする
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
