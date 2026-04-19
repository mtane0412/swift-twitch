// EmotePickerViewModel.swift
// エモートピッカー用 ViewModel
// EmoteStore からエモート一覧を取得し、検索クエリに応じてフィルタリングする

import Foundation
import Observation

/// エモートピッカー用 ViewModel
///
/// - `loadEmotes()` 呼び出しで EmoteStore から全エモートを取得する
/// - `searchQuery` を変更すると即座に `filteredEmotes` がフィルタリングされる
/// - フィルタリングは大文字小文字非区別の部分一致
@Observable
@MainActor
final class EmotePickerViewModel {

    // MARK: - 公開プロパティ

    /// フィルタリング済みエモート一覧（UI へのバインディング用）
    private(set) var filteredEmotes: [HelixEmote] = []

    /// 検索クエリ（空文字の場合は全件表示）
    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            applyFilter()
        }
    }

    // MARK: - プライベートプロパティ

    /// フィルタ前の全エモート一覧
    private var allEmotes: [HelixEmote] = []

    /// エモート定義ストア
    private let emoteStore: EmoteStore

    /// ユーザーが使用可能なエモートセット ID のスナップショット
    ///
    /// `loadEmotes()` 呼び出し時に EmoteStore からスナップショットを取得する。
    /// - `nil`: USERSTATE 未受信（全エモートを使用可能として扱う）
    /// - 空 `Set`: USERSTATE 受信済みだが使用可能セットが空
    private var userEmoteSets: Set<String>?

    // MARK: - 初期化

    /// EmotePickerViewModel を初期化する
    ///
    /// - Parameter emoteStore: エモート定義ストア
    init(emoteStore: EmoteStore) {
        self.emoteStore = emoteStore
    }

    // MARK: - 公開メソッド

    /// EmoteStore から全エモートを取得してフィルタを適用する
    ///
    /// グローバルエモートのフェッチを待ってからスナップショットを取得することで、
    /// 接続直後にピッカーを開いても「エモートが見つかりません」にならないようにする。
    /// ピッカーが表示されるタイミング（.task モディファイア）で呼び出す。
    func loadEmotes() async {
        await emoteStore.fetchGlobalEmotes()
        allEmotes = await emoteStore.allEmotes()
        userEmoteSets = await emoteStore.userAvailableEmoteSets()
        applyFilter()
    }

    /// エモートがユーザーにとって使用可能かどうかを返す
    ///
    /// - `userEmoteSets` が `nil`（USERSTATE 未受信）の場合は全て true
    /// - `emote.emoteSetId` が nil の場合は安全側に倒して true
    /// - それ以外は emoteSetId が userEmoteSets に含まれるか判定する
    ///
    /// - Parameter emote: 判定対象のエモート
    /// - Returns: 使用可能な場合は true
    func isAvailable(_ emote: HelixEmote) -> Bool {
        guard let sets = userEmoteSets else { return true }
        guard let emoteSetId = emote.emoteSetId else { return true }
        return sets.contains(emoteSetId)
    }

    // MARK: - プライベートメソッド

    /// 現在の searchQuery に基づいて filteredEmotes を更新する
    ///
    /// - 空クエリの場合は全件返す
    /// - 大文字小文字を区別しない部分一致でフィルタリングする
    private func applyFilter() {
        guard !searchQuery.isEmpty else {
            filteredEmotes = allEmotes
            return
        }
        filteredEmotes = allEmotes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
}
