// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Context-sensitive filtering for a snapshot row. The extension never reads
/// the selected files' contents, so these checks intentionally stay shallow;
/// the main app validates existence and permissions before acting.
enum FinderMenuBuilder {
    static let extractExtensions: Set<String> = [
        "tar", "rar", "rar5", "arj", "cab", "chm", "cpio", "deb", "dmg",
        "fat", "hfs", "iso", "lzh", "lha", "lzma", "mbr", "msi", "nsis",
        "ntfs", "rpm", "squashfs", "udf", "uefi", "vdi", "vhd", "vmdk",
        "xar", "7z", "zip", "gz"
    ]

    static func isEligible(_ item: FinderMenuSnapshotItem, selected: [URL]) -> Bool {
        guard item.isEnabled else { return false }
        switch item.kind {
        case .application:
            guard let path = item.appPath else { return false }
            return !selected.isEmpty && FileManager.default.fileExists(atPath: path)
        case .action:
            guard let action = item.action else { return false }
            switch action {
            case .compress, .copyPath, .copy, .cut, .delete:
                return !selected.isEmpty
            case .extract:
                guard !selected.isEmpty else { return false }
                return selected.contains {
                    extractExtensions.contains($0.pathExtension.lowercased())
                }
            case .uninstallApp:
                return selected.count == 1
                    && selected[0].pathExtension.lowercased() == "app"
            case .paste:
                return pasteboardHasFileURLs()
            case .newTerminal, .hiddenFiles, .emptyTrash, .newFile, .networkInfo, .restartFinder:
                return true
            case .openWithApp:
                guard let path = item.appPath else { return false }
                return !selected.isEmpty && FileManager.default.fileExists(atPath: path)
            }
        }
    }

    static func image(for item: FinderMenuSnapshotItem,
                      showIcons: Bool) -> NSImage? {
        guard showIcons else { return nil }
        let image: NSImage?
        switch item.kind {
        case .application:
            image = item.appPath.map { NSWorkspace.shared.icon(forFile: $0) }
        case .action:
            image = item.symbolName.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
        }
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func pasteboardHasFileURLs() -> Bool {
        NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }
}
