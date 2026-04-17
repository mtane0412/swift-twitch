// NSImage+Sendable.swift
// NSImage に Sendable 準拠を追加する拡張
//
// Swift 6.1 以前では NSImage が Sendable に準拠していないため、
// Task<NSImage?, Never> 等のジェネリック制約を満たすために @unchecked Sendable を付与する。
// BadgeImageCache / EmoteImageCache / ProfileImageCache でのキャッシュ管理に使用。
// 実際のスレッドセーフティはそれぞれのキャッシュクラス内の NSLock で保証している。

import AppKit

extension NSImage: @unchecked @retroactive Sendable {}
