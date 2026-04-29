// StreamPlayerViewModel.swift
// Twitch ライブ配信 AVPlayer の状態管理 ViewModel
// ライブエッジ追従・stall 検知を含む LL-HLS チューニング済み

import AVFoundation
import Foundation
import Observation

// MARK: - ViewModel

/// Twitch ライブ配信の AVPlayer 状態を管理する ViewModel
///
/// `ChannelManager` が保持する 1 インスタンスで、タブ切替に追従して再生対象を差し替える。
/// AVPlayer 実体は `player` プロパティで公開し、`StreamPlayerView` が直接参照する。
@Observable @MainActor
final class StreamPlayerViewModel {

    // MARK: - 再生状態

    /// AVPlayer の再生状態
    enum State: Equatable {
        /// 未再生（初期状態・stop 後）
        case idle
        /// マニフェスト URL を解決中
        case resolving
        /// AVPlayer に item を渡し再生中（バッファリング含む）
        case playing
        /// チャンネルがオフライン
        case offline
        /// 再生不可エラー（サブスク限定・地域制限・デコード失敗など）
        case error(message: String)
    }

    // MARK: - 公開プロパティ

    /// 現在の再生状態
    private(set) var state: State = .idle
    /// 現在再生中のチャンネルログイン名
    private(set) var currentLogin: String?
    /// View が参照する AVPlayer インスタンス（1インスタンスで item を差し替える）
    let player: AVPlayer
    /// 現在のライブエッジとの遅延秒数（再生中のみ更新、デバッグ用）
    private(set) var currentLatency: Double?
    /// バッファ不足による stall 中かどうか
    private(set) var isStalled: Bool = false

    // MARK: - プライベートプロパティ

    private let resolver: any StreamPlaybackResolverProtocol
    /// 進行中の load Task（キャンセル用）
    private var loadTask: Task<Void, Never>?
    /// 直前の seek 実行時刻（クールダウン判定用）
    private var lastSeekDate: Date?
    /// 周期的時刻オブザーバーのトークン（removeTimeObserver 用）
    private var periodicTimeObserverToken: Any?
    /// timeControlStatus KVO 観察（invalidate 用）
    private var timeControlObservation: NSKeyValueObservation?
    /// AVPlayerItemPlaybackStalledNotification 購読トークン（removeObserver 用）
    private var stalledObserver: NSObjectProtocol?

    // MARK: - 初期化

    /// `StreamPlayerViewModel` を初期化する
    ///
    /// - Parameter resolver: HLS マニフェスト URL を解決するリゾルバー
    init(resolver: any StreamPlaybackResolverProtocol = StreamPlaybackResolver()) {
        self.resolver = resolver
        self.player = AVPlayer()
    }

    // MARK: - 公開メソッド

    /// 指定チャンネルの HLS 配信を読み込んで再生を開始する
    ///
    /// 進行中の load がある場合はキャンセルして新しい load を優先する。
    ///
    /// - Parameter login: チャンネルログイン名
    func load(login: String) async {
        loadTask?.cancel()
        stopObservers()
        // チャンネル切替直後に前の配信音声が流れ続けないよう即座に停止する
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .resolving
        currentLogin = login
        isStalled = false
        currentLatency = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(login: login)
        }
        loadTask = task
        await task.value
    }

    /// 再生を停止して idle 状態に戻る
    func stop() {
        loadTask?.cancel()
        loadTask = nil
        stopObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        currentLogin = nil
        isStalled = false
        currentLatency = nil
    }

    /// 直前のエラーから再試行する
    func retry() async {
        guard let login = currentLogin else { return }
        await load(login: login)
    }

    // MARK: - ライブエッジ追従

    /// ライブエッジへの seek が必要かどうかを判定する純粋関数
    ///
    /// - Parameters:
    ///   - currentLatency: 現在のライブエッジとの遅延秒数
    ///   - recommended: AVPlayer が推奨するオフセット秒数（0 以下の場合は未確立として判定しない）
    ///   - lastSeekAge: 直前の seek からの経過秒数（クールダウン判定用）
    /// - Returns: seek すべきなら `true`
    static func shouldSeekToLive(
        currentLatency: Double,
        recommended: Double,
        lastSeekAge: Double
    ) -> Bool {
        guard recommended > 0 else { return false }
        guard lastSeekAge >= 5.0 else { return false }
        return currentLatency > recommended * 1.5
    }

    // MARK: - stall ハンドラ（テスト用に internal）

    /// stall 通知を受けたときの処理
    func handlePlaybackStalled() {
        isStalled = true
    }

    // MARK: - プライベートヘルパー

    private func performLoad(login: String) async {
        do {
            let manifest = try await resolver.resolve(login: login)
            guard !Task.isCancelled else { return }

            let asset = AVURLAsset(url: manifest.url)
            let item = AVPlayerItem(asset: asset)
            // LL-HLS チューニング: ライブエッジへの追従を最優先にする
            // Twitch は 1 秒セグメント配信（fast_bread）のため 1 セグメント分だけ先読みする
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: 2.0, preferredTimescale: 1000)
            item.preferredForwardBufferDuration = 1.0
            player.automaticallyWaitsToMinimizeStalling = false
            player.replaceCurrentItem(with: item)
            player.playImmediately(atRate: 1.0)
            state = .playing
            startObservers()
        } catch let error as PlaybackError {
            guard !Task.isCancelled else { return }
            player.pause()
            player.replaceCurrentItem(with: nil)
            state = mapPlaybackError(error)
        } catch {
            guard !Task.isCancelled else { return }
            player.pause()
            player.replaceCurrentItem(with: nil)
            state = .error(message: error.localizedDescription)
        }
    }

    private func startObservers() {
        // 1. 1秒ごとのライブエッジ乖離チェック
        let interval = CMTime(seconds: 1.0, preferredTimescale: 1000)
        periodicTimeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLiveEdgeLatency()
            }
        }

        // 2. timeControlStatus KVO: 再生再開で isStalled をリセット
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            let isPlaying = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isPlaying {
                    self.isStalled = false
                }
            }
        }

        // 3. バッファ不足による stall 通知
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackStalled()
            }
        }
    }

    private func stopObservers() {
        if let token = periodicTimeObserverToken {
            player.removeTimeObserver(token)
            periodicTimeObserverToken = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let observer = stalledObserver {
            NotificationCenter.default.removeObserver(observer)
            stalledObserver = nil
        }
    }

    private func updateLiveEdgeLatency() {
        guard let item = player.currentItem,
              let seekableRange = item.seekableTimeRanges.last?.timeRangeValue else {
            currentLatency = nil
            return
        }
        let liveEdge = CMTimeRangeGetEnd(seekableRange)
        let current = item.currentTime()
        let latency = max(0, (liveEdge - current).seconds)
        currentLatency = latency

        let recommended = item.recommendedTimeOffsetFromLive.seconds
        let lastSeekAge = lastSeekDate.map { Date().timeIntervalSince($0) } ?? Double.infinity

        if Self.shouldSeekToLive(currentLatency: latency, recommended: recommended, lastSeekAge: lastSeekAge) {
            let target = liveEdge - CMTime(seconds: recommended, preferredTimescale: 1000)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            lastSeekDate = Date()
        }
    }

    private func mapPlaybackError(_ error: PlaybackError) -> State {
        switch error {
        case .channelOffline:
            return .offline
        case .geoOrSubscriberRestricted:
            return .error(message: "この配信は視聴できません（地域制限またはサブスクライバー限定）")
        case .badURL:
            return .error(message: "マニフェスト URL の生成に失敗しました（内部エラー）")
        case .tokenDecodingFailed:
            return .error(message: "再生トークンの取得に失敗しました（APIが変更された可能性があります）")
        case .tokenRequestFailed(let statusCode):
            return .error(message: "再生トークンの取得に失敗しました（HTTP \(statusCode)）")
        case .manifestUnreachable(let statusCode):
            return .error(message: "HLS マニフェストの取得に失敗しました（HTTP \(statusCode)）")
        case .network(let urlError):
            return .error(message: "ネットワークエラー: \(urlError.localizedDescription)")
        }
    }
}
