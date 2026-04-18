// EmoteStore.swift
// Twitch エモート定義の取得・管理サービス
// Twitch Helix API からグローバル・チャンネルエモート定義をフェッチし、ピッカー用に提供する

import Foundation

/// エモート定義の取得・管理を行うサービス
///
/// - グローバルエモートはアプリ全体で1回フェッチ（isGlobalLoaded フラグで重複防止）
/// - チャンネルエモートは room-id 取得後にフェッチし、チャンネル切替時にリセット
/// - allEmotes() はチャンネルエモートを優先し、グローバルエモートをその後に返す
/// - 並行フェッチの重複実行を Task-based deduplication で防止
/// - トークン未設定（未ログイン）の場合はフェッチをスキップする
actor EmoteStore {

    // MARK: - 定数

    /// Helix グローバルエモートエンドポイント
    private static let helixGlobalEmotesURL = URL(string: "https://api.twitch.tv/helix/chat/emotes/global")!

    /// Helix チャンネルエモートエンドポイント
    private static let helixChannelEmotesURL = URL(string: "https://api.twitch.tv/helix/chat/emotes")!

    // MARK: - 状態

    /// グローバルエモート一覧
    private var globalEmotes: [HelixEmote] = []

    /// チャンネルエモート一覧
    private var channelEmotes: [HelixEmote] = []

    /// グローバルエモート取得済みフラグ
    private var isGlobalLoaded = false

    /// 進行中のグローバルエモートフェッチタスク（並行重複排除用）
    private var globalEmotesTask: Task<Void, Never>?

    /// Helix API クライアント
    private let apiClient: any HelixAPIClientProtocol

    // MARK: - 初期化

    /// EmoteStore を初期化する
    ///
    /// - Parameter apiClient: Helix API クライアント（テスト時はモックを注入）
    init(apiClient: any HelixAPIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - 公開メソッド

    /// グローバルエモート定義をフェッチする
    ///
    /// 並行して複数回呼ばれた場合でも、ネットワークリクエストは1回のみ実行される。
    /// トークン未設定（未ログイン）の場合はスキップし、次回接続時に再取得できるよう
    /// `isGlobalLoaded` フラグを `true` にしない。
    func fetchGlobalEmotes() async {
        guard !isGlobalLoaded else { return }
        // 進行中タスクがあれば完了を待って返す（TOCTOU 防止）
        if let existing = globalEmotesTask {
            await existing.value
            return
        }
        let task = Task {
            do {
                let response: HelixEmotesResponse = try await self.apiClient.get(
                    url: Self.helixGlobalEmotesURL,
                    queryItems: nil
                )
                self.globalEmotes = response.data
                self.isGlobalLoaded = true
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                // 未ログイン時は次回接続時に再取得できるよう isGlobalLoaded を更新しない
            } catch is AuthConfigError {
                // Client ID 未設定（開発環境・テスト実行時）は正常状態のためスキップ
            } catch {
                // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
                assertionFailure("グローバルエモートフェッチ失敗: \(error)")
            }
        }
        globalEmotesTask = task
        await task.value
        globalEmotesTask = nil
    }

    /// チャンネルエモート定義をフェッチする
    ///
    /// - Parameter broadcasterId: Twitch チャンネルID（IRCの room-id タグの値、数字のみ）
    /// トークン未設定（未ログイン）の場合はスキップする。
    func fetchChannelEmotes(broadcasterId: String) async {
        // Twitch の room-id は数字のみで構成される（URLパラメータインジェクション対策）
        guard !broadcasterId.isEmpty, broadcasterId.allSatisfy(\.isNumber) else { return }
        do {
            let response: HelixEmotesResponse = try await apiClient.get(
                url: Self.helixChannelEmotesURL,
                queryItems: [URLQueryItem(name: "broadcaster_id", value: broadcasterId)]
            )
            channelEmotes = response.data
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // 未ログイン時はスキップ
        } catch is AuthConfigError {
            // Client ID 未設定（開発環境・テスト実行時）は正常状態のためスキップ
        } catch {
            // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
            assertionFailure("チャンネルエモートフェッチ失敗（broadcasterId: \(broadcasterId)）: \(error)")
        }
    }

    /// ピッカー用エモート一覧を返す
    ///
    /// チャンネルエモートを先頭に、グローバルエモートをその後に並べて返す。
    /// チャンネル固有エモートをより目立たせるための順序。
    func allEmotes() -> [HelixEmote] {
        channelEmotes + globalEmotes
    }

    /// チャンネルエモートのキャッシュをクリアする
    ///
    /// チャンネル切替時（connect 呼び出し前）に呼び出すことで、
    /// 前チャンネルのエモートが新チャンネルのピッカーに混入しないようにする
    func resetChannelEmotes() {
        channelEmotes = []
    }

    /// 進行中のグローバルエモートフェッチタスクをキャンセルする
    ///
    /// disconnect 時に呼び出すことで、不要なネットワークリクエストを中断できる
    func cancelGlobalFetch() {
        globalEmotesTask?.cancel()
        globalEmotesTask = nil
    }

    // MARK: - テスト用メソッド

#if DEBUG
    /// グローバルエモート一覧を直接設定する（テスト用）
    func setGlobalEmotes(_ emotes: [HelixEmote]) {
        globalEmotes = emotes
        isGlobalLoaded = true
    }

    /// チャンネルエモート一覧を直接設定する（テスト用）
    func setChannelEmotes(_ emotes: [HelixEmote]) {
        channelEmotes = emotes
    }
#endif
}
