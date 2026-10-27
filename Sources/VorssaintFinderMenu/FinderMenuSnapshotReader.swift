// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderMenuSnapshotReader {
    static func read(rootDirectory: URL,
                     fileManager: FileManager = .default) -> FinderMenuSnapshot? {
        let url = FinderMenuIPCContract.snapshotURL(rootDirectory: rootDirectory)
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try PropertyListDecoder().decode(FinderMenuSnapshot.self, from: data)
            return try snapshot.validated()
        } catch {
            FinderMenuLog.write("[VorssaintFinderMenu] snapshot read failed at \(url.path): \(String(describing: error))")
            return nil
        }
    }
}
