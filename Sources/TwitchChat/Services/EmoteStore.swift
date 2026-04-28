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

    /// エモートの TTL（24 時間）
    ///
    /// stale-while-revalidate 判定に使用する。TTL 以内の永続化データがあれば API コールを抑止する。
    private static let emoteTTL: TimeInterval = 86400

    /// Helix グローバルエモートエンドポイント
    private static let helixGlobalEmotesURL = URL(string: "https://api.twitch.tv/helix/chat/emotes/global")!

    /// Helix チャンネルエモートエンドポイント
    private static let helixChannelEmotesURL = URL(string: "https://api.twitch.tv/helix/chat/emotes")!

    /// Helix ユーザーエモートエンドポイント
    private static let helixUserEmotesURL = URL(string: "https://api.twitch.tv/helix/chat/emotes/user")!

    // MARK: - 状態

    /// グローバルエモート一覧
    private var globalEmotes: [HelixEmote] = []

    /// チャンネルエモート一覧
    private var channelEmotes: [HelixEmote] = []

    /// ユーザーが使用可能なエモート一覧（/helix/chat/emotes/user から取得）
    ///
    /// サブスクしている他チャンネルのエモート・ビッツエモート・Hypeトレインエモート等を含む。
    private var userEmotes: [HelixEmote] = []

    /// グローバルエモート取得済みフラグ
    private var isGlobalLoaded = false

    /// ユーザーエモート取得済みフラグ
    private var isUserEmotesLoaded = false

    /// 進行中のグローバルエモートフェッチタスク（並行重複排除用）
    private var globalEmotesTask: Task<Void, Never>?

    /// 進行中のユーザーエモートフェッチタスク（並行重複排除用）
    private var userEmotesTask: Task<Void, Never>?

    /// Helix API クライアント
    private let apiClient: any HelixAPIClientProtocol

    /// 永続化サービス（PR-3 以降で seed/write-back に使用）
    private let persistenceService: (any PersistenceService)?

    /// ユーザーが使用可能なエモートセット ID の一覧
    ///
    /// USERSTATE の `emote-sets` タグから更新される。
    /// - `nil`: USERSTATE 未受信（全エモートを使用可能として扱う）
    /// - 空 `Set`: USERSTATE 受信済みだが使用可能セットが空
    private var userEmoteSets: Set<String>?

    /// `userEmoteSets` 更新を待機している Continuation の一覧（ID → Continuation）
    ///
    /// `waitForNextUserEmoteSetsUpdate()` が呼ばれるたびに UUID キーで Continuation を登録し、
    /// `updateUserEmoteSets` / `resetUserEmoteSets` が呼ばれたときに全件 resume する。
    /// タスクキャンセル時は UUID で個別に resume して Continuation リークを防ぐ。
    private var userEmoteSetsUpdateContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    // MARK: - 初期化

    /// EmoteStore を初期化する
    ///
    /// - Parameters:
    ///   - apiClient: Helix API クライアント（テスト時はモックを注入）
    ///   - persistenceService: 永続化サービス（nil の場合は永続化なし）
    init(apiClient: any HelixAPIClientProtocol, persistenceService: (any PersistenceService)? = nil) {
        self.apiClient = apiClient
        self.persistenceService = persistenceService
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
                self.writeBackEmotes(response.data, scope: .global)
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                // 未ログイン時は次回接続時に再取得できるよう isGlobalLoaded を更新しない
            } catch HelixAPIError.unauthorized {
                // Helix API が 401 を返した場合（トークン失効等）は次回接続時に再取得する
            } catch let error as URLError where error.code == .cancelled {
                // Task キャンセル（disconnect 等）による中断は正常系のためスキップ
            } catch is CancellationError {
                // Swift concurrency のキャンセル伝播は正常系のためスキップ
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
        // Twitch の room-id は ASCII 十進数のみで構成される（URLパラメータインジェクション対策）
        guard !broadcasterId.isEmpty, broadcasterId.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        // 永続化キャッシュから先読みしてオフライン時の即時表示と API 呼び出し抑止を実現する
        if let persistence = persistenceService {
            let cached = await persistence.loadChannelEmotesWithTimestamp(broadcasterId: broadcasterId)
            // emotes が空でも fetchedAt があれば「取得済み空配列」として TTL を適用する
            if !cached.emotes.isEmpty {
                channelEmotes = cached.emotes
                notifyUserEmoteSetsUpdated()
            }
            if let fetchedAt = cached.fetchedAt,
               Date().timeIntervalSince(fetchedAt) < Self.emoteTTL {
                return
            }
        }
        do {
            let response: HelixEmotesResponse = try await apiClient.get(
                url: Self.helixChannelEmotesURL,
                queryItems: [URLQueryItem(name: "broadcaster_id", value: broadcasterId)]
            )
            channelEmotes = response.data
            writeBackEmotes(response.data, scope: .channel(broadcasterId: broadcasterId))
            // チャンネルエモートのロード完了をピッカーに通知する
            notifyUserEmoteSetsUpdated()
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // 未ログイン時はスキップ
        } catch HelixAPIError.unauthorized {
            // Helix API が 401 を返した場合（トークン失効等）はスキップ
        } catch let error as URLError where error.code == .cancelled {
            // Task キャンセル（disconnect 等）による中断は正常系のためスキップ
        } catch is CancellationError {
            // Swift concurrency のキャンセル伝播は正常系のためスキップ
        } catch is AuthConfigError {
            // Client ID 未設定（開発環境・テスト実行時）は正常状態のためスキップ
        } catch {
            // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
            assertionFailure("チャンネルエモートフェッチ失敗（broadcasterId: \(broadcasterId)）: \(error)")
        }
    }

    /// ユーザーが使用可能なエモート定義をフェッチする
    ///
    /// `/helix/chat/emotes/user` エンドポイントを使用してサブスク中の他チャンネルエモート、
    /// ビッツエモート、Hypeトレインエモート等を取得する。cursor ベースのページネーションに対応。
    ///
    /// - Parameter userId: 認証済みユーザーの Twitch ユーザー ID（数字のみ）
    ///
    /// - Note: `user:read:emotes` スコープが必要。スコープ未付与の場合はスキップする。
    /// トークン未設定（未ログイン）の場合もスキップする。
    func fetchUserEmotes(userId: String) async {
        // Twitch の user_id は ASCII 十進数のみで構成される（URLパラメータインジェクション対策）
        guard !userId.isEmpty, userId.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        guard !isUserEmotesLoaded else { return }
        // 進行中タスクがあれば完了を待って返す（TOCTOU 防止）
        if let existing = userEmotesTask {
            await existing.value
            return
        }
        let task = Task {
            #if DEBUG
            print("[EmoteStore] fetchUserEmotes: フェッチ開始 userId=\(userId)")
            #endif
            do {
                let accumulated = try await self.performUserEmotesFetch(userId: userId)
                // 全ページ完了後に write-back（途中キャンセル時は部分データを保存しない）
                self.writeBackEmotes(accumulated, scope: .user(userId: userId))
                self.isUserEmotesLoaded = true
                #if DEBUG
                print("[EmoteStore] fetchUserEmotes: フェッチ完了 \(accumulated.count)件")
                #endif
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                // 未ログイン・スコープ未付与時はスキップ
            } catch HelixAPIError.unauthorized {
                // Helix API が 401 を返した場合（スコープ不足・トークン失効）はスキップ
                #if DEBUG
                print("[EmoteStore] fetchUserEmotes: 401 unauthorized — user:read:emotes スコープ未付与の可能性")
                #endif
            } catch let error as URLError where error.code == .cancelled {
                // Task キャンセル（disconnect 等）による中断は正常系のためスキップ
            } catch is CancellationError {
                // Swift concurrency のキャンセル伝播は正常系のためスキップ
            } catch is AuthConfigError {
                // Client ID 未設定（開発環境・テスト実行時）は正常状態のためスキップ
            } catch {
                // 設定不備・サーバーエラー等の恒久エラーは診断できるよう記録する
                assertionFailure("ユーザーエモートフェッチ失敗（userId: \(userId)）: \(error)")
            }
        }
        userEmotesTask = task
        await task.value
        userEmotesTask = nil
    }

    /// ユーザーエモートの cursor ページネーションフェッチを実行して全エモートを返す
    ///
    /// ページ取得ごとに `userEmotes` を更新してピッカーの段階表示を有効にする。
    ///
    /// - Parameter userId: 認証済みユーザーの Twitch ユーザー ID
    /// - Returns: 全ページから収集した HelixEmote 配列
    private func performUserEmotesFetch(userId: String) async throws -> [HelixEmote] {
        /// ページネーションループの上限（無限ループ防止）
        let maxPages = 100
        var accumulated: [HelixEmote] = []
        var cursor: String?
        var pageCount = 0
        repeat {
            // キャンセル済みの場合はループを抜けて古いデータを書き込まない
            guard !Task.isCancelled else { return accumulated }
            var queryItems: [URLQueryItem] = [URLQueryItem(name: "user_id", value: userId)]
            if let after = cursor {
                queryItems.append(URLQueryItem(name: "after", value: after))
            }
            let response: HelixUserEmotesResponse = try await self.apiClient.get(
                url: Self.helixUserEmotesURL,
                queryItems: queryItems
            )
            accumulated += response.data
            // ページ取得ごとにピッカーを段階更新して最初のページから即座に表示する
            self.userEmotes = accumulated
            self.notifyUserEmoteSetsUpdated()
            cursor = response.cursor.flatMap { $0.isEmpty ? nil : $0 }
            pageCount += 1
            if pageCount >= maxPages {
                assertionFailure("ユーザーエモートページネーションが上限 \(maxPages) ページに達しました")
                break
            }
        } while cursor != nil
        return accumulated
    }

    /// エモート名でエモートを検索する
    ///
    /// チャンネルエモートを優先し、次にユーザーエモート、最後にグローバルエモートを検索する。
    /// 大文字小文字を区別する完全一致で検索する（Twitch エモート名は大文字小文字を区別するため）。
    ///
    /// - Parameter name: エモート名（例: "LUL", "PogChamp"）
    /// - Returns: 見つかった HelixEmote、存在しない場合は nil
    func emote(byName name: String) -> HelixEmote? {
        allEmotes().first(where: { $0.name == name })
    }

    /// テキスト内のエモート名を検索し、EmotePosition 配列を返す
    ///
    /// テキストをスペース区切りのトークンに分割し、既知のエモート名と一致するものを
    /// `EmotePosition` に変換して返す。楽観的 UI メッセージのエモート表示に使用する。
    ///
    /// - Note: 位置は UTF-16 コードユニットベースのオフセット（Twitch IRC の emotes タグと同形式）
    /// - Parameter text: 検索対象のメッセージテキスト
    /// - Returns: 検出されたエモートの位置情報（startIndex 昇順）
    func emotePositions(in text: String) -> [EmotePosition] {
        guard !text.isEmpty else { return [] }
        let allEmotes = allEmotes()
        guard !allEmotes.isEmpty else { return [] }

        var positions: [EmotePosition] = []
        var utf16Cursor = 0
        var stringIndex = text.startIndex

        while stringIndex < text.endIndex {
            // 次のスペースまでのトークン範囲を取り出す
            let spaceIndex = text[stringIndex...].firstIndex(of: " ")
            let tokenEnd = spaceIndex ?? text.endIndex
            let token = String(text[stringIndex..<tokenEnd])
            let tokenUtf16Length = token.utf16.count

            if !token.isEmpty, let emote = allEmotes.first(where: { $0.name == token }) {
                positions.append(EmotePosition(
                    emoteId: emote.id,
                    startIndex: utf16Cursor,
                    endIndex: utf16Cursor + tokenUtf16Length - 1
                ))
            }

            utf16Cursor += tokenUtf16Length

            if let spaceIdx = spaceIndex {
                // スペース1文字分を加算して次のトークン先頭へ移動
                utf16Cursor += 1
                stringIndex = text.index(after: spaceIdx)
            } else {
                break
            }
        }

        return positions.sorted { $0.startIndex < $1.startIndex }
    }

    /// ピッカー用エモート一覧を返す
    ///
    /// チャンネルエモート → ユーザーエモート → グローバルエモートの優先順で並べ、
    /// ID ベースの重複排除を行って返す。
    ///
    /// - チャンネル固有エモートが最優先（現在視聴中チャンネル）
    /// - ユーザーエモートはサブスク中の他チャンネル・ビッツ・Hype等
    /// - グローバルエモートは最後尾
    func allEmotes() -> [HelixEmote] {
        var seen = Set<String>()
        var result: [HelixEmote] = []
        for emote in channelEmotes where seen.insert(emote.id).inserted {
            result.append(emote)
        }
        for emote in userEmotes where seen.insert(emote.id).inserted {
            result.append(emote)
        }
        for emote in globalEmotes where seen.insert(emote.id).inserted {
            result.append(emote)
        }
        return result
    }

    /// ユーザーエモートの ID セットを返す
    ///
    /// `EmotePickerViewModel` が使用可否を判定するために使用する。
    /// `/helix/chat/emotes/user` から取得したエモートのIDのみ含む。
    ///
    /// - Returns: ユーザーエモートの ID の Set
    func userEmoteIdSet() -> Set<String> {
        Set(userEmotes.map(\.id))
    }

    /// 現在のユーザーエモート一覧のスナップショットを返す
    ///
    /// `ChannelManager` が新しい `ChatViewModel` のエモートストアにユーザーエモートを
    /// シードする際に使用する。スナップショットはプリロード完了分のみを含む。
    ///
    /// - Returns: 現在のユーザーエモート一覧（未ロードの場合は空配列）
    func userEmotesSnapshot() -> [HelixEmote] {
        userEmotes
    }

    /// 現在のチャンネルエモート一覧のスナップショットを返す
    ///
    /// `EmotePickerViewModel` がセクション分けされたエモート一覧を構築する際に使用する。
    ///
    /// - Returns: 現在のチャンネルエモート一覧（未ロードの場合は空配列）
    func channelEmotesSnapshot() -> [HelixEmote] {
        channelEmotes
    }

    /// 現在のグローバルエモート一覧のスナップショットを返す
    ///
    /// `EmotePickerViewModel` がセクション分けされたエモート一覧を構築する際に使用する。
    ///
    /// - Returns: 現在のグローバルエモート一覧（未ロードの場合は空配列）
    func globalEmotesSnapshot() -> [HelixEmote] {
        globalEmotes
    }

    /// ユーザーが使用可能なエモートセット ID を更新する
    ///
    /// USERSTATE の `emote-sets` タグを受信するたびに呼び出す。
    /// チャンネル切替時は新チャンネルの USERSTATE が自動的に更新するため、
    /// `resetChannelEmotes()` ではリセットしない。
    ///
    /// - Parameter sets: USERSTATE の emote-sets タグから生成した Set<String>
    func updateUserEmoteSets(_ sets: Set<String>) {
        userEmoteSets = sets
        notifyUserEmoteSetsUpdated()
    }

    /// ユーザーエモートセットをリセットする
    ///
    /// disconnect / ログアウト時に呼び出すことで、前回接続時のセット情報が
    /// 次回接続に持ち越されないようにする。
    func resetUserEmoteSets() {
        userEmoteSets = nil
        notifyUserEmoteSetsUpdated()
    }

    /// ユーザーが使用可能なエモートセット ID のスナップショットを返す
    ///
    /// ViewModel が使用可否を判定するためのスナップショット取得に使用する。
    ///
    /// - Returns: 使用可能なエモートセット ID の Set。`nil` の場合は USERSTATE 未受信。
    func userAvailableEmoteSets() -> Set<String>? {
        userEmoteSets
    }

    /// 次回の `userEmoteSets` 更新を待機する
    ///
    /// ピッカー表示中に USERSTATE が届いた場合に即座に追従するために使用する。
    /// `updateUserEmoteSets` または `resetUserEmoteSets` が呼ばれたときに返る。
    /// タスクキャンセル時は `withTaskCancellationHandler` が Continuation を resume して
    /// リークを防ぐ。キャンセル時は resume するだけで CancellationError は投げない。
    func waitForNextUserEmoteSetsUpdate() async {
        guard !Task.isCancelled else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                userEmoteSetsUpdateContinuations[id] = cont
            }
        } onCancel: {
            Task { await self.resumeContinuation(id: id) }
        }
        userEmoteSetsUpdateContinuations.removeValue(forKey: id)
    }

    /// 登録済みの全 Continuation を resume して更新を通知する
    private func notifyUserEmoteSetsUpdated() {
        let conts = userEmoteSetsUpdateContinuations
        userEmoteSetsUpdateContinuations.removeAll()
        conts.values.forEach { $0.resume() }
    }

    /// 指定 ID の Continuation を resume する（キャンセル時のリーク防止用）
    private func resumeContinuation(id: UUID) {
        guard let cont = userEmoteSetsUpdateContinuations.removeValue(forKey: id) else { return }
        cont.resume()
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

    /// ユーザーエモートのキャッシュをクリアする
    ///
    /// disconnect / ログアウト時に呼び出すことで、前回接続時のエモートを持ち越さないようにする。
    /// チャンネル切替時は呼び出し不要（ユーザーエモートはユーザースコープのため）。
    func resetUserEmotes() {
        userEmotes = []
        isUserEmotesLoaded = false
    }

    /// 進行中のユーザーエモートフェッチタスクをキャンセルする
    ///
    /// disconnect 時に呼び出すことで、不要なネットワークリクエストを中断できる
    func cancelUserEmotesFetch() {
        userEmotesTask?.cancel()
        userEmotesTask = nil
    }

    /// 永続化済みグローバルエモートを読み込んでキャッシュを事前充填する
    ///
    /// チャンネル接続時に呼び出す。TTL（24h）以内のデータなら `isGlobalLoaded = true`
    /// にして後続の `fetchGlobalEmotes()` による API 呼び出しを抑止する（stale-while-revalidate）。
    /// TTL 超過時は古いデータでキャッシュを充填した上で `isGlobalLoaded = false` のままにし、
    /// 後続の `fetchGlobalEmotes()` で再フェッチさせる。
    func seedFromPersistence() async {
        guard !isGlobalLoaded else { return }
        guard let persistence = persistenceService else { return }
        let result = await persistence.loadGlobalEmotesWithTimestamp()
        // emotes が空でも fetchedAt があれば「取得済み空配列」として TTL を適用する
        globalEmotes = result.emotes
        if !result.emotes.isEmpty {
            notifyUserEmoteSetsUpdated()
        }
        if let fetchedAt = result.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.emoteTTL {
            isGlobalLoaded = true
        }
    }

    /// 永続化済みユーザーエモートを読み込んでキャッシュを事前充填する
    ///
    /// `ChannelManager.preloadUserEmotes()` の冒頭で呼び出す。
    /// `setUserEmotes(_:)` と異なり `isUserEmotesLoaded` フラグを立てない。
    /// TTL（24h）以内のデータがある場合のみフラグを立てて後続の `fetchUserEmotes` を抑止する。
    ///
    /// - Parameter userId: 認証済みユーザーの Twitch ユーザー ID
    func seedUserEmotes(userId: String) async {
        guard !isUserEmotesLoaded else { return }
        guard let persistence = persistenceService else { return }
        let result = await persistence.loadUserEmotesWithTimestamp(userId: userId)
        // emotes が空でも fetchedAt があれば「取得済み空配列」として TTL を適用する
        userEmotes = result.emotes
        if !result.emotes.isEmpty {
            notifyUserEmoteSetsUpdated()
        }
        if let fetchedAt = result.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.emoteTTL {
            isUserEmotesLoaded = true
        }
    }

    /// 永続化済みチャンネルエモートを読み込んでキャッシュを事前充填する
    ///
    /// `joinChannel` 時の `fetchChannelEmotes` 呼び出し前にセットする。
    /// チャンネルエモートに loaded フラグはないため、TTL 判定は `fetchChannelEmotes` 冒頭で行う。
    ///
    /// - Parameter broadcasterId: Twitch チャンネルID（数字のみ）
    func seedChannelEmotes(broadcasterId: String) async {
        guard let persistence = persistenceService else { return }
        let result = await persistence.loadChannelEmotesWithTimestamp(broadcasterId: broadcasterId)
        guard !result.emotes.isEmpty else { return }
        channelEmotes = result.emotes
        notifyUserEmoteSetsUpdated()
    }

    // MARK: - write-back

    /// エモートを永続化サービスに非同期保存する（fire-and-forget）
    ///
    /// fetch 成功直後に呼び出すことで、次回起動時の seed を有効にする。
    private func writeBackEmotes(_ emotes: [HelixEmote], scope: EmoteScope) {
        guard let persistence = persistenceService else { return }
        Task { [persistence] in
            do {
                switch scope {
                case .global:
                    try await persistence.saveGlobalEmotes(emotes)
                case .channel(let broadcasterId):
                    try await persistence.saveChannelEmotes(emotes, broadcasterId: broadcasterId)
                case .user(let userId):
                    try await persistence.saveUserEmotes(emotes, userId: userId)
                }
            } catch {
                #if DEBUG
                print("[EmoteStore] write-back 失敗 scope=\(scope.rawValue) error=\(error)")
                #endif
            }
        }
    }

    /// ユーザーエモート一覧を直接設定する
    ///
    /// `ChannelManager` が新規接続チャンネルの `ChatViewModel` にプリロード済み
    /// ユーザーエモートをシードするために使用する。
    /// `isUserEmotesLoaded` を `true` に設定するため、その後の `fetchUserEmotes` は
    /// emote-sets 変化がない限りスキップされる。
    ///
    /// - Parameter emotes: シードするユーザーエモート一覧
    func setUserEmotes(_ emotes: [HelixEmote]) {
        userEmotes = emotes
        isUserEmotesLoaded = true
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

    /// ユーザーエモートセットを直接設定する（テスト用）
    func setUserEmoteSets(_ sets: Set<String>) {
        userEmoteSets = sets
    }

    /// エモートセット更新通知をテストから手動発火する（テスト用）
    func notifyUserEmoteSetsUpdatedForTest() {
        notifyUserEmoteSetsUpdated()
    }
#endif
}
