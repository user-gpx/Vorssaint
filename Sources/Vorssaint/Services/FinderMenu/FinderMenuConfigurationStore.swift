// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Single source of truth for the Finder menu. UserDefaults keeps the
/// editable configuration; the Finder extension only reads the presentation
/// snapshot published next to the IPC files.
final class FinderMenuConfigurationStore {
    static let shared = FinderMenuConfigurationStore()

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = DefaultsKey.finderMenuConfiguration) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> FinderMenuConfiguration {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FinderMenuConfiguration.self, from: data)
        else {
            return .default
        }
        return decoded.normalized().includingMissingDefaultActions()
    }

    func save(_ configuration: FinderMenuConfiguration) throws {
        let normalized = configuration.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(normalized), forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    /// Publishes the snapshot the extension reads. The replacement is atomic,
    /// so a Finder redraw never observes a half-written plist.
    @discardableResult
    func publishSnapshot(rootDirectory: URL,
                         generatedAt: Date = Date(),
                         title: (FinderMenuAction) -> String = { $0.defaultTitle },
                         symbolName: (FinderMenuAction) -> String? = { $0.defaultSymbolName }) throws -> FinderMenuSnapshot {
        try FinderMenuIPCContract.prepare(rootDirectory: rootDirectory)
        let snapshot = FinderMenuSnapshotBuilder.build(configuration: load(),
                                                       generatedAt: generatedAt,
                                                       title: title,
                                                       symbolName: symbolName)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(snapshot)
        let url = FinderMenuIPCContract.snapshotURL(rootDirectory: rootDirectory)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
        return snapshot
    }

    func removeSnapshot(rootDirectory: URL) {
        let url = FinderMenuIPCContract.snapshotURL(rootDirectory: rootDirectory)
        try? FileManager.default.removeItem(at: url)
    }
}
