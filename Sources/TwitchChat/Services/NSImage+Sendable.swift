// NSImage+Sendable.swift
// NSImage に Sendable 準拠を追加する拡張
//
// Swift 6.3+ では AppKit が NSImage を Sendable に準拠させるため拡張不要。
// Swift 6.0.x（Xcode 16.4 以前）では NSImage の Sendable 準拠が macOS 15+ 限定のため、
// macOS 14 デプロイメントターゲットで Task<NSImage?, Never> 等が使用できない。
// @unchecked で実際のスレッドセーフティはキャッシュクラス内の NSLock で保証している。

import AppKit

#if !swift(>=6.3)
// @retroactive: SE-0364 に従い、外部モジュール型への外部プロトコル準拠追加には必須
extension NSImage: @unchecked @retroactive Sendable {}
#endif
