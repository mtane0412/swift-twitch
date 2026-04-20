// PersistenceContainer.swift
// PersistenceService インスタンスを束ねる Sendable ラッパー
// DI 配線の窓口として TwitchChatApp から各ストアへ service を渡す際に使用する

/// PersistenceService インスタンスを保持する Sendable ラッパー
///
/// PR-1 段階では in-memory 実装のみを提供する。
/// 将来 SwiftData 実装が入る際は `makeOnDisk()` ファクトリを追加し、
/// `TwitchChatApp` の呼び出しを `(try? .makeOnDisk()) ?? .makeInMemory()` に変更する。
struct PersistenceContainer: Sendable {
    /// 永続化サービスの実体
    let service: any PersistenceService

    /// インメモリ実装で初期化する（PR-1 段階）
    static func makeInMemory() -> PersistenceContainer {
        PersistenceContainer(service: InMemoryPersistenceService())
    }
}
