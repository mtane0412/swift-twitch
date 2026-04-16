// ChannelManagerTests.swift
// ChannelManager の単体テスト
// MockTwitchIRCClient と MockHelixAPIClient を使って複数チャンネル管理の振る舞いを検証する

import Testing
import Foundation
@testable import TwitchChat

@Suite("ChannelManager テスト")
@MainActor
struct ChannelManagerTests {

    // MARK: - 初期状態

    @Test("初期状態はチャンネルなし、選択チャンネルなし")
    func testInitialState() {
        let manager = ChannelManager(authState: AuthState())

        #expect(manager.channels.isEmpty)
        #expect(manager.channelOrder.isEmpty)
        #expect(manager.selectedChannel == nil)
        #expect(manager.selectedViewModel == nil)
    }

    // MARK: - チャンネル参加

    @Test("joinChannel で新しいチャンネルに接続できる")
    func testJoinNewChannel() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        // チャンネル名は小文字なので正規化しても変わらない
        await manager.joinChannel("haishinsha1")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.channels.count == 1)
        #expect(manager.channelOrder == ["haishinsha1"])
        #expect(manager.selectedChannel == "haishinsha1")
        #expect(manager.selectedViewModel != nil)
    }

    @Test("複数チャンネルに同時接続できる")
    func testJoinMultipleChannels() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // 両チャンネルが接続中であること
        #expect(manager.channels.count == 2)
        #expect(manager.channelOrder.contains("haishinsha1"))
        #expect(manager.channelOrder.contains("haishinsha2"))
        // 最後に選択したチャンネルが表示されること
        #expect(manager.selectedChannel == "haishinsha2")
    }

    @Test("joinChannel は既存チャンネルへの再参加時に選択のみ切り替える")
    func testJoinExistingChannelSwitchesSelection() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // haishinsha1 を再度 join → 接続数は増えず選択が切り替わること
        await manager.joinChannel("haishinsha1")
        #expect(manager.channels.count == 2)
        #expect(manager.selectedChannel == "haishinsha1")
    }

    @Test("チャンネル名は小文字に正規化される")
    func testChannelNameNormalized() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        // 大文字混じりの名前を渡しても小文字で管理される
        await manager.joinChannel("NintendoJP")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.channels["nintendojp"] != nil)
        #expect(manager.selectedChannel == "nintendojp")
    }

    // MARK: - チャンネル退出

    @Test("leaveChannel で接続を切断してリストから削除される")
    func testLeaveChannel() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.leaveChannel("haishinsha1")

        #expect(manager.channels.count == 1)
        #expect(manager.channels["haishinsha1"] == nil)
        #expect(manager.channelOrder == ["haishinsha2"])
    }

    @Test("選択中のチャンネルを退出すると選択が解除される")
    func testLeaveSelectedChannelClearsSelection() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.leaveChannel("haishinsha1")

        #expect(manager.selectedChannel == nil)
        #expect(manager.selectedViewModel == nil)
    }

    @Test("disconnectAll で全チャンネルが切断される")
    func testDisconnectAll() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        await manager.joinChannel("haishinsha3")
        try await Task.sleep(nanoseconds: 50_000_000)

        await manager.disconnectAll()

        #expect(manager.channels.isEmpty)
        #expect(manager.channelOrder.isEmpty)
        #expect(manager.selectedChannel == nil)
    }

    @Test("選択中チャンネルを退出すると直前のチャンネルが選択される")
    func testLeaveSelectedChannelFallsBackToPreviousChannel() async throws {
        // 2チャンネル接続中にhaishinsha2（選択中）を退出すると、haishinsha1が選択される
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.selectedChannel == "haishinsha2")

        await manager.leaveChannel("haishinsha2")

        #expect(manager.selectedChannel == "haishinsha1")
        #expect(manager.channels.count == 1)
    }

    // MARK: - selectChannel / isJoined

    @Test("selectChannel で未接続チャンネルを指定しても selectedChannel は変化しない")
    func testSelectChannelIgnoresNonJoined() {
        // 前提: どのチャンネルにも接続していない
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        // 未接続チャンネルを selectChannel しても selectedChannel は nil のまま
        manager.selectChannel("みんなの配信者")
        #expect(manager.selectedChannel == nil)
    }

    @Test("selectChannel で既接続チャンネルに切り替えられる")
    func testSelectChannelSwitchesSelection() async throws {
        // 前提: haishinsha1 と haishinsha2 の 2 チャンネルに接続済み
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // haishinsha2 が選択中のときに haishinsha1 を selectChannel する
        #expect(manager.selectedChannel == "haishinsha2")
        manager.selectChannel("haishinsha1")

        // channels の数は変化せず、selectedChannel だけ切り替わること
        #expect(manager.selectedChannel == "haishinsha1")
        #expect(manager.channels.count == 2)
    }

    @Test("selectChannel を呼んでも IRC クライアントの connect は再発火しない")
    func testSelectChannelDoesNotReconnect() async throws {
        // 前提: haishinsha1 と haishinsha2 に接続済み
        var mockClients: [MockTwitchIRCClient] = []
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: {
            let client = MockTwitchIRCClient()
            mockClients.append(client)
            return client
        })

        await manager.joinChannel("haishinsha1")
        await manager.joinChannel("haishinsha2")
        try await Task.sleep(nanoseconds: 50_000_000)

        // この時点での各クライアントの接続呼び出し回数を取得
        let countsBefore = await withTaskGroup(of: Int.self) { group in
            for client in mockClients {
                group.addTask { await client.connectCallCount }
            }
            var results: [Int] = []
            for await count in group { results.append(count) }
            return results
        }

        // selectChannel を呼ぶ（再接続が走らないことを検証）
        manager.selectChannel("haishinsha1")
        try await Task.sleep(nanoseconds: 50_000_000)

        // connect の呼び出し回数が増えていないこと
        let countsAfter = await withTaskGroup(of: Int.self) { group in
            for client in mockClients {
                group.addTask { await client.connectCallCount }
            }
            var results: [Int] = []
            for await count in group { results.append(count) }
            return results
        }

        #expect(countsBefore.reduce(0, +) == countsAfter.reduce(0, +))
    }

    @Test("isJoined は接続中のチャンネルに true を返す")
    func testIsJoinedReturnsTrueForJoinedChannel() async throws {
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("haishinsha_yamada")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(manager.isJoined("haishinsha_yamada") == true)
    }

    @Test("isJoined は未接続のチャンネルに false を返す")
    func testIsJoinedReturnsFalseForNonJoinedChannel() {
        let manager = ChannelManager(authState: AuthState())

        #expect(manager.isJoined("未接続チャンネル") == false)
    }

    @Test("selectChannel と isJoined は大文字混在のチャンネル名を正規化して扱う")
    func testSelectChannelAndIsJoinedNormalizesChannelName() async throws {
        // 前提: 小文字 "nintendojp" で接続済み
        let manager = ChannelManager(authState: AuthState(), makeIRCClient: { MockTwitchIRCClient() })

        await manager.joinChannel("nintendojp")
        try await Task.sleep(nanoseconds: 50_000_000)

        // 大文字混在で isJoined を呼んでも true が返ること
        #expect(manager.isJoined("NintendoJP") == true)

        // 大文字混在で selectChannel を呼んでも selectedChannel が正規化された名前に切り替わること
        manager.selectChannel("NintendoJP")
        #expect(manager.selectedChannel == "nintendojp")
    }
}
