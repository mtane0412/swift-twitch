// KeychainStore.swift
// Keychain へのトークン保存・取得・削除を提供するサービス
// Security framework の SecItem* API をラップし、actor で排他制御する
// SecAccessCreate (deprecated macOS 12.0+) は使用せず、SecItemAdd 時に
// kSecAttrAccessible でアクセシビリティのみを設定する

import Foundation
import Security

/// Keychain へのトークン保存・取得・削除を行うサービス
///
/// actor で排他制御し、並行アクセスを安全にする。
/// `SecAccessCreate` (deprecated) を使用せず、`kSecAttrAccessible` のみで
/// アクセシビリティを設定する。
/// - Note: `service` をテスト用に変更することで、本番 Keychain との干渉を防げる
actor KeychainStore {

    // MARK: - プロパティ

    /// Keychain アイテムのサービス名（アプリ識別子）
    private let service: String

    // MARK: - 初期化

    /// KeychainStore を初期化する
    ///
    /// - Parameter service: Keychain サービス名（デフォルト: アプリの Bundle ID）
    init(service: String = "com.mtane0412.TwitchChat") {
        self.service = service
    }

    // MARK: - パブリックメソッド

    /// 指定キーに文字列値を保存する
    ///
    /// 既存のアイテムがある場合は削除してから追加する（SecItemUpdate は ACL を引き継ぐため）。
    ///
    /// - Parameters:
    ///   - key: 保存キー名
    ///   - value: 保存する文字列値
    /// - Throws: `KeychainError.saveFailed` Keychain 操作に失敗した場合
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.saveFailed(status: errSecParam)
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // 既存アイテムがあれば削除してから追加する。
        // SecItemUpdate は既存の ACL を引き継ぐため上書きではなく削除→追加にする。
        // errSecItemNotFound は「存在しない」を意味するため正常扱い。
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.saveFailed(status: deleteStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        // 再起動後の初回ロック解除後はバックグラウンドからもアクセス可能にする。
        // macOS アプリの OAuth トークン保管として適切なアクセシビリティ。
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// 指定キーの文字列値を取得する
    ///
    /// - Parameter key: 取得キー名
    /// - Returns: 保存されていた文字列値。存在しない場合は `nil`
    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #if DEBUG
        if status != errSecSuccess {
            print("[KeychainStore] load(\(key)) failed: OSStatus=\(status)")
        }
        #endif
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// 指定キーのアイテムを削除する
    ///
    /// アイテムが存在しない場合はエラーにならない
    ///
    /// - Parameter key: 削除キー名
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// このサービスに属するすべての Keychain アイテムを削除する
    ///
    /// ログアウト時に全トークンを一括削除する際に使用する
    /// - Note: macOS の `SecItemDelete` は 1 回の呼び出しで 1 アイテムのみ削除することがあるため、
    ///   `errSecItemNotFound` が返るまでループする
    func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        while SecItemDelete(query as CFDictionary) == errSecSuccess {}
    }
}

// MARK: - エラー定義

/// Keychain 操作エラー
enum KeychainError: Error, Equatable {
    /// 保存に失敗した（OSStatus コード付き）
    case saveFailed(status: OSStatus)
}
