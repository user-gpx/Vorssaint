// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderMenuItemKind: String, Codable, Sendable {
    /// A built-in Finder action.
    case action
    /// A favourite application rendered under an "Open With" submenu.
    case application
}

/// One persisted menu row. Built-in actions use their action raw value as the
/// identity; application rows use `app:<absolute path>`.
struct FinderMenuItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var kind: FinderMenuItemKind
    var action: FinderMenuAction?
    var appPath: String?
    var isEnabled: Bool
    var customTitle: String?
    var customSymbolName: String?

    init(id: String,
         kind: FinderMenuItemKind,
         action: FinderMenuAction?,
         appPath: String? = nil,
         isEnabled: Bool = true,
         customTitle: String? = nil,
         customSymbolName: String? = nil) {
        self.id = id
        self.kind = kind
        self.action = action
        self.appPath = appPath
        self.isEnabled = isEnabled
        self.customTitle = customTitle
        self.customSymbolName = customSymbolName
    }

    static func action(_ action: FinderMenuAction,
                       isEnabled: Bool = true,
                       customTitle: String? = nil,
                       customSymbolName: String? = nil) -> FinderMenuItem {
        FinderMenuItem(id: action.rawValue,
                       kind: .action,
                       action: action,
                       isEnabled: isEnabled,
                       customTitle: customTitle,
                       customSymbolName: customSymbolName)
    }

    static func application(_ path: String,
                            isEnabled: Bool = true,
                            customTitle: String? = nil) -> FinderMenuItem {
        let normalized = Self.normalizedApplicationPath(path)
        return FinderMenuItem(id: "app:\(normalized ?? path)",
                              kind: .application,
                              action: .openWithApp,
                              appPath: normalized,
                              isEnabled: isEnabled,
                              customTitle: customTitle)
    }

    /// Returns a canonical row, or nil when the stored row is not usable.
    func normalized() -> FinderMenuItem? {
        let title = Self.trimmed(customTitle)
        let symbol = Self.trimmed(customSymbolName)

        switch kind {
        case .action:
            guard let action, action.isAvailableInMenu else { return nil }
            return FinderMenuItem(id: action.rawValue,
                                  kind: .action,
                                  action: action,
                                  isEnabled: isEnabled,
                                  customTitle: title,
                                  customSymbolName: symbol)
        case .application:
            guard let path = appPath.flatMap(Self.normalizedApplicationPath) else {
                return nil
            }
            return FinderMenuItem(id: "app:\(path)",
                                  kind: .application,
                                  action: .openWithApp,
                                  appPath: path,
                                  isEnabled: isEnabled,
                                  customTitle: title,
                                  customSymbolName: symbol)
        }
    }

    private static func normalizedApplicationPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r")
        else { return nil }
        let url = URL(fileURLWithPath: trimmed).standardizedFileURL
        guard url.pathExtension.lowercased() == "app" else { return nil }
        return url.path
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

/// An optional submenu. Items not referenced by any group stay at the top
/// level, so a fresh install can ship a flat menu and add groups later.
struct FinderMenuGroup: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String?
    var isEnabled: Bool
    var itemIDs: [String]

    init(id: String, title: String? = nil, isEnabled: Bool = true, itemIDs: [String]) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.itemIDs = itemIDs
    }

    func normalized(itemIDs existing: Set<String>) -> FinderMenuGroup? {
        var seen = Set<String>()
        let valid = itemIDs.filter { existing.contains($0) && seen.insert($0).inserted }
        guard !valid.isEmpty else { return nil }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FinderMenuGroup(id: id,
                               title: (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil,
                               isEnabled: isEnabled,
                               itemIDs: valid)
    }
}

/// The persisted menu configuration. `normalized()` is the only constructor
/// UI and IPC code should trust; it drops stale rows, duplicates and relative
/// application paths instead of failing the whole menu.
struct FinderMenuConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var isEnabled: Bool
    var showIcons: Bool
    var items: [FinderMenuItem]
    var groups: [FinderMenuGroup]

    init(schemaVersion: Int = FinderMenuConfiguration.currentSchemaVersion,
         isEnabled: Bool = true,
         showIcons: Bool = true,
         items: [FinderMenuItem] = FinderMenuConfiguration.defaultItems,
         groups: [FinderMenuGroup] = []) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.showIcons = showIcons
        self.items = items
        self.groups = groups
    }

    static var defaultItems: [FinderMenuItem] {
        FinderMenuAction.defaultOrder.map { .action($0) }
    }

    static var `default`: FinderMenuConfiguration {
        FinderMenuConfiguration()
    }

    func normalized() -> FinderMenuConfiguration {
        var seenItemIDs = Set<String>()
        var rows: [FinderMenuItem] = []
        for item in items {
            guard let normalized = item.normalized(),
                  seenItemIDs.insert(normalized.id).inserted else { continue }
            rows.append(normalized)
        }
        if rows.isEmpty {
            rows = Self.defaultItems
            seenItemIDs = Set(rows.map(\.id))
        }

        var seenGroupIDs = Set<String>()
        var validGroups: [FinderMenuGroup] = []
        for group in groups {
            guard !seenGroupIDs.contains(group.id),
                  let normalized = group.normalized(itemIDs: seenItemIDs) else { continue }
            seenGroupIDs.insert(group.id)
            validGroups.append(normalized)
        }

        return FinderMenuConfiguration(schemaVersion: Self.currentSchemaVersion,
                                       isEnabled: isEnabled,
                                       showIcons: showIcons,
                                       items: rows,
                                       groups: validGroups)
    }

    /// Every row in display order: ungrouped rows first, then enabled groups.
    /// The extension uses this to turn the persisted configuration into
    /// `NSMenu` items without re-implementing the ordering rules.
    func orderedRows() -> [FinderMenuItem] {
        let normalized = normalized()
        var grouped = Set<String>()
        for group in normalized.groups where group.isEnabled {
            grouped.formUnion(group.itemIDs)
        }
        var result = normalized.items.filter { !grouped.contains($0.id) }
        for group in normalized.groups where group.isEnabled {
            let rowsByID = Dictionary(uniqueKeysWithValues: normalized.items.map { ($0.id, $0) })
            result.append(contentsOf: group.itemIDs.compactMap { rowsByID[$0] })
        }
        return result
    }
}
