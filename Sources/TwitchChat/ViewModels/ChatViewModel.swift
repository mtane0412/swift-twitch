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

    /// メッセージ送信中フラグ（UI のローディング表示用）
    private(set) var isSending: Bool = false

    /// 最後の送信エラーメッセージ（UI 表示用、成功時は nil にリセット）
    private(set) var sendError: String?

    // MARK: - プライベートプロパティ

    private let ircClient: any TwitchIRCClientProtocol
    private var receiveTask: Task<Void, Never>?

    /// 認証状態（ログイン済みなら認証接続、ログアウト中なら匿名接続）
    private let authState: AuthState

    /// バッジ定義ストア（View からバッジ画像URLの解決に使用）
    let badgeStore: BadgeStore

    /// グローバルバッジフェッチタスク（切断時にキャンセル）
    private var globalBadgeFetchTask: Task<Void, Never>?

    /// チャンネルバッジフェッチタスク（切断時にキャンセル）
    private var channelBadgeFetchTask: Task<Void, Never>?

    /// チャンネルバッジ取得済みフラグ
    private var channelBadgesFetched = false

    /// 最初に受信したメッセージから抽出した room-id（楽観的 UI の ChatMessage 生成に使用）
    private var currentRoomId: String?

    // MARK: - 初期化

    /// ChatViewModel を初期化する
    ///
    /// - Parameters:
    ///   - ircClient: IRC クライアント（テスト時はモックを注入）
    ///   - authState: 認証状態（ログイン済みなら認証接続に使用）
    ///   - apiClient: Helix API クライアント（テスト時はモックを注入）
    init(
        ircClient: any TwitchIRCClientProtocol = TwitchIRCClient(),
        authState: AuthState = AuthState(),
        apiClient: (any HelixAPIClientProtocol)? = nil
    ) {
        self.ircClient = ircClient
        self.authState = authState
        let helixClient = apiClient ?? HelixAPIClient(tokenProvider: authState)
        self.badgeStore = BadgeStore(apiClient: helixClient)
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

        // チャンネル切替時に前チャンネルのバッジが誤解決されないようクリア
        await badgeStore.resetChannelBadges()

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
            // ログイン済みなら認証接続、ログアウト中なら匿名接続にフォールバック
            let token = await authState.validAccessToken()
            let userLogin: String?
            if case .loggedIn(let login) = authState.status {
                userLogin = login
            } else {
                userLogin = nil
            }
            try await ircClient.connect(to: channel, accessToken: token, userLogin: userLogin)
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
        // BadgeStore 内部の unstructured task もキャンセルする（キャンセル伝播漏れの防止）
        await badgeStore.cancelGlobalFetch()
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
        // 楽観的 UI のために room-id を保持する（最初に取得できたものを使い続ける）
        if currentRoomId == nil {
            currentRoomId = message.roomId
        }
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }

    // MARK: - 送信

    /// コメント投稿が可能かどうか
    ///
    /// 接続済み・ログイン済み・`chat:edit` スコープ保有の3条件をすべて満たす場合のみ `true`
    var canSendMessage: Bool {
        guard connectionState == .connected else { return false }
        guard case .loggedIn = authState.status else { return false }
        return authState.canSendChat
    }

    /// 入力テキストをサニタイズして PRIVMSG を送信し、楽観的 UI を更新する
    ///
    /// Twitch IRC は自分の PRIVMSG をエコーバックしないため、
    /// 送信成功後にローカルで ChatMessage を生成して `messages` に追加する。
    ///
    /// - Parameter text: 生の入力テキスト（改行・空白を含む場合がある）
    /// - Throws: `ChatSendError.empty`（空文字）、`.tooLong`（500 文字超）、
    ///           `.notReady`（未接続・未ログイン・スコープ不足）、
    ///           または IRC クライアントが throw するエラー
    func sendMessage(_ text: String) async throws {
        let sanitized = Self.sanitize(text)
        guard !sanitized.isEmpty else { throw ChatSendError.empty }
        guard sanitized.count <= 500 else { throw ChatSendError.tooLong }
        guard canSendMessage else { throw ChatSendError.notReady }

        isSending = true
        sendError = nil
        defer { isSending = false }

        do {
            try await ircClient.sendPrivmsg(sanitized)
            // 楽観的 UI: 自分の PRIVMSG はサーバーからエコーバックされないのでローカルで追加する
            if case .loggedIn(let login) = authState.status {
                let localMessage = ChatMessage(
                    localUsername: login,
                    displayName: login,
                    text: sanitized,
                    roomId: currentRoomId
                )
                appendMessage(localMessage)
            }
        } catch {
            sendError = error.localizedDescription
            throw error
        }
    }

    /// 送信エラーをリセットする（UI でエラー表示を消す際に呼ぶ）
    func clearSendError() {
        sendError = nil
    }

    /// IRC メッセージ送信用テキストのサニタイズ
    ///
    /// - `\r` を除去（CRLF の `\r` だけを除いて `\n` と `\r\n` を統一）
    /// - `\n` をスペースに変換（IRC は行区切りプロトコルのため改行禁止）
    /// - 前後の空白をトリム
    ///
    /// - Parameter text: 生の入力テキスト
    /// - Returns: サニタイズ済みテキスト
    static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 送信エラー定義

/// チャットメッセージ送信時のエラー
enum ChatSendError: Error, LocalizedError, Equatable {
    /// 送信テキストが空（トリム後）
    case empty
    /// 送信テキストが 500 文字を超えている
    case tooLong
    /// 送信できる状態でない（未接続・未ログイン・スコープ不足）
    case notReady

    var errorDescription: String? {
        switch self {
        case .empty:
            return "メッセージを入力してください"
        case .tooLong:
            return "メッセージは500文字以内にしてください"
        case .notReady:
            return "コメントの投稿にはログインが必要です"
        }
    }
}
