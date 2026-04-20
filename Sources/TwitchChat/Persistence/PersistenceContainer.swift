// PersistenceContainer.swift
// PersistenceService インスタンスを束ねる Sendable ラッパー
// DI 配線の窓口として TwitchChatApp から各ストアへ service を渡す際に使用する

import Foundation
import SwiftData

/// PersistenceService インスタンスを保持する Sendable ラッパー
///
/// ディスク永続化が必要な場合は `makeOnDisk()` を使用し、
/// `TwitchChatApp` の呼び出しを `(try? .makeOnDisk()) ?? .makeInMemory()` に変更する。
/// 構築失敗時のフォールバックは呼び出し側で行う。
struct PersistenceContainer: Sendable {
    /// 永続化サービスの実体
    let service: any PersistenceService

    /// インメモリ実装で初期化する（テスト・フォールバック用）
    static func makeInMemory() -> PersistenceContainer {
        PersistenceContainer(service: InMemoryPersistenceService())
    }

    /// SwiftData ディスク永続化で初期化する
    ///
    /// Application Support 配下の SQLite ファイルにデータを保存する。
    /// 構築に失敗した場合は呼び出し側で `makeInMemory()` にフォールバックすること。
    ///
    /// - Throws: ディレクトリ作成または `ModelContainer` の構築に失敗した場合
    static func makeOnDisk() throws -> PersistenceContainer {
        let storeURL = try defaultOnDiskStoreURL()
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ChatSchemaMigrationPlan.self,
            configurations: config
        )
        return PersistenceContainer(service: SwiftDataPersistenceService(container: container))
    }

    /// Application Support 配下の SQLite ファイル URL を返す
    private static func defaultOnDiskStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleId = Bundle.main.bundleIdentifier ?? "TwitchChat"
        let dir = base.appending(path: bundleId, directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appending(path: "TwitchChat.sqlite", directoryHint: .notDirectory)
    }
}
