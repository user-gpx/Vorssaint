// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Shared filesystem and notification names for the main app and its Finder
/// Sync extension. The extension sandbox cannot see the app's container, so
/// both sides use a private, permission-restricted directory under `/private/tmp`.
enum FinderMenuIPCContract {
    static let version = FinderMenuRequest.currentVersion

    static let stableNamespace = "com.vorssaint.finder-menu"
    static let developerNamespace = "com.vorssaint.finder-menu.dev"

    static let snapshotFileName = "menu.plist"
    static let requestsDirectoryName = "requests"
    static let responsesDirectoryName = "responses"

    static let requestNotification = "com.vorssaint.finderMenu.request"
    static let responseNotification = "com.vorssaint.finderMenu.response"

    static func rootDirectory(namespace: String = stableNamespace) -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    static func snapshotURL(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    static func requestsDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent(requestsDirectoryName, isDirectory: true)
    }

    static func responsesDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent(responsesDirectoryName, isDirectory: true)
    }

    static func requestURL(id: UUID, rootDirectory: URL) -> URL {
        requestsDirectory(rootDirectory: rootDirectory)
            .appendingPathComponent("\(id.uuidString).plist", isDirectory: false)
    }

    static func responseURL(id: UUID, rootDirectory: URL) -> URL {
        responsesDirectory(rootDirectory: rootDirectory)
            .appendingPathComponent("\(id.uuidString).plist", isDirectory: false)
    }

    /// Creates the shared layout with owner-only permissions. Called by the
    /// main app before publishing a snapshot and by the extension before
    /// writing its first request.
    @discardableResult
    static func prepare(rootDirectory: URL,
                        fileManager: FileManager = .default) throws -> URL {
        let directories = [
            rootDirectory,
            requestsDirectory(rootDirectory: rootDirectory),
            responsesDirectory(rootDirectory: rootDirectory)
        ]
        for directory in directories {
            try fileManager.createDirectory(at: directory,
                                            withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700],
                                          ofItemAtPath: directory.path)
        }
        return rootDirectory
    }

    /// Request and response files are named after their UUID. Ignore anything
    /// else so a stray file in the directory cannot be mistaken for work.
    static func isMessageFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".plist") else { return false }
        let stem = String(name.dropLast(".plist".count))
        return UUID(uuidString: stem) != nil
    }
}
