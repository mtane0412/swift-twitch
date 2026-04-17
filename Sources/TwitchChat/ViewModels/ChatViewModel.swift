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
    /// 再接続中（切断検知後、指数バックオフでリトライ中）
    ///
    /// - Parameter attempt: 現在の再接続試行回数（1 始まり）
    case reconnecting(attempt: Int)
    /// エラー
    case error(String)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.reconnecting(let l), .reconnecting(let r)): return l == r
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

    /// NOTICE 受信ループタスク（切断時にキャンセル）
    private var noticeReceiveTask: Task<Void, Never>?

    /// IRC クライアントの接続状態変化を購読するタスク（切断時にキャンセル）
    private var connectionStateReceiveTask: Task<Void, Never>?

    /// USERSTATE 受信ループタスク（切断時にキャンセル）
    private var userStateReceiveTask: Task<Void, Never>?

    /// USERSTATE から取得した自分のユーザー状態（楽観的 UI 生成に使用）
    ///
    /// JOIN 後とメッセージ送信後に更新される。nil の場合は login 名にフォールバックする。
    /// テストからポーリング条件として参照できるよう `private(set)` で公開する。
    private(set) var currentUserState: TwitchUserState?

    /// チャンネルバッジ取得済みフラグ
    private var channelBadgesFetched = false

    /// 最初に受信したメッセージから抽出した room-id（楽観的 UI の ChatMessage 生成に使用）
    private var currentRoomId: String?

    /// 楽観的 UI メッセージの送信時刻マップ（messageId → 送信時刻）
    ///
    /// 複数のメッセージを連続送信した場合でも各メッセージを個別に rollback できるよう
    /// 辞書で管理する。NOTICE 受信時は rollback ウィンドウ内で最も古いものを除去する。
    private var optimisticPendingMessages: [String: Date] = [:]

    /// 楽観的 UI メッセージを rollback する有効期間（秒）
    ///
    /// この期間内に受信した NOTICE のみを直近の送信に対するサーバー拒否とみなす。
    private static let optimisticRollbackWindow: TimeInterval = 5

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
        currentRoomId = nil

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

        noticeReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.ircClient.noticeStream
            for await notice in stream {
                guard !Task.isCancelled else { break }
                self.handleIncomingNotice(notice)
            }
        }

        // IRC クライアントの接続状態変化（再接続 / 再接続成功）を ViewModel の状態に反映する
        connectionStateReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.ircClient.connectionStateStream
            for await state in stream {
                guard !Task.isCancelled else { break }
                self.applyClientConnectionState(state)
            }
        }

        // USERSTATE を購読して自分のユーザー情報を更新する（楽観的 UI の精度向上）
        userStateReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.ircClient.userStateStream
            for await userState in stream {
                guard !Task.isCancelled else { break }
                self.currentUserState = userState
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
            noticeReceiveTask?.cancel()
            connectionStateReceiveTask?.cancel()
            userStateReceiveTask?.cancel()
            globalBadgeFetchTask?.cancel()
        }
    }

    /// チャンネルから切断する
    func disconnect() async {
        receiveTask?.cancel()
        noticeReceiveTask?.cancel()
        connectionStateReceiveTask?.cancel()
        userStateReceiveTask?.cancel()
        globalBadgeFetchTask?.cancel()
        channelBadgeFetchTask?.cancel()
        // BadgeStore 内部の unstructured task もキャンセルする（キャンセル伝播漏れの防止）
        await badgeStore.cancelGlobalFetch()
        await ircClient.disconnect()
        connectionState = .disconnected
        currentRoomId = nil
        currentUserState = nil
        optimisticPendingMessages.removeAll()
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

    /// IRC クライアントから通知された接続状態を ViewModel の ConnectionState に反映する
    ///
    /// - `.connected` → `.connected`（再接続成功時も含む。`messages` はリセットしない）
    /// - `.reconnecting(attempt:)` → `.reconnecting(attempt:)`
    /// - `.disconnected` → 無視（`disconnect()` で明示的に遷移させるため）
    private func applyClientConnectionState(_ state: ClientConnectionState) {
        // 切断済み状態に遅延到達した通知が上書きしないようにガードする
        guard connectionState != .disconnected else { return }
        switch state {
        case .connected:
            connectionState = .connected
        case .reconnecting(let attempt):
            connectionState = .reconnecting(attempt: attempt)
        case .disconnected:
            // ViewModel.disconnect() で明示的に .disconnected へ遷移させるので無視
            break
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
                // USERSTATE 受信済みなら displayName / colorHex / badges に反映する
                let localMessage = ChatMessage(
                    localUsername: login,
                    displayName: currentUserState?.displayName ?? login,
                    text: sanitized,
                    roomId: currentRoomId,
                    colorHex: currentUserState?.colorHex,
                    badges: currentUserState?.badges ?? []
                )
                appendMessage(localMessage)
                // サーバー拒否（NOTICE）が来た場合の rollback のために ID と時刻を記録する
                optimisticPendingMessages[localMessage.id] = Date()
            }
        } catch TwitchIRCClientError.rateLimited(let retryAfter) {
            // クライアント側レートリミットエラーを ChatSendError に変換して上位に伝える
            let sendError = ChatSendError.clientRateLimited(retryAfter: retryAfter)
            self.sendError = sendError.localizedDescription
            throw sendError
        } catch {
            sendError = error.localizedDescription
            throw error
        }
    }

    /// 送信エラーをリセットする（UI でエラー表示を消す際に呼ぶ）
    func clearSendError() {
        sendError = nil
    }

    /// サーバーから受信した NOTICE を処理する
    ///
    /// エラー系 msg-id に対応する ChatSendError を `sendError` に反映し、
    /// `optimisticPendingMessages` の rollback ウィンドウ内で最も新しい楽観的 UI メッセージを
    /// `messages` から除去する。直前に送ったメッセージが拒否された可能性が最も高いため、
    /// 送信時刻が最新のエントリを rollback 対象とする。
    private func handleIncomingNotice(_ notice: TwitchNotice) {
        guard let error = ChatSendError.from(notice: notice) else {
            // 情報系通知（host_on, host_off 等）は何もしない
            return
        }
        sendError = error.errorDescription

        let now = Date()
        let windowStart = now.addingTimeInterval(-Self.optimisticRollbackWindow)

        // 期限切れエントリを先に除去して辞書が無限に膨らむのを防ぐ
        optimisticPendingMessages = optimisticPendingMessages.filter { $0.value >= windowStart }

        // rollback: ウィンドウ内で最も新しい pending を除去する
        // NOTICE はユーザーが直前に送ったメッセージへの拒否通知であるため、
        // 最後に追加されたものが拒否された可能性が最も高い
        if let (newestId, _) = optimisticPendingMessages
            .max(by: { $0.value < $1.value }) {
            messages.removeAll { $0.id == newestId }
            optimisticPendingMessages.removeValue(forKey: newestId)
        }
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
    /// クライアント側レートリミット超過（送信前の事前チェック）
    ///
    /// - Parameter retryAfter: 送信可能になるまでの残り秒数
    case clientRateLimited(retryAfter: TimeInterval)
    /// レートリミット超過（msg_ratelimit）
    case rateLimited
    /// 重複メッセージの連投（msg_duplicate）
    case duplicate
    /// エモートオンリーモード（msg_emoteonly）
    case emoteOnly
    /// フォロワー限定モード（msg_followersonly / msg_followersonly_followed / msg_followersonly_zero）
    case followersOnly
    /// サブスクライバー限定モード（msg_subsonly）
    case subscribersOnly
    /// スローモード中（msg_slowmode）
    case slowMode
    /// BAN またはチャンネル停止（msg_banned / msg_channel_suspended / tos_ban）
    case banned
    /// タイムアウト中（msg_timedout）
    case timedOut
    /// メール/電話番号認証が必要（msg_verified_email / msg_requires_verified_phone_number）
    case verificationRequired
    /// 上記以外のサーバー起因エラー（エラー文言をそのまま保持）
    case serverRejected(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "メッセージを入力してください"
        case .tooLong:
            return "メッセージは500文字以内にしてください"
        case .notReady:
            return "コメントの投稿にはログインが必要です"
        case .clientRateLimited(let retryAfter):
            // retryAfter が 0 以下になる場合でも「あと 1 秒」と表示して混乱を防ぐ
            let seconds = max(1, Int(ceil(retryAfter)))
            return "送信頻度が上限に達しました。あと \(seconds) 秒後に再試行してください"
        case .rateLimited:
            return "メッセージの送信頻度が速すぎます。少し待ってから送信してください"
        case .duplicate:
            return "直前と同じメッセージは連投できません"
        case .emoteOnly:
            return "このチャンネルはエモートのみ送信できます"
        case .followersOnly:
            return "このチャンネルはフォロワー限定モードです"
        case .subscribersOnly:
            return "このチャンネルはサブスクライバー限定モードです"
        case .slowMode:
            return "スローモード中です。時間を空けて送信してください"
        case .banned:
            return "このチャンネルで投稿が制限されています"
        case .timedOut:
            return "タイムアウト中は投稿できません"
        case .verificationRequired:
            return "投稿にはメール/電話番号の認証が必要です"
        case .serverRejected(let message):
            return "送信できませんでした: \(message)"
        }
    }

    /// TwitchNotice を ChatSendError に変換する
    ///
    /// 送信エラーに相当しない NOTICE（情報系通知など）は nil を返す。
    ///
    /// - Parameter notice: サーバーから受信した TwitchNotice
    /// - Returns: 対応する ChatSendError、または変換対象外の場合は nil
    static func from(notice: TwitchNotice) -> ChatSendError? {
        guard let msgId = notice.msgId else { return nil }
        if let mapped = msgIdToError[msgId] {
            return mapped
        }
        // "msg_" プレフィックスを持つ未知の msg-id はサーバー起因エラーとして扱う
        if msgId.hasPrefix("msg_") {
            return .serverRejected(notice.message)
        }
        // 情報系通知（host_on, host_off, raid 等）は nil を返してスキップする
        return nil
    }

    /// msg-id → ChatSendError のマッピングテーブル
    ///
    /// 複数の msg-id が同じエラーに対応する場合は同じ case を指定する。
    private static let msgIdToError: [String: ChatSendError] = {
        let entries: [(String, ChatSendError)] = [
            ("msg_ratelimit",                          .rateLimited),
            ("msg_duplicate",                          .duplicate),
            ("msg_emoteonly",                          .emoteOnly),
            ("msg_followersonly",                      .followersOnly),
            ("msg_followersonly_followed",             .followersOnly),
            ("msg_followersonly_zero",                 .followersOnly),
            ("msg_subsonly",                           .subscribersOnly),
            ("msg_slowmode",                           .slowMode),
            ("msg_banned",                             .banned),
            ("msg_channel_suspended",                  .banned),
            ("tos_ban",                                .banned),
            ("no_permission",                          .banned),
            ("msg_suspended",                          .banned),
            ("msg_timedout",                           .timedOut),
            ("msg_verified_email",                     .verificationRequired),
            ("msg_requires_verified_phone_number",     .verificationRequired)
        ]
        return Dictionary(uniqueKeysWithValues: entries)
    }()
}
