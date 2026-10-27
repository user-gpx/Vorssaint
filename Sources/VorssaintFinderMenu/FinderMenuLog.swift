// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Finder Sync diagnostics go to a file because `NSLog` output from an appex
/// is not reliably visible in `log show` on current macOS releases.
enum FinderMenuLog {
    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var rootDirectory: URL {
#if VORSSAINT_DEVELOPMENT
        FinderMenuIPCContract.rootDirectory(namespace: FinderMenuIPCContract.developerNamespace)
#else
        FinderMenuIPCContract.rootDirectory()
#endif
    }

    static func write(_ message: String) {
        let url = rootDirectory.appendingPathComponent("finder-extension.log", isDirectory: false)
        let line = "[\(timestamp.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: rootDirectory,
                                         withIntermediateDirectories: true,
                                         attributes: [.posixPermissions: 0o700])
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                try? data.write(to: url, options: .atomic)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
