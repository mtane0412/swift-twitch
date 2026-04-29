// StreamPlayerViewModel.swift
// Twitch ライブ配信 AVPlayer の状態管理 ViewModel

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

    // MARK: - プライベートプロパティ

    private let resolver: any StreamPlaybackResolverProtocol
    /// 進行中の load Task（キャンセル用）
    private var loadTask: Task<Void, Never>?

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
        // チャンネル切替直後に前の配信音声が流れ続けないよう即座に停止する
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .resolving
        currentLogin = login

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
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        currentLogin = nil
    }

    /// 直前のエラーから再試行する
    func retry() async {
        guard let login = currentLogin else { return }
        await load(login: login)
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
