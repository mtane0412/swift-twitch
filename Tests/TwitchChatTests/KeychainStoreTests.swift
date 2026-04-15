// KeychainStoreTests.swift
// Keychain へのトークン保存・取得・削除のテスト
// KeychainStore actor の CRUD 操作を検証する

import Testing
@testable import TwitchChat

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {

    // MARK: - save / load

    @Test("アクセストークンを保存して取得できる")
    func アクセストークンを保存して取得できる() async throws {
        // テストごとに一意のサービス名を使用して Keychain の干渉を防ぐ
        let store = KeychainStore(service: "com.test.KeychainStore.save")
        defer { Task { await store.deleteAll() } }

        // 保存
        try await store.save(key: "access_token", value: "テスト用アクセストークン1234")

        // 取得できることを確認
        let loaded = await store.load(key: "access_token")
        #expect(loaded == "テスト用アクセストークン1234")
    }

    @Test("存在しないキーを取得するとnilを返す")
    func 存在しないキーを取得するとnilを返す() async {
        let store = KeychainStore(service: "com.test.KeychainStore.notfound")

        let result = await store.load(key: "存在しないキー_xyzabc")
        #expect(result == nil)
    }

    @Test("同じキーで保存すると値が上書きされる")
    func 同じキーで保存すると値が上書きされる() async throws {
        let store = KeychainStore(service: "com.test.KeychainStore.overwrite")
        defer { Task { await store.deleteAll() } }

        // 初回保存
        try await store.save(key: "refresh_token", value: "古いリフレッシュトークン")
        // 上書き保存
        try await store.save(key: "refresh_token", value: "新しいリフレッシュトークン")

        // 最新の値が取得できることを確認
        let loaded = await store.load(key: "refresh_token")
        #expect(loaded == "新しいリフレッシュトークン")
    }

    // MARK: - delete

    @Test("削除後にキーを取得するとnilを返す")
    func 削除後にキーを取得するとnilを返す() async throws {
        let store = KeychainStore(service: "com.test.KeychainStore.delete")

        // 保存してから削除
        try await store.save(key: "user_id", value: "ユーザーID_67890")
        await store.delete(key: "user_id")

        // 削除後は nil になることを確認
        let result = await store.load(key: "user_id")
        #expect(result == nil)
    }

    @Test("存在しないキーを削除してもエラーにならない")
    func 存在しないキーを削除してもエラーにならない() async {
        let store = KeychainStore(service: "com.test.KeychainStore.deletemissing")
        // エラーなく完了することを確認（クラッシュ・例外なし）
        await store.delete(key: "存在しないキー_deletetest")
    }

    // MARK: - deleteAll

    @Test("deleteAllで全キーが削除される")
    func deleteAllで全キーが削除される() async throws {
        let store = KeychainStore(service: "com.test.KeychainStore.deleteall")

        // 複数キーを保存
        try await store.save(key: "access_token", value: "アクセストークン")
        try await store.save(key: "refresh_token", value: "リフレッシュトークン")
        try await store.save(key: "user_login", value: "配信者ログイン名")

        // 一括削除
        await store.deleteAll()

        // 全キーが nil になることを確認
        #expect(await store.load(key: "access_token") == nil)
        #expect(await store.load(key: "refresh_token") == nil)
        #expect(await store.load(key: "user_login") == nil)
    }
}
