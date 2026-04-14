// WebSocketClient.swift
// WebSocket 通信の抽象化プロトコルと URLSession を使った実装
// テスト時はモック実装に差し替えることで実ネットワーク通信を回避できる

import Foundation

/// WebSocket 通信の抽象化プロトコル
///
/// テスト時にモック実装に差し替えられるよう、依存性注入のためのプロトコル
protocol WebSocketClientProtocol: Sendable {
    /// 指定した URL に WebSocket 接続する
    func connect(to url: URL) async throws

    /// テキストメッセージを送信する
    func send(_ message: String) async throws

    /// テキストメッセージを 1 件受信する
    ///
    /// - Returns: 受信したメッセージ文字列
    /// - Throws: 接続切断時は CancellationError または URLError
    func receive() async throws -> String

    /// WebSocket 接続を切断する
    func disconnect() async
}

/// URLSessionWebSocketTask を使った WebSocket クライアント実装
///
/// - Note: macOS 15+ の URLSession WebSocket API を使用する
final class URLSessionWebSocketClient: WebSocketClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(to url: URL) async throws {
        task = session.webSocketTask(with: url)
        task?.resume()
    }

    func send(_ message: String) async throws {
        guard let task else {
            throw URLError(.notConnectedToInternet)
        }
        try await task.send(.string(message))
    }

    func receive() async throws -> String {
        guard let task else {
            throw URLError(.notConnectedToInternet)
        }
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return ""
        }
    }

    func disconnect() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
