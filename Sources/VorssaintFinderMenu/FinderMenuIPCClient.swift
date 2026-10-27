// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Writes a request and pokes the main app. The request file is the data;
/// the Darwin notification only makes the app react immediately.
struct FinderMenuIPCClient {
    let rootDirectory: URL

    func send(_ request: FinderMenuRequest) throws {
        try request.validated()
        try FinderMenuIPCContract.prepare(rootDirectory: rootDirectory)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(request)
        let url = FinderMenuIPCContract.requestURL(id: request.id,
                                                   rootDirectory: rootDirectory)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(FinderMenuIPCContract.requestNotification as CFString),
            nil,
            nil,
            true
        )
    }
}
