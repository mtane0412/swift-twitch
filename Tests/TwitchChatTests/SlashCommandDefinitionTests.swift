// SlashCommandDefinitionTests.swift
// SlashCommandDefinition の静的コマンドリスト・構造のテスト

import Testing
@testable import TwitchChat

@Suite("SlashCommandDefinitionTests")
struct SlashCommandDefinitionTests {

    // MARK: - allCommands

    @Test("allCommands が空でないこと")
    func testAllCommandsNotEmpty() {
        #expect(!SlashCommandDefinition.allCommands.isEmpty)
    }

    @Test("allCommands の各コマンドの name が一意であること")
    func testAllCommandNamesAreUnique() {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        let uniqueNames = Set(names)
        // 重複しているコマンド名を特定してメッセージに含める
        let duplicates = names.filter { name in names.filter { $0 == name }.count > 1 }
        let uniqueDuplicates = Array(Set(duplicates)).sorted()
        #expect(
            names.count == uniqueNames.count,
            "重複しているコマンド名: \(uniqueDuplicates.joined(separator: ", "))"
        )
    }

    @Test("allCommands の各コマンドの name に先頭スラッシュが含まれないこと")
    func testCommandNamesDoNotContainLeadingSlash() {
        for command in SlashCommandDefinition.allCommands {
            #expect(!command.name.hasPrefix("/"), "コマンド '\(command.name)' に先頭スラッシュが含まれています")
        }
    }

    @Test("allCommands の各コマンドの description が空でないこと")
    func testAllCommandDescriptionsNotEmpty() {
        for command in SlashCommandDefinition.allCommands {
            #expect(!command.description.isEmpty, "コマンド '\(command.name)' の description が空です")
        }
    }

    // MARK: - Identifiable

    @Test("id は name と一致すること")
    func testIdEqualsName() {
        for command in SlashCommandDefinition.allCommands {
            #expect(
                command.id == command.name,
                "コマンド '\(command.name)' の id '\(command.id)' が name と一致しません"
            )
        }
    }

    // MARK: - 必須コマンドの存在確認

    @Test("主要コマンドが allCommands に定義されていること", arguments: [
        "me", "ban", "timeout", "clear"
    ])
    func testEssentialCommandExists(expectedName: String) {
        let names = SlashCommandDefinition.allCommands.map { $0.name }
        #expect(names.contains(expectedName), "/\(expectedName) コマンドが allCommands に定義されていません")
    }
}
