// StreamPlayerViewModelTests.swift
// StreamPlayerViewModel の単体テスト
// MockStreamPlaybackResolver を使ってネットワーク通信なしで state 遷移・AVPlayer 設定を検証する

import AVFoundation
import Foundation
import Testing
@testable import TwitchChat

// MARK: - テスト用モック

/// StreamPlaybackResolver のモック実装
actor MockStreamPlaybackResolver: StreamPlaybackResolverProtocol {

    /// 返すマニフェスト（正常ケース用）
    var manifestToReturn: StreamPlaybackManifest?
    /// 投げるエラー（nil の場合はマニフェストを返す）
    var errorToThrow: PlaybackError?
    /// resolve が呼ばれた login をキャプチャ（検証用）
    private(set) var capturedLogins: [String] = []
    /// resolve が呼ばれた回数
    var callCount: Int { capturedLogins.count }

    // MARK: - ブロッキングサポート（in-flight 競合テスト用）

    /// 次の resolve をサスペンドするかどうか
    private var shouldSuspend = false
    /// サスペンド中の continuation（unblock/キャンセルで resume する）
    private var blockedContinuation: CheckedContinuation<StreamPlaybackManifest, Error>?
    /// サスペンド到達を呼び出し元に通知する continuation
    private var onSuspendedContinuation: CheckedContinuation<Void, Never>?

    /// 次の resolve をサスペンドするよう予約する
    func suspendNextResolve() {
        shouldSuspend = true
    }

    /// resolve がサスペンド状態に入るまで待機する（テストの同期に使用）
    func waitUntilSuspended() async {
        await withCheckedContinuation { cont in
            onSuspendedContinuation = cont
        }
    }

    func resolve(login: String) async throws -> StreamPlaybackManifest {
        capturedLogins.append(login)
        if shouldSuspend {
            shouldSuspend = false
            // 呼び出し元に「サスペンド到達」を通知
            onSuspendedContinuation?.resume()
            onSuspendedContinuation = nil
            // キャンセル時に continuation を resume して CancellationError を伝播する
            return try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { cont in
                        self.blockedContinuation = cont
                    }
                },
                onCancel: {
                    Task { await self.resumeBlockedWithCancellation() }
                }
            )
        }
        if let error = errorToThrow {
            throw error
        }
        guard let manifest = manifestToReturn else {
            throw PlaybackError.channelOffline
        }
        return manifest
    }

    /// ブロック中の continuation をキャンセルエラーで resume する
    private func resumeBlockedWithCancellation() {
        blockedContinuation?.resume(throwing: CancellationError())
        blockedContinuation = nil
    }
}

// MARK: - テストデータファクトリ

/// テスト用 StreamPlaybackManifest を生成する
private func makeManifest(url: URL = URL(string: "https://usher.ttvnw.net/api/channel/hls/argstar.m3u8?sig=s&token=t")!) -> StreamPlaybackManifest {
    StreamPlaybackManifest(url: url, fetchedAt: Date())
}

// MARK: - テスト

@Suite("StreamPlayerViewModel テスト")
@MainActor
struct StreamPlayerViewModelTests {

    // MARK: - 初期状態テスト

    @Test("初期状態は idle である")
    func initialStateIsIdle() {
        let resolver = MockStreamPlaybackResolver()
        let viewModel = StreamPlayerViewModel(resolver: resolver)

        #expect(viewModel.state == .idle)
        #expect(viewModel.currentLogin == nil)
        #expect(viewModel.player.currentItem == nil)
    }

    // MARK: - load テスト

    @Test("resolve 成功後 state は playing になる")
    func stateIsPlayingAfterLoad() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest())

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "argstar")

        #expect(viewModel.state == .playing)
    }

    @Test("resolve 成功後 currentLogin が更新される")
    func currentLoginIsUpdatedAfterSuccess() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest())

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "argstar")

        #expect(viewModel.currentLogin == "argstar")
    }

    @Test("resolve 成功後 player.currentItem に AVURLAsset が設定される")
    func playerItemIsSetAfterSuccess() async throws {
        let testURL = URL(string: "https://usher.ttvnw.net/api/channel/hls/forsen.m3u8?sig=s&token=t")!
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest(url: testURL))

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "forsen")

        guard let asset = viewModel.player.currentItem?.asset as? AVURLAsset else {
            Issue.record("player.currentItem の asset が AVURLAsset ではない")
            return
        }
        #expect(asset.url == testURL)
    }

    @Test("channelOffline エラーで state は offline になる")
    func stateIsOfflineOnChannelOfflineError() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setError(.channelOffline)

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "オフラインチャンネル")

        #expect(viewModel.state == .offline)
    }

    @Test("tokenDecodingFailed エラーで state は error になる")
    func stateIsErrorOnTokenDecodingFailed() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setError(.tokenDecodingFailed)

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "テストチャンネル")

        if case .error = viewModel.state {
            // エラー状態になっていればよい
        } else {
            Issue.record("state が error でない: \(viewModel.state)")
        }
    }

    @Test("geoOrSubscriberRestricted エラーで state は error になる")
    func stateIsErrorOnGeoOrSubscriberRestricted() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setError(.geoOrSubscriberRestricted)

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "サブスク限定チャンネル")

        if case .error = viewModel.state {
            // エラー状態になっていればよい
        } else {
            Issue.record("state が error でない: \(viewModel.state)")
        }
    }

    // MARK: - stop テスト

    @Test("stop() で player.currentItem が nil になる")
    func stopClearsPlayerItem() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest())

        let viewModel = StreamPlayerViewModel(resolver: resolver)
        await viewModel.load(login: "argstar")
        viewModel.stop()

        #expect(viewModel.player.currentItem == nil)
        #expect(viewModel.state == .idle)
    }

    // MARK: - 重複 load テスト

    @Test("load 中に別 login で load を呼ぶと前のロードがキャンセルされ最後の login だけが反映される")
    func secondLoadCancelsFirstInFlight() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest())
        // 1回目の resolve をサスペンドして in-flight 状態を作る
        await resolver.suspendNextResolve()

        let viewModel = StreamPlayerViewModel(resolver: resolver)

        // 1回目の load を Task で開始（await せず in-flight のまま保持）
        let firstLoadTask = Task { await viewModel.load(login: "argstar") }
        // resolver がサスペンド到達するまで待機（確実な同期）
        await resolver.waitUntilSuspended()

        // 2回目の load を呼ぶ（1回目がキャンセルされ、2回目が優先される）
        await viewModel.load(login: "forsen")
        await firstLoadTask.value

        #expect(viewModel.currentLogin == "forsen")
    }

    @Test("複数回 load を順番に呼んでも currentLogin は最後の値になる")
    func sequentialLoadsUpdateCurrentLogin() async throws {
        let resolver = MockStreamPlaybackResolver()
        await resolver.setManifest(makeManifest())

        let viewModel = StreamPlayerViewModel(resolver: resolver)

        await viewModel.load(login: "argstar")
        await viewModel.load(login: "forsen")

        #expect(viewModel.currentLogin == "forsen")
    }
}

// MARK: - MockStreamPlaybackResolver セッターヘルパー

extension MockStreamPlaybackResolver {
    func setManifest(_ manifest: StreamPlaybackManifest) {
        self.manifestToReturn = manifest
        self.errorToThrow = nil
    }

    func setError(_ error: PlaybackError) {
        self.errorToThrow = error
        self.manifestToReturn = nil
    }
}
