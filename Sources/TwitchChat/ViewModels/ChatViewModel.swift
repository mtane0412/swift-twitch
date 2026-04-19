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

    /// 現在返信対象として選択されているメッセージ（nil の場合は通常送信）
    private(set) var replyingTo: ChatMessage?

    // MARK: - プライベートプロパティ

    private let ircClient: any TwitchIRCClientProtocol
    private var receiveTask: Task<Void, Never>?

    /// 認証状態（ログイン済みなら認証接続、ログアウト中なら匿名接続）
    private let authState: AuthState

    /// バッジ定義ストア（View からバッジ画像URLの解決に使用）
    let badgeStore: BadgeStore

    /// エモート定義ストア（エモートピッカーのデータソースに使用）
    let emoteStore: EmoteStore

    /// @メンション補完用ユーザー名リスト（入力バーの補完候補として使用）
    let mentionStore: MentionStore = MentionStore()

    /// グローバルバッジフェッチタスク（切断時にキャンセル）
    private var globalBadgeFetchTask: Task<Void, Never>?

    /// チャンネルバッジフェッチタスク（切断時にキャンセル）
    private var channelBadgeFetchTask: Task<Void, Never>?

    /// グローバルエモートフェッチタスク（切断時にキャンセル）
    private var globalEmoteFetchTask: Task<Void, Never>?

    /// チャンネルエモートフェッチタスク（切断時にキャンセル）
    private var channelEmoteFetchTask: Task<Void, Never>?

    /// ユーザーエモートフェッチタスク（切断時にキャンセル）
    ///
    /// ユーザーエモートはユーザースコープのため接続時に1回のみフェッチ（チャンネル切替時は再取得不要）
    private var userEmoteFetchTask: Task<Void, Never>?

    /// NOTICE 受信ループタスク（切断時にキャンセル）
    private var noticeReceiveTask: Task<Void, Never>?

    /// IRC クライアントの接続状態変化を購読するタスク（切断時にキャンセル）
    private var connectionStateReceiveTask: Task<Void, Never>?

    /// USERSTATE 受信ループタスク（切断時にキャンセル）
    private var userStateReceiveTask: Task<Void, Never>?

    /// ROOMSTATE 受信ループタスク（切断時にキャンセル）
    private var roomStateReceiveTask: Task<Void, Never>?

    /// USERSTATE から取得した自分のユーザー状態（楽観的 UI 生成に使用）
    ///
    /// JOIN 後とメッセージ送信後に更新される。nil の場合は login 名にフォールバックする。
    /// テストからポーリング条件として参照できるよう `private(set)` で公開する。
    private(set) var currentUserState: TwitchUserState?

    /// チャンネルバッジ取得済みフラグ
    private var channelBadgesFetched = false

    /// チャンネルエモート取得済みフラグ
    private var channelEmotesFetched = false

    /// 最初に受信したメッセージまたは ROOMSTATE から取得した room-id
    ///
    /// ROOMSTATE 購読のポーリング条件として参照できるよう `private(set)` で公開する。
    private(set) var currentRoomId: String?

    /// room-id が確定したときに呼ばれるコールバック
    ///
    /// ChannelManager が EventSub の subscribeChatMessage を呼ぶタイミングを知るために使用する。
    /// room-id は最初の 1 回のみ確定するため、コールバックも 1 度だけ呼ばれる。
    var onRoomIdConfirmed: ((String) -> Void)?

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

    /// モデレーションコマンド実行サービス
    private let moderationService: any ModerationServiceProtocol

    /// ChatViewModel を初期化する
    ///
    /// - Parameters:
    ///   - ircClient: IRC クライアント（テスト時はモックを注入）
    ///   - authState: 認証状態（ログイン済みなら認証接続に使用）
    ///   - apiClient: Helix API クライアント（テスト時はモックを注入）
    ///   - moderationService: モデレーションサービス（テスト時はモックを注入）
    init(
        ircClient: any TwitchIRCClientProtocol = TwitchIRCClient(),
        authState: AuthState = AuthState(),
        apiClient: (any HelixAPIClientProtocol)? = nil,
        moderationService: (any ModerationServiceProtocol)? = nil
    ) {
        self.ircClient = ircClient
        self.authState = authState
        let helixClient = apiClient ?? HelixAPIClient(tokenProvider: authState)
        self.badgeStore = BadgeStore(apiClient: helixClient)
        self.emoteStore = EmoteStore(apiClient: helixClient)
        self.moderationService = moderationService ?? ModerationService(apiClient: helixClient)
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
        channelEmotesFetched = false
        currentRoomId = nil

        // チャンネル切替時に前チャンネルのバッジ・エモートが誤解決されないようクリア
        await badgeStore.resetChannelBadges()
        await emoteStore.resetChannelEmotes()

        // グローバルバッジ・エモート定義を並行フェッチ（切断時にキャンセルできるよう保持）
        globalBadgeFetchTask = Task { await badgeStore.fetchGlobalBadges() }
        globalEmoteFetchTask = Task { await emoteStore.fetchGlobalEmotes() }

        // ユーザーエモートを並行フェッチ（user:read:emotes スコープがある場合のみ）
        // ユーザースコープのため接続時に1回のみ取得し、チャンネル切替時には再取得しない
        if let userId = authState.userId, authState.canReadUserEmotes {
            userEmoteFetchTask = Task { await emoteStore.fetchUserEmotes(userId: userId) }
        } else {
            #if DEBUG
            if authState.userId == nil {
                print("[ChatViewModel] ユーザーエモートフェッチをスキップ: userId が未取得（未ログイン）")
            } else if !authState.canReadUserEmotes {
                print("[ChatViewModel] ユーザーエモートフェッチをスキップ: user:read:emotes スコープなし（再ログインで取得可能）")
            }
            #endif
        }

        startStreamTasks()

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
            globalEmoteFetchTask?.cancel()
        }
    }

    /// メッセージ・NOTICE・接続状態・USERSTATE の受信ループタスクをすべて開始する
    ///
    /// connect() の本体長を抑えるために切り出したヘルパーメソッド。
    /// 各タスクは weak self で循環参照を防ぎ、disconnect() でキャンセルされる。
    private func startStreamTasks() {
        receiveTask = Task { [weak self] in
            // メッセージ受信ループ（weak self で循環参照を回避する）
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
                await self.handleUserStateUpdate(userState)
            }
        }
        // ROOMSTATE を購読して room-id を早期設定する（PRIVMSG より先に取得可能）
        roomStateReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.ircClient.roomStateStream
            for await roomId in stream {
                guard !Task.isCancelled else { break }
                self.applyRoomState(roomId: roomId)
            }
        }
    }

    /// USERSTATE 受信時のエモートセット更新処理を行う
    ///
    /// USERSTATE で通知された emote-sets を EmoteStore に反映し、
    /// 変化があった場合はユーザーエモートの再フェッチを起動する。
    ///
    /// - Parameter userState: 受信した USERSTATE 情報
    private func handleUserStateUpdate(_ userState: TwitchUserState) async {
        currentUserState = userState
        // emote-sets 変化を先に取得してからストアを更新する
        let previousEmoteSets = await emoteStore.userAvailableEmoteSets()
        await emoteStore.updateUserEmoteSets(userState.emoteSets)
        guard let userId = authState.userId, authState.canReadUserEmotes else { return }
        // emote-sets が実際に変化した場合（サブスク追加/終了）はユーザーエモートを再フェッチ
        // nil → 値 は初回 USERSTATE のため変化とみなさず、フェッチは connect() 時のタスクに任せる
        if let previous = previousEmoteSets, previous != userState.emoteSets {
            #if DEBUG
            print("[ChatViewModel] emote-sets 変化を検出 — ユーザーエモートを再フェッチ")
            #endif
            await emoteStore.resetUserEmotes()
        }
        // 未ロード・再ログイン後・emote-sets 変化後のいずれもここで起動
        // isUserEmotesLoaded フラグが内部でガードするため重複フェッチなし
        userEmoteFetchTask = Task { await emoteStore.fetchUserEmotes(userId: userId) }
    }

    /// チャンネルから切断する
    func disconnect() async {
        receiveTask?.cancel()
        noticeReceiveTask?.cancel()
        connectionStateReceiveTask?.cancel()
        userStateReceiveTask?.cancel()
        roomStateReceiveTask?.cancel()
        globalBadgeFetchTask?.cancel()
        channelBadgeFetchTask?.cancel()
        globalEmoteFetchTask?.cancel()
        channelEmoteFetchTask?.cancel()
        userEmoteFetchTask?.cancel()
        // BadgeStore / EmoteStore 内部の unstructured task もキャンセルする（キャンセル伝播漏れの防止）
        await badgeStore.cancelGlobalFetch()
        await emoteStore.cancelGlobalFetch()
        await emoteStore.cancelUserEmotesFetch()
        // disconnect 時にユーザーエモートセット・ユーザーエモートをリセットし、前回接続の情報を持ち越さない
        await emoteStore.resetUserEmoteSets()
        await emoteStore.resetUserEmotes()
        await ircClient.disconnect()
        connectionState = .disconnected
        currentRoomId = nil
        currentUserState = nil
        optimisticPendingMessages.removeAll()
    }

    // MARK: - プライベートメソッド

    /// メッセージをリストに追加し、上限を超えた場合は古いものを削除する
    private func appendMessage(_ message: ChatMessage) {
        // 最初の room-id 取得時にチャンネルバッジ・エモートをフェッチ（切断時にキャンセルできるよう保持）
        if let roomId = message.roomId {
            if !channelBadgesFetched {
                channelBadgesFetched = true
                channelBadgeFetchTask = Task { await badgeStore.fetchChannelBadges(channelId: roomId) }
            }
            if !channelEmotesFetched {
                channelEmotesFetched = true
                channelEmoteFetchTask = Task { await emoteStore.fetchChannelEmotes(broadcasterId: roomId) }
            }
        }
        // 楽観的 UI のために room-id を保持する（最初に取得できたものを使い続ける）
        if currentRoomId == nil {
            currentRoomId = message.roomId
        }
        // @メンション補完の候補リストを更新する（システム通知は空ユーザー名なので除外する）
        if !message.username.isEmpty {
            mentionStore.recordUser(username: message.username, displayName: message.displayName)
        }
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }

    /// ROOMSTATE から取得した room-id を currentRoomId に設定する
    ///
    /// PRIVMSG より先に届くため、接続直後のモデレーションコマンドが使えるようになる。
    /// room-id が既に設定済みの場合は上書きしない。
    /// チャンネルエモートは ROOMSTATE 受信時にフェッチ開始し、ピッカーを開いたときに
    /// 素早く表示できるようにする。バッジのフェッチは appendMessage() で行う。
    private func applyRoomState(roomId: String) {
        if currentRoomId == nil {
            currentRoomId = roomId
            // room-id 確定を ChannelManager に通知する（EventSub サブスクリプション登録に使用）
            onRoomIdConfirmed?(roomId)
            // PRIVMSG より先に room-id が取得できるため、チャンネルエモートを早期フェッチする
            // channelEmotesFetched フラグで重複フェッチを防止する（appendMessage() との排他制御）
            if !channelEmotesFetched {
                channelEmotesFetched = true
                channelEmoteFetchTask = Task { await emoteStore.fetchChannelEmotes(broadcasterId: roomId) }
            }
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

    // MARK: - 返信

    /// 指定メッセージへの返信モードを開始する
    ///
    /// - Parameter message: 返信先のメッセージ
    func startReply(to message: ChatMessage) {
        replyingTo = message
    }

    /// 返信モードをキャンセルし、通常送信モードに戻る
    func cancelReply() {
        replyingTo = nil
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

    /// 入力テキストをサニタイズしてコマンドパースし、IRC 送信または Helix API 呼び出しにルーティングする
    ///
    /// Twitch IRC は自分の PRIVMSG をエコーバックしないため、
    /// 送信成功後にローカルで ChatMessage を生成して `messages` に追加する。
    /// スラッシュコマンドは ChatCommandParser で解析し、IRC 経由（/me）または Helix API にルーティングする。
    ///
    /// - Parameter text: 生の入力テキスト（改行・空白を含む場合がある）
    /// - Throws: `ChatSendError.empty`（空文字）、`.tooLong`（500 文字超）、
    ///           `.notReady`（未接続・未ログイン・スコープ不足）、
    ///           `.unknownCommand`（未知のスラッシュコマンド）、
    ///           `.roomIdNotAvailable`（room-id 未取得）、
    ///           または IRC クライアントが throw するエラー
    func sendMessage(_ text: String) async throws {
        let sanitized = Self.sanitize(text)
        guard !sanitized.isEmpty else { throw ChatSendError.empty }
        guard sanitized.count <= 500 else { throw ChatSendError.tooLong }
        guard canSendMessage else { throw ChatSendError.notReady }

        let command = ChatCommandParser.parse(sanitized)

        switch command {
        case .me(let rawMessage):
            // /me コマンドは IRC 経由で ACTION 形式に変換して送信する
            // 本文前後の空白はトリムする（例: "/me   hello   " → "hello"）
            let message = rawMessage.trimmingCharacters(in: .whitespaces)
            guard !message.isEmpty else { throw ChatSendError.empty }
            let ircText = "\u{1}ACTION \(message)\u{1}"
            guard ircText.count <= 500 else { throw ChatSendError.tooLong }
            try await sendIRCMessage(ircText, displayText: message, isAction: true)

        case .plainText(let messageText):
            // 通常テキストは IRC PRIVMSG として送信する
            try await sendIRCMessage(messageText, displayText: messageText, isAction: false)

        case .unknown(let name, _):
            // 未知のスラッシュコマンドはエラーとして扱う
            let error = ChatSendError.unknownCommand(name)
            sendError = error.localizedDescription
            throw error

        default:
            // Helix API コマンド（ban/timeout/emoteonly 等）
            try await executeHelixCommand(command)
        }
    }

    /// IRC PRIVMSG を送信して楽観的 UI を更新する
    ///
    /// - Parameters:
    ///   - ircText: IRC に送信するテキスト（ACTION 形式等に変換済み）
    ///   - displayText: UI に表示するテキスト
    ///   - isAction: ACTION 形式（/me コマンド）かどうか
    private func sendIRCMessage(_ ircText: String, displayText: String, isAction: Bool) async throws {
        isSending = true
        sendError = nil
        defer { isSending = false }

        // 送信時点の返信先 ID を取得し、送信成功後にリセットするために保持する
        let parentMsgId = replyingTo?.id

        do {
            try await ircClient.sendPrivmsg(ircText, replyTo: parentMsgId)
            replyingTo = nil
            await appendOptimisticMessage(displayText: displayText, isAction: isAction, parentMsgId: parentMsgId)
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

    /// Helix API コマンド（モデレーションコマンド等）を実行する
    ///
    /// - Parameter command: 実行する ChatCommand（ban/timeout/emoteonly 等）
    /// - Throws: `ChatSendError.roomIdNotAvailable`、`HelixAPIError`
    private func executeHelixCommand(_ command: ChatCommand) async throws {
        guard let broadcasterId = currentRoomId else {
            let error = ChatSendError.roomIdNotAvailable
            sendError = error.localizedDescription
            throw error
        }
        guard let moderatorId = authState.userId else {
            let error = ChatSendError.notReady
            sendError = error.localizedDescription
            throw error
        }

        isSending = true
        sendError = nil
        defer { isSending = false }

        do {
            try await moderationService.execute(command: command, broadcasterId: broadcasterId, moderatorId: moderatorId)
            // 成功時はシステム通知をチャットに表示する
            appendSystemNotice(commandSuccessMessage(for: command))
        } catch let helixError as HelixAPIError {
            sendError = helixError.localizedDescription
            throw helixError
        } catch {
            sendError = error.localizedDescription
            throw error
        }
    }

    /// コマンド成功時に表示するシステム通知メッセージを返す
    private func commandSuccessMessage(for command: ChatCommand) -> String {
        switch command {
        case .ban(let username, _): return "/ban \(username): BANしました"
        case .timeout(let username, let duration, _): return "/timeout \(username): \(duration)秒のタイムアウトを設定しました"
        case .unban(let username), .untimeout(let username): return "\(username) の制限を解除しました"
        case .emoteOnly(let enabled): return enabled ? "エモートオンリーモードを有効にしました" : "エモートオンリーモードを無効にしました"
        case .slow(let seconds): return "スローモードを有効にしました（\(seconds ?? 30)秒）"
        case .slowOff: return "スローモードを無効にしました"
        case .subscribers(let enabled): return enabled ? "サブスクライバーモードを有効にしました" : "サブスクライバーモードを無効にしました"
        case .followers(let duration): return duration.map { "フォロワーモードを有効にしました（\($0)分）" } ?? "フォロワーモードを有効にしました"
        case .followersOff: return "フォロワーモードを無効にしました"
        case .uniqueChat(let enabled): return enabled ? "ユニークチャットモードを有効にしました" : "ユニークチャットモードを無効にしました"
        case .clear: return "チャットをクリアしました"
        case .delete(let msgId): return "メッセージ \(msgId) を削除しました"
        default: return "コマンドを実行しました"
        }
    }

    /// システム通知メッセージをチャットリストに追加する
    ///
    /// モデレーションコマンドの成功・失敗等のフィードバックに使用する
    private func appendSystemNotice(_ text: String) {
        let notice = ChatMessage(systemNotice: text, roomId: currentRoomId)
        appendMessage(notice)
    }

    /// 楽観的 UI メッセージを生成して追加する
    ///
    /// 送信直後に自分のメッセージをローカルで表示するために使用する。
    /// EmoteStore でエモート位置を解決し、エモート画像をインライン表示できるようにする。
    private func appendOptimisticMessage(displayText: String, isAction: Bool, parentMsgId: String?) async {
        guard case .loggedIn(let login) = authState.status else { return }
        // EmoteStore でテキスト内のエモート名を解決してエモート位置を取得する
        let resolvedEmotePositions = await emoteStore.emotePositions(in: displayText)
        // USERSTATE 受信済みなら displayName / colorHex / badges に反映する
        let localMessage = ChatMessage(
            localUsername: login,
            displayName: currentUserState?.displayName ?? login,
            text: displayText,
            isAction: isAction,
            roomId: currentRoomId,
            colorHex: currentUserState?.colorHex,
            badges: currentUserState?.badges ?? [],
            replyParentMsgId: parentMsgId,
            emotePositions: resolvedEmotePositions
        )
        appendMessage(localMessage)
        // サーバー拒否（NOTICE）が来た場合の rollback のために ID と時刻を記録する
        optimisticPendingMessages[localMessage.id] = Date()
    }

    /// 送信エラーをリセットする（UI でエラー表示を消す際に呼ぶ）
    func clearSendError() {
        sendError = nil
    }

    /// EventSub `channel.chat.message` イベントを処理する
    ///
    /// `optimisticPendingMessages` に記録されている楽観的 UI メッセージと照合し、
    /// 一致すれば本物の message ID で差し替え `isOptimistic` を false にする。
    /// これにより、自分のメッセージへの返信機能が有効化される。
    ///
    /// マッチング条件:
    /// 1. 送信者ログイン名が自分と一致
    /// 2. メッセージテキストが完全一致
    /// 3. 送信時刻が楽観的メッセージの追加時刻から 10 秒以内
    ///
    /// - Parameter event: EventSub から受信した channel.chat.message イベント
    func handleEventSubChatMessage(_ event: EventSubChatEvent) {
        // 自分のメッセージのみ照合する（他人のメッセージは IRC 経由で受信済み）
        guard case .loggedIn(let login) = authState.status,
              event.chatterUserLogin == login else { return }

        let now = Date()
        let matchWindow: TimeInterval = 10

        // 期限切れエントリを先に除去して辞書が無限に膨らむのを防ぐ
        // EventSub 確認が来なかったメッセージが蓄積しないようにする
        optimisticPendingMessages = optimisticPendingMessages.filter { _, sentAt in
            now.timeIntervalSince(sentAt) < matchWindow
        }

        // optimisticPendingMessages から候補を絞り込む
        // 条件: 対応する messages エントリのテキストが一致、かつ送信時刻が 10 秒以内
        let candidates = optimisticPendingMessages.filter { candidateId, sentAt in
            guard let msg = messages.first(where: { $0.id == candidateId }) else { return false }
            let elapsed = now.timeIntervalSince(sentAt)
            return msg.text == event.message.text
                && elapsed >= 0
                && elapsed < matchWindow
        }

        // 同一テキストの連投がある場合は最も古いエントリを優先（FIFO）
        guard let (optimisticId, _) = candidates.min(by: { $0.value < $1.value }) else { return }

        // messages 配列内で本物の ID に差し替える
        if let index = messages.firstIndex(where: { $0.id == optimisticId }) {
            messages[index] = ChatMessage(confirming: messages[index], withRealId: event.messageId)
        }

        // pending から除去する
        optimisticPendingMessages.removeValue(forKey: optimisticId)
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
