// ChannelManager.swift
// 複数チャンネルへの同時接続を管理するオーケストレーター
// チャンネルの参加・退出・選択切替を担当し、各チャンネルの ChatViewModel を保持する

import Foundation
import Observation

/// 複数チャンネル接続を管理するオーケストレーター
///
/// - 各チャンネルに独立した `ChatViewModel` を持つ設計
/// - `joinChannel()` で未接続チャンネルに新規接続、既接続なら選択切替のみ
/// - 接続は明示的に `leaveChannel()` または `disconnectAll()` を呼ぶまで維持される
@Observable
@MainActor
final class ChannelManager {

    // MARK: - 公開プロパティ

    /// 接続中チャンネルの ViewModel（キー: 小文字チャンネル名）
    private(set) var channels: [String: ChatViewModel] = [:]

    /// 接続順を保持する配列（サイドバー表示順）
    private(set) var channelOrder: [String] = []

    /// 現在選択中のチャンネル名
    var selectedChannel: String?

    /// 現在選択中の ChatViewModel
    var selectedViewModel: ChatViewModel? {
        guard let name = selectedChannel else { return nil }
        return channels[name]
    }

    // MARK: - プライベートプロパティ

    private let authState: AuthState
    private let apiClient: any HelixAPIClientProtocol
    /// IRC クライアントファクトリ（テスト時にモックを注入するために使用）
    private let makeIRCClient: @MainActor () -> any TwitchIRCClientProtocol

    // MARK: - 初期化

    /// ChannelManager を初期化する（本番用）
    ///
    /// - Parameter authState: 認証状態（IRC 接続と Helix API 呼び出しに使用）
    init(authState: AuthState) {
        self.authState = authState
        self.apiClient = HelixAPIClient(tokenProvider: authState)
        self.makeIRCClient = { TwitchIRCClient() }
    }

    /// ChannelManager を初期化する（テスト用: IRC クライアントファクトリを注入）
    ///
    /// - Parameters:
    ///   - authState: 認証状態
    ///   - makeIRCClient: IRC クライアントを生成するファクトリクロージャ
    init(
        authState: AuthState,
        makeIRCClient: @escaping @MainActor () -> any TwitchIRCClientProtocol
    ) {
        self.authState = authState
        self.apiClient = HelixAPIClient(tokenProvider: authState)
        self.makeIRCClient = makeIRCClient
    }

    // MARK: - 公開メソッド

    /// 指定チャンネルに参加する
    ///
    /// - 未接続の場合: 新しい `ChatViewModel` を作成して接続開始し、選択状態にする
    /// - 既接続の場合: 接続はそのままで選択状態を切り替えるのみ
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    func joinChannel(_ channelLogin: String) async {
        let normalized = channelLogin.lowercased()

        if channels[normalized] != nil {
            // 既接続 → 選択だけ切り替える
            selectedChannel = normalized
            return
        }

        // 新規接続
        let ircClient = makeIRCClient()
        let viewModel = ChatViewModel(ircClient: ircClient, authState: authState, apiClient: apiClient)
        channels[normalized] = viewModel
        channelOrder.append(normalized)
        selectedChannel = normalized

        // バックグラウンドで接続開始（joinChannel がブロックされないように）
        Task {
            await viewModel.connect(to: normalized)
        }
    }

    /// 指定チャンネルから退出する
    ///
    /// 接続を切断してチャンネルリストから削除する。
    /// 選択中のチャンネルを退出した場合は選択を解除する。
    ///
    /// - Parameter channelLogin: チャンネルのログイン名
    func leaveChannel(_ channelLogin: String) async {
        let normalized = channelLogin.lowercased()

        guard let viewModel = channels[normalized] else { return }

        await viewModel.disconnect()
        channels.removeValue(forKey: normalized)
        channelOrder.removeAll { $0 == normalized }

        if selectedChannel == normalized {
            selectedChannel = channelOrder.last
        }
    }

    /// 指定チャンネルが既に接続中かどうかを返す
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    /// - Returns: 接続中なら `true`、未接続なら `false`
    func isJoined(_ channelLogin: String) -> Bool {
        channels[channelLogin.lowercased()] != nil
    }

    /// 既接続チャンネルを選択状態にする（同期）
    ///
    /// 未接続チャンネルを指定した場合は何もしない。
    /// `joinChannel(_:)` は未接続時に新規接続を開始するが、このメソッドは選択切替のみ行う。
    /// サイドバーのアイコンクリックやタブバーのタブクリックから呼ぶことを想定している。
    ///
    /// - Parameter channelLogin: チャンネルのログイン名（大文字小文字は自動正規化）
    func selectChannel(_ channelLogin: String) {
        let normalized = channelLogin.lowercased()
        guard channels[normalized] != nil else { return }
        selectedChannel = normalized
    }

    /// 指定チャンネルを目的のインデックス位置に移動する
    ///
    /// - 未知のチャンネル名は no-op（クラッシュしない）
    /// - `destinationIndex` は `0...(channelOrder.count - 1)` の範囲に clamp する
    /// - 元の位置と同じ index への移動は no-op（不要な再描画を防ぐ）
    /// - `selectedChannel` は名前ベース管理のため並び替え後も変更不要
    ///
    /// - Parameters:
    ///   - channelLogin: 移動するチャンネル名（大文字小文字は自動正規化）
    ///   - destinationIndex: 移動先のインデックス
    func moveChannel(_ channelLogin: String, toIndex destinationIndex: Int) {
        let normalized = channelLogin.lowercased()
        guard let currentIndex = channelOrder.firstIndex(of: normalized) else { return }
        let clamped = min(max(destinationIndex, 0), channelOrder.count - 1)
        guard currentIndex != clamped else { return }
        let removed = channelOrder.remove(at: currentIndex)
        channelOrder.insert(removed, at: clamped)
    }

    /// 全チャンネルから切断して管理状態をリセットする
    func disconnectAll() async {
        let allChannels = channelOrder
        for channel in allChannels {
            if let viewModel = channels[channel] {
                await viewModel.disconnect()
            }
        }
        channels = [:]
        channelOrder = []
        selectedChannel = nil
    }
}
