// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Stable identities for every action the Finder extension may request.
///
/// The raw values are persisted in the menu configuration and sent over IPC,
/// so cases can be added but existing raw values must never change.
enum FinderMenuAction: String, Codable, CaseIterable, Sendable {
    case compress
    case extract
    case newTerminal
    case copyPath
    case hiddenFiles
    case copy
    case cut
    case paste
    case delete
    case emptyTrash
    case newFile
    case networkInfo
    case uninstallApp
    case restartFinder
    case openWithApp

    /// The menu deliberately stays small. The other identities remain in the
    /// enum so saved configurations and older requests still decode, but they
    /// are filtered out before the menu is published.
    static let defaultOrder: [FinderMenuAction] = [
        .newTerminal, .copy, .cut, .paste, .newFile
    ]

    static let menuActions = Set(defaultOrder)

    var isAvailableInMenu: Bool { Self.menuActions.contains(self) }

    /// English fallback used when no localized title has been published yet.
    var defaultTitle: String {
        switch self {
        case .compress: return "Compress"
        case .extract: return "Extract"
        case .newTerminal: return "New Terminal"
        case .copyPath: return "Copy Path"
        case .hiddenFiles: return "Show Hidden Files"
        case .copy: return "Copy"
        case .cut: return "Cut"
        case .paste: return "Paste"
        case .delete: return "Move to Trash"
        case .emptyTrash: return "Empty Trash"
        case .newFile: return "New File"
        case .networkInfo: return "Network Info"
        case .uninstallApp: return "Uninstall App"
        case .restartFinder: return "Restart Finder"
        case .openWithApp: return "Open With"
        }
    }

    var defaultSymbolName: String {
        switch self {
        case .compress: return "archivebox"
        case .extract: return "shippingbox"
        case .newTerminal: return "terminal"
        case .copyPath: return "doc.on.doc"
        case .hiddenFiles: return "eye.slash"
        case .copy: return "plus.rectangle.on.rectangle"
        case .cut: return "scissors"
        case .paste: return "doc.on.clipboard"
        case .delete: return "trash"
        case .emptyTrash: return "trash.slash"
        case .newFile: return "doc.badge.plus"
        case .networkInfo: return "network"
        case .uninstallApp: return "trash.circle"
        case .restartFinder: return "arrow.clockwise"
        case .openWithApp: return "arrow.up.forward.app"
        }
    }

    var isDestructive: Bool {
        self == .delete || self == .emptyTrash
    }

    /// Some menu items stay visible in an empty folder; the rest need a
    /// selection to have a meaningful target.
    var requiresSelection: Bool {
        switch self {
        case .newTerminal, .hiddenFiles, .paste, .emptyTrash, .newFile, .networkInfo, .restartFinder:
            return false
        default:
            return true
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .newTerminal, .newFile, .uninstallApp:
            return false
        default:
            return true
        }
    }

    /// Applications opened through the submenu carry their own path, so the
    /// request must include one. The other actions never do.
    var requiresApplicationPath: Bool {
        self == .openWithApp
    }
}
