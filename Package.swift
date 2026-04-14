// swift-tools-version: 6.0
// Package.swift
// TwitchChat macOS アプリのパッケージ定義
// Twitch IRC チャットを表示する macOS 15+ ネイティブアプリ

import PackageDescription

let package = Package(
    name: "TwitchChat",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "TwitchChat",
            path: "Sources/TwitchChat"
        ),
        .testTarget(
            name: "TwitchChatTests",
            dependencies: ["TwitchChat"],
            path: "Tests/TwitchChatTests",
            swiftSettings: [
                // CommandLineTools 環境での Testing フレームワーク参照
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
