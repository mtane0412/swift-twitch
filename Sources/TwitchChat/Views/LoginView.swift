// LoginView.swift
// ログイン / ログアウト UI
// ヘッダーエリアに配置し、認証状態に応じてボタンを切り替える

import SwiftUI

/// ログイン / ログアウト UI
///
/// - ログアウト状態: 「Twitch でログイン」ボタンを表示
/// - Device Code Flow 認証中: ユーザーコードとキャンセルボタンを表示
/// - ログイン状態: ユーザー名と「ログアウト」ボタンを表示
/// - `.unknown` 状態（起動直後）: ローディングインジケータを表示
struct LoginView: View {
    /// 認証状態
    var authState: AuthState

    var body: some View {
        VStack(spacing: 2) {
            if let deviceFlow = authState.deviceFlowInfo {
                // Device Code Flow 認証中: ユーザーコードを表示
                deviceFlowView(deviceFlow)
            } else {
                HStack(spacing: 8) {
                    switch authState.status {
                    case .unknown:
                        // 起動直後・セッション復元中
                        ProgressView()
                            .controlSize(.small)
                        Text("認証中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .loggedOut:
                        // ログアウト状態: ログインボタン
                        Button(action: handleLogin) {
                            Label("Twitch でログイン", systemImage: "person.crop.circle.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    case .loggedIn(let userLogin):
                        // ログイン状態: ユーザー名 + ログアウトボタン
                        Label(userLogin, systemImage: "person.crop.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Button(action: handleLogout) {
                            Text("ログアウト")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // エラーメッセージ表示
            if let error = authState.loginError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - サブビュー

    /// Device Code Flow 認証中の UI
    ///
    /// ユーザーコードを表示し、twitch.tv/activate へのアクセスを促す
    @ViewBuilder
    private func deviceFlowView(_ deviceFlow: DeviceFlowInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("twitch.tv/activate でコードを入力:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(deviceFlow.userCode)
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Button("キャンセル", action: handleCancelDeviceFlow)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - アクション

    private func handleLogin() {
        authState.startLogin()
    }

    private func handleLogout() {
        Task {
            await authState.logout()
        }
    }

    private func handleCancelDeviceFlow() {
        authState.cancelDeviceFlow()
    }
}
