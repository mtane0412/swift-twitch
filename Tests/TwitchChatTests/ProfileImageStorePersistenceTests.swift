// ProfileImageStorePersistenceTests.swift
// ProfileImageStore の永続化配線テスト（キャッシュ先読み / write-back / clear 後の復元）

import Foundation
import Testing
@testable import TwitchChat

/// ProfileImageStore の永続化配線テストスイート
@Suite("ProfileImageStorePersistenceTests")
@MainActor
struct ProfileImageStorePersistenceTests {

    // MARK: - ヘルパー

    /// テスト用ユーザープロフィールスナップショットを生成する
    private func makeYamadaProfile() -> UserProfileSnapshot {
        UserProfileSnapshot(
            userId: "ユーザーID001",
            login: "yamada_taro",
            displayName: "山田太郎",
            profileImageUrl: "https://cdn.example.com/profile/yamada.png"
        )
    }

    private func makeSatoProfile() -> UserProfileSnapshot {
        UserProfileSnapshot(
            userId: "ユーザーID002",
            login: "sato_hanako",
            displayName: "佐藤花子",
            profileImageUrl: nil
        )
    }

    // MARK: - キャッシュ先読み（API 呼び出し抑制）

    @Test("永続化済みプロフィールはfetchUsers呼び出し時にAPIを呼ばずに解決される")
    func 永続化済みプロフィールはfetchUsers呼び出し時にAPIを呼ばずに解決される() async {
        // 前提: 山田太郎のプロフィールを InMemoryPersistenceService に事前保存する
        let persistence = InMemoryPersistenceService()
        let yamada = makeYamadaProfile()
        try? await persistence.saveUserProfiles([yamada])

        // 前提: API クライアントは呼ばれてはならない（永続化から解決できるため）
        let apiClient = MockProfileImageAPIClient()

        // 操作: persistenceService 付きで ProfileImageStore を初期化し fetchUsers を呼ぶ
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API は呼ばれなかった
        let callCount = await apiClient.callCount
        #expect(callCount == 0)

        // 検証: 永続化から復元されたプロフィールで表示名・画像URLを解決できる
        let displayName = await store.displayName(for: "ユーザーID001")
        let imageURL = await store.profileImageUrl(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
        #expect(imageURL?.absoluteString == "https://cdn.example.com/profile/yamada.png")
    }

    @Test("永続化にないプロフィールはAPIを呼んで取得する")
    func 永続化にないプロフィールはAPIを呼んで取得する() async {
        // 前提: 永続化サービスは空、API クライアントは山田太郎を返す
        let persistence = InMemoryPersistenceService()
        let apiClient = MockProfileImageAPIClient()
        await apiClient.setUsers([
            HelixUserData(
                id: "ユーザーID001",
                login: "yamada_taro",
                displayName: "山田太郎",
                profileImageUrl: URL(string: "https://cdn.example.com/profile/yamada.png")
            )
        ])

        // 操作: fetchUsers を呼ぶ（永続化にないので API を呼ぶはず）
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API が1回呼ばれた
        let callCount = await apiClient.callCount
        #expect(callCount == 1)

        // 検証: displayName が解決できる
        let displayName = await store.displayName(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
    }

    // MARK: - write-back

    @Test("APIフェッチ後にプロフィールが永続化サービスに保存される")
    func APIフェッチ後にプロフィールが永続化サービスに保存される() async {
        // 前提: 空の永続化サービスと、山田太郎・佐藤花子を返す API クライアント
        let persistence = InMemoryPersistenceService()
        let apiClient = MockProfileImageAPIClient()
        await apiClient.setUsers([
            HelixUserData(
                id: "ユーザーID001",
                login: "yamada_taro",
                displayName: "山田太郎",
                profileImageUrl: URL(string: "https://cdn.example.com/profile/yamada.png")
            ),
            HelixUserData(
                id: "ユーザーID002",
                login: "sato_hanako",
                displayName: "佐藤花子",
                profileImageUrl: nil
            )
        ])

        // 操作: fetchUsers で2ユーザーを取得する
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)
        await store.fetchUsers(userIds: ["ユーザーID001", "ユーザーID002"])

        // write-back は Task で非同期に行うため少し待機する
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 検証: 永続化サービスに両ユーザーのプロフィールが保存されている
        let saved = await persistence.loadUserProfiles(userIds: ["ユーザーID001", "ユーザーID002"])
        #expect(saved.count == 2)
        #expect(saved.map(\.displayName).contains("山田太郎"))
        #expect(saved.map(\.displayName).contains("佐藤花子"))
    }

    // MARK: - clear 後の復元

    @Test("clear後にfetchUsersを呼ぶと永続化キャッシュから復元されAPIを呼ばない")
    func clear後にfetchUsersを呼ぶと永続化キャッシュから復元されAPIを呼ばない() async {
        // 前提: 永続化に山田太郎を保存済み
        let persistence = InMemoryPersistenceService()
        let yamada = makeYamadaProfile()
        try? await persistence.saveUserProfiles([yamada])

        let apiClient = MockProfileImageAPIClient()
        let store = ProfileImageStore(apiClient: apiClient, persistenceService: persistence)

        // 操作: まず fetchUsers を呼んでキャッシュに入れる
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 操作: clear() を呼ぶ（in-memory キャッシュを消去、永続化データは保持）
        await store.clear()

        // 操作: 再度 fetchUsers を呼ぶ
        await store.fetchUsers(userIds: ["ユーザーID001"])

        // 検証: API は呼ばれなかった（永続化から復元）
        let callCount = await apiClient.callCount
        #expect(callCount == 0)

        // 検証: clear 後でも displayName が解決できる
        let displayName = await store.displayName(for: "ユーザーID001")
        #expect(displayName == "山田太郎")
    }
}
