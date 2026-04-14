// ChatViewModel.swift
// チャット画面の ViewModel
// @Observable マクロで SwiftUI ビューとのバインディングを管理する

import Foundation
import Observation

/// チャット接続の状態
enum ConnectionState: Equatable {
    /// 未接続
    case disconnected
    /// 接続中
    case connecting
    /// 接続済み
    case connected
    /// エラー
    case error(String)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

/// チャット画面の ViewModel
///
/// Twitch IRC クライアントを通じてチャットメッセージを受信し、
/// SwiftUI ビューに表示するためのデータを管理する
///
/// - Note: `@MainActor` で UI スレッドでの状態更新を保証する
@Observable
@MainActor
final class ChatViewModel {
    // MARK: - 定数

    /// メモリ管理のための最大メッセージ保持件数
    private static let maxMessages = 500

    // MARK: - Published プロパティ

    /// 受信済みチャットメッセージ（最新 500 件）
    private(set) var messages: [ChatMessage] = []

    /// 接続状態
    private(set) var connectionState: ConnectionState = .disconnected

    /// 接続中のチャンネル名
    private(set) var channelName: String = ""

    // MARK: - プライベートプロパティ

    private let ircClient: any TwitchIRCClientProtocol
    private var receiveTask: Task<Void, Never>?

    /// バッジ定義ストア（View からバッジ画像URLの解決に使用）
    let badgeStore = BadgeStore()

    /// グローバルバッジフェッチタスク（切断時にキャンセル）
    private var globalBadgeFetchTask: Task<Void, Never>?

    /// チャンネルバッジフェッチタスク（切断時にキャンセル）
    private var channelBadgeFetchTask: Task<Void, Never>?

    /// チャンネルバッジ取得済みフラグ
    private var channelBadgesFetched = false

    // MARK: - 初期化

    /// ChatViewModel を初期化する
    ///
    /// - Parameter ircClient: IRC クライアント（テスト時はモックを注入）
    init(ircClient: any TwitchIRCClientProtocol = TwitchIRCClient()) {
        self.ircClient = ircClient
    }

    // MARK: - 接続・切断

    /// 指定チャンネルに接続する
    ///
    /// - Parameter channel: チャンネル名（例: "haishinsha"）
    func connect(to channel: String) async {
        guard connectionState == .disconnected else { return }

        channelName = channel
        connectionState = .connecting
        messages = []
        channelBadgesFetched = false

        // グローバルバッジ定義を並行フェッチ（切断時にキャンセルできるよう保持）
        globalBadgeFetchTask = Task { await badgeStore.fetchGlobalBadges() }

        receiveTask = Task { [weak self] in
            // メッセージ受信ループを別タスクで開始
            // weak self で循環参照を回避する
            guard let self else { return }
            let stream = await self.ircClient.messageStream
            for await message in stream {
                guard !Task.isCancelled else { break }
                self.appendMessage(message)
            }
        }

        do {
            try await ircClient.connect(to: channel)
            connectionState = .connected
        } catch {
            connectionState = .error(error.localizedDescription)
            receiveTask?.cancel()
        }
    }

    /// チャンネルから切断する
    func disconnect() async {
        receiveTask?.cancel()
        globalBadgeFetchTask?.cancel()
        channelBadgeFetchTask?.cancel()
        await ircClient.disconnect()
        connectionState = .disconnected
    }

    // MARK: - プライベートメソッド

    /// メッセージをリストに追加し、上限を超えた場合は古いものを削除する
    private func appendMessage(_ message: ChatMessage) {
        // 最初の room-id 取得時にチャンネルバッジをフェッチ（切断時にキャンセルできるよう保持）
        if !channelBadgesFetched, let roomId = message.roomId {
            channelBadgesFetched = true
            channelBadgeFetchTask = Task { await badgeStore.fetchChannelBadges(channelId: roomId) }
        }
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }
}
