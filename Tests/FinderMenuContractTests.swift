// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure contract tests for the Finder menu. No Finder extension is loaded and
/// no real file operation runs.
enum FinderMenuContractTests {
    static func run(_ suite: TestSuite) {
        testDefaults(suite)
        testNormalization(suite)
        testSnapshot(suite)
        testRequests(suite)
        testConfigurationStore(suite)
        testExtensionEntitlements(suite)
    }

    private static func testDefaults(_ suite: TestSuite) {
        let actionIDs = FinderMenuAction.allCases.map(\.rawValue)
        suite.expect(Set(actionIDs).count == actionIDs.count, "action identities are unique")
        suite.expect(FinderMenuAction.defaultOrder.count == 5, "the default menu has five built-in rows")
        suite.expect(Set(FinderMenuAction.defaultOrder).count == 5,
                     "the default menu does not repeat an action")
        suite.expect(FinderMenuAction.menuActions == Set(FinderMenuAction.defaultOrder),
                     "the supported menu set matches the default order")

        let config = FinderMenuConfiguration.default.normalized()
        suite.expect(config.schemaVersion == FinderMenuConfiguration.currentSchemaVersion,
                     "new configurations use the current schema")
        suite.expect(config.isEnabled && config.showIcons, "a new menu is enabled and shows icons")
        suite.expect(config.items.map(\.id) == FinderMenuAction.defaultOrder.map(\.rawValue),
                     "default rows keep the intended order")
        suite.expect(config.items.allSatisfy { $0.kind == .action && $0.isEnabled },
                     "default rows are enabled built-in actions")
        suite.expect(config.groups.isEmpty, "the first install ships a flat menu")
        suite.expect(config.orderedRows().map(\.id) == config.items.map(\.id),
                     "a flat configuration preserves row order")

        suite.expect(FinderMenuAction.delete.isDestructive, "delete is destructive")
        suite.expect(FinderMenuAction.emptyTrash.isDestructive, "empty trash is destructive")
        suite.expect(!FinderMenuAction.copy.isDestructive, "copy is not destructive")
        suite.expect(FinderMenuAction.allCases.allSatisfy { !$0.defaultSymbolName.isEmpty },
                     "every built-in action has a fallback symbol")
    }

    private static func testNormalization(_ suite: TestSuite) {
        let duplicate = FinderMenuConfiguration(
            items: [
                .action(.cut),
                .action(.cut, isEnabled: false),
                .action(.copy, customTitle: "  Copy Me  ", customSymbolName: "  doc.on.doc  ")
            ]
        ).normalized()
        suite.expect(duplicate.items.count == 2, "duplicate action rows collapse to one")
        suite.expect(duplicate.items.first?.isEnabled == true,
                     "the first duplicate wins so a stale disabled copy cannot hide it")
        suite.expect(duplicate.items.last?.customTitle == "Copy Me",
                     "custom titles are trimmed")
        suite.expect(duplicate.items.last?.customSymbolName == "doc.on.doc",
                     "custom symbols are trimmed")

        let unsupported = FinderMenuConfiguration(
            items: [.action(.compress), .action(.delete), .action(.copy)]
        ).normalized()
        suite.expect(unsupported.items.map(\.id) == ["copy"],
                     "actions removed from the menu are dropped from older configurations")

        let applications = FinderMenuConfiguration(
            items: [
                .application("/Applications/Safari.app"),
                .application("Applications/Chrome.app"),
                .application("/Applications/Finder.app/"),
                .action(.openWithApp)
            ]
        ).normalized()
        suite.expect(applications.items.count == 2,
                     "absolute application rows survive; relative and bare Open With rows do not")
        suite.expect(applications.items[0].id == "app:/Applications/Safari.app",
                     "application identity is derived from the normalized path")
        suite.expect(applications.items[0].action == .openWithApp,
                     "application rows use the Open With action")
        suite.expect(applications.items[1].id == "app:/Applications/Finder.app",
                     "a trailing slash is normalized away")

        let grouped = FinderMenuConfiguration(
            items: [.action(.copy), .action(.paste), .action(.cut)],
            groups: [
                FinderMenuGroup(id: "clipboard", title: " Clipboard ",
                                itemIDs: ["paste", "missing", "paste", "cut"]),
                FinderMenuGroup(id: "empty", itemIDs: ["missing"]),
                FinderMenuGroup(id: "clipboard", title: "Duplicate", itemIDs: ["copy"])
            ]
        ).normalized()
        suite.expect(grouped.groups.count == 1,
                     "empty and duplicate groups are dropped")
        suite.expect(grouped.groups[0].title == "Clipboard", "group titles are trimmed")
        suite.expect(grouped.groups[0].itemIDs == ["paste", "cut"],
                     "group rows keep order, remove unknown ids and deduplicate")
        suite.expect(grouped.orderedRows().map(\.id) == ["copy", "paste", "cut"],
                     "ungrouped rows come first, then enabled group members")

        let empty = FinderMenuConfiguration(items: []).normalized()
        suite.expect(empty.items.count == FinderMenuAction.defaultOrder.count,
                     "an empty configuration falls back to the default menu")

        let disabled = FinderMenuConfiguration(isEnabled: false,
                                               showIcons: false,
                                               items: [.action(.copy, isEnabled: false)]).normalized()
        suite.expect(!disabled.isEnabled && !disabled.showIcons && disabled.items[0].isEnabled == false,
                     "menu-level and row-level switches survive normalization")
    }

    private static func testSnapshot(_ suite: TestSuite) {
        let configuration = FinderMenuConfiguration(
            items: [
                .action(.copy, customTitle: "Copy It", customSymbolName: "doc.on.doc.fill"),
                .application("/Applications/Safari.app", customTitle: "Safari Browser"),
                .action(.paste, isEnabled: false)
            ],
            groups: [
                FinderMenuGroup(id: "clipboard", itemIDs: ["paste", "copy"])
            ]
        )
        let snapshot = FinderMenuSnapshotBuilder.build(configuration: configuration,
                                                       generatedAt: Date(timeIntervalSince1970: 1_000))
        suite.expect(snapshot.version == FinderMenuSnapshot.currentVersion,
                     "the snapshot carries its schema version")
        suite.expect(snapshot.generatedAt == Date(timeIntervalSince1970: 1_000),
                     "the snapshot keeps the supplied generation time")
        suite.expect(snapshot.items.count == 3, "every configured row is published")
        suite.expect(snapshot.items[0].title == "Copy It", "custom titles win over the localized default")
        suite.expect(snapshot.items[0].symbolName == "doc.on.doc.fill", "custom symbols win")
        suite.expect(snapshot.items[1].title == "Safari Browser" && snapshot.items[1].kind == .application,
                     "application rows publish their custom title")
        suite.expect(snapshot.items[2].isEnabled == false, "disabled rows stay disabled")
        suite.expect(snapshot.groups.count == 1 && snapshot.groups[0].title == "clipboard",
                     "groups without a title fall back to their identity")
        suite.expect(snapshot.orderedItems().map(\.id) == ["app:/Applications/Safari.app",
                                                           "paste",
                                                           "copy"],
                     "the snapshot exposes the same ordering rule as the configuration")

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try! encoder.encode(snapshot)
        let decoded = try! PropertyListDecoder().decode(FinderMenuSnapshot.self, from: data)
        suite.expect(decoded == snapshot, "snapshots survive the plist round trip")
        suite.expect((try? decoded.validated()) != nil, "the current snapshot version validates")

        var future = snapshot
        future.version = FinderMenuSnapshot.currentVersion + 1
        do {
            _ = try future.validated()
            suite.expect(false, "a newer snapshot version is rejected")
        } catch {
            suite.expect(error as? FinderMenuSnapshotError == .unsupportedVersion(future.version),
                         "a newer snapshot version reports the mismatch")
        }
    }

    private static func testRequests(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 2_000)
        func expectValid(_ request: FinderMenuRequest, _ label: String) {
            do {
                try request.validated(now: now)
            } catch {
                suite.expect(false, "\(label): \(error)")
            }
        }
        func expectError(_ request: FinderMenuRequest,
                         _ expected: FinderMenuRequestError,
                         _ label: String) {
            do {
                try request.validated(now: now)
                suite.expect(false, "\(label): request unexpectedly validated")
            } catch {
                suite.expect(error as? FinderMenuRequestError == expected,
                             "\(label): got \(error), expected \(expected)")
            }
        }

        let copy = FinderMenuRequest(action: .copy,
                                     selectedPaths: ["/tmp/a.txt"],
                                     createdAt: now)
        expectValid(copy, "a selected file validates")

        let copiedPath = FinderMenuRequest(action: .copyPath,
                                           selectedPaths: ["/tmp/a.txt", "/tmp/b.txt"],
                                           createdAt: now)
        expectValid(copiedPath, "Copy Path accepts multiple selections")

        expectError(FinderMenuRequest(action: .copyPath, createdAt: now),
                    .emptySelection, "Copy Path without a selection")

        expectValid(FinderMenuRequest(action: .newTerminal, createdAt: now),
                    "New Terminal works in an empty folder")

        expectError(FinderMenuRequest(action: .newFile, createdAt: now),
                    .missingTargetDirectory, "New File requires a target directory")
        expectValid(FinderMenuRequest(action: .newFile,
                                      targetDirectory: "/tmp",
                                      createdAt: now),
                    "New File accepts an absolute target directory")
        expectError(FinderMenuRequest(action: .paste, createdAt: now),
                    .missingTargetDirectory, "Paste requires a target directory")

        expectValid(FinderMenuRequest(action: .openWithApp,
                                      selectedPaths: ["/tmp/a.txt"],
                                      appPath: "/Applications/Safari.app",
                                      createdAt: now),
                    "Open With accepts a selected file and application")
        expectError(FinderMenuRequest(action: .openWithApp,
                                      selectedPaths: ["/tmp/a.txt"],
                                      createdAt: now),
                    .invalidApplicationPath, "Open With requires an application path")
        expectError(FinderMenuRequest(action: .openWithApp,
                                      selectedPaths: ["/tmp/a.txt"],
                                      appPath: "/Applications/Safari",
                                      createdAt: now),
                    .invalidApplicationPath, "Open With requires an .app bundle")
        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a.txt"],
                                      appPath: "/Applications/Safari.app",
                                      createdAt: now),
                    .unexpectedApplicationPath, "only Open With may carry an application path")

        expectError(FinderMenuRequest(action: .uninstallApp,
                                      selectedPaths: ["/Applications/A.app", "/Applications/B.app"],
                                      createdAt: now),
                    .tooManySelections, "Uninstall App accepts one application")

        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["tmp/a.txt"],
                                      createdAt: now),
                    .invalidPath, "relative paths are rejected")
        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a\0b"],
                                      createdAt: now),
                    .invalidPath, "NUL bytes are rejected")
        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a\nb"],
                                      createdAt: now),
                    .invalidPath, "newlines are rejected")
        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: Array(repeating: "/tmp/a", count: 201),
                                      createdAt: now),
                    .tooManyPaths, "the selection limit is enforced")

        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a"],
                                      createdAt: now.addingTimeInterval(-61)),
                    .stale, "requests older than the limit are rejected")
        expectError(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a"],
                                      createdAt: now.addingTimeInterval(6)),
                    .stale, "requests too far in the future are rejected")
        expectValid(FinderMenuRequest(action: .copy,
                                      selectedPaths: ["/tmp/a"],
                                      createdAt: now.addingTimeInterval(4)),
                    "small clock skew is tolerated")
        expectError(FinderMenuRequest(version: FinderMenuRequest.currentVersion + 1,
                                      action: .copy,
                                      selectedPaths: ["/tmp/a"],
                                      createdAt: now),
                    .unsupportedVersion(FinderMenuRequest.currentVersion + 1),
                    "unsupported request versions are rejected")

        let response = FinderMenuResponse(id: copy.id, succeeded: true)
        suite.expect((try? response.validated()) != nil, "a current response validates")
        let data = try! JSONEncoder().encode(response)
        let decoded = try! JSONDecoder().decode(FinderMenuResponse.self, from: data)
        suite.expect(decoded == response, "responses survive the JSON round trip")

        let tooLong = FinderMenuResponse(id: copy.id,
                                         succeeded: false,
                                         message: String(repeating: "x", count: 2049))
        do {
            try tooLong.validated()
            suite.expect(false, "an oversized response message is rejected")
        } catch {
            suite.expect(error as? FinderMenuRequestError == .messageTooLong,
                         "an oversized response message reports its limit")
        }
    }

    private static func testConfigurationStore(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.finder-menu.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        let key = "testConfiguration"
        let store = FinderMenuConfigurationStore(defaults: defaults, key: key)
        defer { defaults.removePersistentDomain(forName: domain) }

        suite.expect(store.load() == .default, "a fresh suite loads the default menu")

        var configuration = FinderMenuConfiguration.default
        configuration.showIcons = false
        configuration.items = [.action(.copy, customTitle: "Copy"), .action(.delete)]
        try! store.save(configuration)
        suite.expect(store.load() == configuration.normalized(),
                     "saved configurations round trip through defaults")

        defaults.set(Data("not json".utf8), forKey: key)
        suite.expect(store.load() == .default, "corrupt data falls back to the default menu")

        store.reset()
        suite.expect(store.load() == .default, "reset restores the default menu")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-finder-menu-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try! store.save(configuration)
        let snapshot = try! store.publishSnapshot(rootDirectory: root,
                                                  generatedAt: Date(timeIntervalSince1970: 3_000))
        let snapshotURL = FinderMenuIPCContract.snapshotURL(rootDirectory: root)
        suite.expect(FileManager.default.fileExists(atPath: snapshotURL.path),
                     "publishing writes the extension snapshot")
        suite.expect(snapshot.configurationItemsMatch(store.load()),
                     "the published snapshot reflects the stored configuration")

        let attributes = try! FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        suite.expect(permissions == 0o600, "the snapshot is owner-only readable")

        let data = try! Data(contentsOf: snapshotURL)
        let decoded = try! PropertyListDecoder().decode(FinderMenuSnapshot.self, from: data)
        suite.expect(decoded == snapshot, "the extension can decode the published plist")

        store.removeSnapshot(rootDirectory: root)
        suite.expect(!FileManager.default.fileExists(atPath: snapshotURL.path),
                     "removing the snapshot leaves no stale menu")
    }

    private static func testExtensionEntitlements(_ suite: TestSuite) {
        let url = URL(fileURLWithPath: "Resources/FinderMenu/VorssaintFinderMenu.entitlements")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     options: [],
                                                                     format: nil),
              let entitlements = plist as? [String: Any]
        else {
            suite.expect(false, "the Finder extension entitlements are readable")
            return
        }

        let paths = entitlements["com.apple.security.temporary-exception.files.absolute-path.read-write"]
            as? [String]
        suite.expect(paths?.contains("/") == true,
                     "the Finder extension can inspect selected items outside its container")
    }
}

private extension FinderMenuSnapshot {
    func configurationItemsMatch(_ configuration: FinderMenuConfiguration) -> Bool {
        let normalized = configuration.normalized()
        return items.map(\.id) == normalized.items.map(\.id)
            && isEnabled == normalized.isEnabled
            && showIcons == normalized.showIcons
    }
}
