// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Presentation-ready item published by the main app. Titles are resolved
/// before writing the snapshot, so the extension never has to load the app's
/// localization catalog.
struct FinderMenuSnapshotItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: FinderMenuItemKind
    var action: FinderMenuAction?
    var title: String
    var symbolName: String?
    var appPath: String?
    var isEnabled: Bool
    var isDestructive: Bool
}

struct FinderMenuSnapshotGroup: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var isEnabled: Bool
    var itemIDs: [String]
}

struct FinderMenuSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var generatedAt: Date
    var isEnabled: Bool
    var showIcons: Bool
    var items: [FinderMenuSnapshotItem]
    var groups: [FinderMenuSnapshotGroup]

    func validated() throws -> FinderMenuSnapshot {
        guard version == Self.currentVersion else {
            throw FinderMenuSnapshotError.unsupportedVersion(version)
        }
        return self
    }

    /// Ungrouped rows first, then each enabled group in order. The extension
    /// uses this directly, so menu ordering lives in one place.
    func orderedItems() -> [FinderMenuSnapshotItem] {
        var grouped = Set<String>()
        for group in groups where group.isEnabled {
            grouped.formUnion(group.itemIDs)
        }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result = items.filter { !grouped.contains($0.id) }
        for group in groups where group.isEnabled {
            result.append(contentsOf: group.itemIDs.compactMap { byID[$0] })
        }
        return result
    }
}

enum FinderMenuSnapshotError: Error, Equatable {
    case unsupportedVersion(Int)
}

enum FinderMenuSnapshotBuilder {
    /// Builds a snapshot from the normalized configuration. The title and
    /// symbol closures let the main app supply localized strings without
    /// making the shared contract depend on SwiftUI or Combine.
    static func build(
        configuration: FinderMenuConfiguration,
        generatedAt: Date = Date(),
        title: (FinderMenuAction) -> String = { $0.defaultTitle },
        symbolName: (FinderMenuAction) -> String? = { $0.defaultSymbolName }
    ) -> FinderMenuSnapshot {
        let normalized = configuration.normalized()
        let rows = normalized.items.map { item -> FinderMenuSnapshotItem in
            switch item.kind {
            case .action:
                let action = item.action ?? .copyPath
                return FinderMenuSnapshotItem(
                    id: item.id,
                    kind: .action,
                    action: action,
                    title: item.customTitle ?? title(action),
                    symbolName: item.customSymbolName ?? symbolName(action),
                    appPath: nil,
                    isEnabled: item.isEnabled,
                    isDestructive: action.isDestructive
                )
            case .application:
                let path = item.appPath ?? ""
                let defaultTitle = (path as NSString).lastPathComponent
                    .replacingOccurrences(of: ".app", with: "")
                return FinderMenuSnapshotItem(
                    id: item.id,
                    kind: .application,
                    action: .openWithApp,
                    title: item.customTitle ?? defaultTitle,
                    symbolName: item.customSymbolName,
                    appPath: path,
                    isEnabled: item.isEnabled,
                    isDestructive: false
                )
            }
        }
        let groups = normalized.groups.map { group in
            FinderMenuSnapshotGroup(
                id: group.id,
                title: group.title ?? group.id,
                isEnabled: group.isEnabled,
                itemIDs: group.itemIDs
            )
        }
        return FinderMenuSnapshot(version: FinderMenuSnapshot.currentVersion,
                                  generatedAt: generatedAt,
                                  isEnabled: normalized.isEnabled,
                                  showIcons: normalized.showIcons,
                                  items: rows,
                                  groups: groups)
    }
}
