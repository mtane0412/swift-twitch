// ChatViewModel+Persistence.swift
// チャット履歴の永続化バッファリング・seed・VOD video_id 取得を担当する ChatViewModel 拡張

import Foundation

extension ChatViewModel {

    // MARK: - 永続化（バッファリング書き込み・seed・videoId 取得）

    /// 200ms 間隔で pendingPersistQueue を永続化する flush ループを開始する
    ///
    /// `FollowedStreamStore.startAutoRefresh()` と同じパターンで unstructured Task を使用する。
    /// 既存のループがある場合は先にキャンセルしてから新しいループを開始する。
    func startFlushLoop() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                guard !Task.isCancelled else { break }
                await self?.flushPendingPersistQueue()
            }
        }
    }

    /// pendingPersistQueue の内容を永続化サービスに書き出す
    ///
    /// - `currentRoomId` が未確定の場合は次の flush サイクルまで保留する
    /// - `roomId` が nil のメッセージは `currentRoomId` で上書き
    /// - `videoId` が nil のメッセージは `currentVideoId` で上書き（取得済みの場合）
    func flushPendingPersistQueue() async {
        guard let persistenceService else {
            pendingPersistQueue.removeAll()
            return
        }
        guard !pendingPersistQueue.isEmpty else { return }
        // roomId 未確定の場合は次のサイクルまで保留する
        guard let roomId = currentRoomId else { return }
        let videoId = currentVideoId
        let snapshot = pendingPersistQueue.map {
            $0.withRoomIdAndVideoId(
                roomId: $0.roomId ?? roomId,
                videoId: $0.videoId ?? videoId
            )
        }
        // removeAll() は appendMessages() 成功後に行う
        // 失敗時はキューを保持して次の flush サイクルで再試行する
        do {
            try await persistenceService.appendMessages(snapshot)
            pendingPersistQueue.removeFirst(min(snapshot.count, pendingPersistQueue.count))
        } catch {
            #if DEBUG
            print("[ChatViewModel] flushPendingPersistQueue 失敗 error=\(error)")
            #endif
        }
    }

    /// 永続化サービスから直近 50 件を読み込んで messages に seed する
    ///
    /// - 既に新着メッセージが届いている場合（`messages` が空でない場合）はスキップする
    /// - 降順で返るメッセージを昇順に変換して先頭に挿入する
    func seedFromPersistence(roomId: String) async {
        guard let persistenceService else { return }
        guard messages.isEmpty || messages.allSatisfy(\.isOptimistic) else { return }
        // await 中に新着が届いた場合を検知するため件数をスナップショット
        let initialCount = messages.count
        let recent = await persistenceService.loadRecentMessages(roomId: roomId, limit: 50, before: nil)
        guard !recent.isEmpty else { return }
        // await 復帰後に状態が変化していたら seed を中止する
        guard messages.count == initialCount,
              messages.isEmpty || messages.allSatisfy(\.isOptimistic) else { return }
        // loadRecentMessages は降順（新しい順）で返すため昇順に変換して先頭に挿入
        let ordered = Array(recent.reversed())
        applyHistoricalSeed(ordered)
    }

    /// Helix /helix/videos から現在配信中の VOD video_id を取得して currentVideoId に設定する
    ///
    /// 取得できなかった場合（archive 未生成・VOD 保存無効・ネットワークエラーなど）は
    /// `currentVideoId = nil` のまま続行する（エラーによる切断はしない）。
    func fetchLatestVideoId(broadcasterId: String) async {
        do {
            let response: HelixVideosResponse = try await helixAPIClient.get(
                url: Self.videosURL,
                queryItems: [
                    URLQueryItem(name: "user_id", value: broadcasterId),
                    URLQueryItem(name: "type", value: "archive"),
                    URLQueryItem(name: "first", value: "1")
                ]
            )
            let videoId = response.data.first?.id
            updateCurrentVideoId(videoId)
            #if DEBUG
            if let videoId {
                print("[ChatViewModel] currentVideoId 確定 broadcasterId=\(broadcasterId) videoId=\(videoId)")
            } else {
                print("[ChatViewModel] currentVideoId 未取得（archive 未生成） broadcasterId=\(broadcasterId)")
            }
            #endif
        } catch {
            updateCurrentVideoId(nil)
            #if DEBUG
            print("[ChatViewModel] fetchLatestVideoId 失敗 broadcasterId=\(broadcasterId) error=\(error) → nil で続行")
            #endif
        }
    }
}
