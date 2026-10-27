// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Cocoa
import FinderSync

/// Finder Sync entry point. It only renders the snapshot published by the
/// main app and forwards a validated request; file operations and dialogs stay
/// in Vorssaint.
final class FinderSync: FIFinderSync {
    private var tokens: [Int: FinderMenuSnapshotItem] = [:]
    private var nextTag = 1

    private var rootDirectory: URL {
#if VORSSAINT_DEVELOPMENT
        FinderMenuIPCContract.rootDirectory(namespace: FinderMenuIPCContract.developerNamespace)
#else
        FinderMenuIPCContract.rootDirectory()
#endif
    }

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        FinderMenuLog.write("[VorssaintFinderMenu] init bundle=\(Bundle.main.bundlePath) root=\(rootDirectory.path)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        FinderMenuLog.write("[VorssaintFinderMenu] menu kind=\(menuKind.rawValue) selected=\(selected.count) targeted=\(FIFinderSyncController.default().targetedURL()?.path ?? "nil")")

        guard let snapshot = FinderMenuSnapshotReader.read(rootDirectory: rootDirectory),
              snapshot.isEnabled
        else {
            FinderMenuLog.write("[VorssaintFinderMenu] menu skipped: unable to read enabled snapshot at \(rootDirectory.path)")
            return nil
        }

        let menu = NSMenu(title: "Vorssaint")
        tokens.removeAll()
        nextTag = 1

        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        let groupedIDs = Set(snapshot.groups.filter(\.isEnabled).flatMap(\.itemIDs))

        for item in snapshot.orderedItems() where !groupedIDs.contains(item.id) {
            add(item, to: menu, selected: selected, showIcons: snapshot.showIcons)
        }

        for group in snapshot.groups where group.isEnabled {
            let submenu = NSMenu(title: group.title)
            for id in group.itemIDs {
                guard let item = byID[id] else { continue }
                add(item, to: submenu, selected: selected, showIcons: snapshot.showIcons)
            }
            guard submenu.numberOfItems > 0 else { continue }
            let parent = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            parent.submenu = submenu
            if snapshot.showIcons {
                parent.image = NSImage(systemSymbolName: "folder",
                                       accessibilityDescription: nil)
                parent.image?.size = NSSize(width: 16, height: 16)
            }
            menu.addItem(parent)
        }

        FinderMenuLog.write("[VorssaintFinderMenu] menu built items=\(menu.numberOfItems)")
        return menu.numberOfItems > 0 ? menu : nil
    }

    @discardableResult
    private func add(_ item: FinderMenuSnapshotItem,
                     to menu: NSMenu,
                     selected: [URL],
                     showIcons: Bool) -> Bool {
        guard FinderMenuBuilder.isEligible(item, selected: selected) else { return false }
        let menuItem = NSMenuItem(title: item.title,
                                  action: #selector(performMenuAction(_:)),
                                  keyEquivalent: "")
        menuItem.target = self
        menuItem.tag = nextTag
        menuItem.image = FinderMenuBuilder.image(for: item, showIcons: showIcons)
        tokens[nextTag] = item
        nextTag += 1
        menu.addItem(menuItem)
        return true
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let item = tokens[sender.tag] else { return }
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []

        if item.action == .copyPath {
            copyPaths(selected)
            return
        }
        guard let action = item.action else { return }

        let request = FinderMenuRequest(
            action: action,
            selectedPaths: selected.map(\.path),
            targetDirectory: targetDirectory(selected: selected),
            appPath: item.appPath
        )
        do {
            try FinderMenuIPCClient(rootDirectory: rootDirectory).send(request)
        } catch {
            FinderMenuLog.write("[VorssaintFinderMenu] request failed: \(String(describing: error))")
            NSSound.beep()
        }
    }

    private func copyPaths(_ selected: [URL]) {
        guard !selected.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selected.map(\.path).joined(separator: "\n"),
                             forType: .string)
    }

    private func targetDirectory(selected: [URL]) -> String? {
        let fileManager = FileManager.default
        if let targeted = FIFinderSyncController.default().targetedURL() {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: targeted.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return targeted.path
            }
        }
        guard let first = selected.first else { return nil }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: first.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return first.path
        }
        return first.deletingLastPathComponent().path
    }
}
