// KeychainStore.swift
// Keychain へのトークン保存・取得・削除を提供するサービス
// Security framework の SecItem* API をラップし、actor で排他制御する

import Foundation
import Security

/// Keychain へのトークン保存・取得・削除を行うサービス
///
/// actor で排他制御し、並行アクセスを安全にする
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
    /// open ACL の生成に失敗した場合は保存を中断し `accessCreationFailed` を throw する。
    ///
    /// - Parameters:
    ///   - key: 保存キー名
    ///   - value: 保存する文字列値
    /// - Throws: `KeychainError.saveFailed` Keychain 操作に失敗した場合
    ///           `KeychainError.accessCreationFailed` open ACL 生成に失敗した場合
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.saveFailed(status: errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // 既存アイテムがあれば削除してから追加する。
        // SecItemUpdate は既存の ACL を引き継ぐため open ACL に更新できない。
        // errSecItemNotFound は「存在しない」を意味するため正常扱い。それ以外の失敗はエラーとする。
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.saveFailed(status: deleteStatus)
        }

        // trustedList を nil にすることで任意のアプリからアクセス可能な open ACL を設定する。
        // SPM ビルドごとにバイナリのコード署名が変わっても Keychain 許可ダイアログが表示されなくなる。
        // ACL 生成に失敗した場合は保存を中断する（デフォルト ACL での暗黙保存を防ぐ）。
        guard let access = makeOpenAccess() else {
            throw KeychainError.accessCreationFailed
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccess as String] = access
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

    // MARK: - プライベートメソッド

    /// trustedList が nil の open ACL を持つ SecAccess を作成する
    ///
    /// nil の trustedList はすべてのアプリケーションからのアクセスを許可する。
    /// これにより SPM ビルドごとにバイナリが変わっても Keychain 許可ダイアログが表示されない。
    /// - Note: SecAccessCreate は macOS 10.10 で deprecated だが、
    ///   App Store 外の SPM アプリで open ACL を設定する唯一の方法として使用する。
    /// - Returns: 生成した `SecAccess`。失敗した場合は `nil`
    private func makeOpenAccess() -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate("TwitchChat Token" as CFString, nil, &access)
        guard status == errSecSuccess else {
            #if DEBUG
            print("[KeychainStore] SecAccessCreate failed: OSStatus=\(status)")
            #endif
            return nil
        }
        return access
    }
}

// MARK: - エラー定義

/// Keychain 操作エラー
enum KeychainError: Error, Equatable {
    /// 保存に失敗した（OSStatus コード付き）
    case saveFailed(status: OSStatus)
    /// open ACL（SecAccess）の生成に失敗した
    case accessCreationFailed
}
