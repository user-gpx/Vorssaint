// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Owns the main-app half of the Finder context menu: publishing the menu
/// snapshot, receiving requests from the Finder Sync extension and performing
/// the file operations. The extension itself stays sandboxed and never touches
/// the selected files.
final class FinderMenuService {
    static let shared = FinderMenuService()

    private let store = FinderMenuConfigurationStore.shared
    private let queue = DispatchQueue(label: "com.vorssaint.finder-menu", qos: .userInitiated)
    private var isListening = false
    private var pendingResponses: [UUID: FinderMenuResponse] = [:]
    private var languageCancellable: AnyCancellable?

    private init() {
        languageCancellable = L10n.shared.$language
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncWithPreferences()
            }
    }

    private var rootDirectory: URL {
#if VORSSAINT_DEVELOPMENT
        FinderMenuIPCContract.rootDirectory(namespace: FinderMenuIPCContract.developerNamespace)
#else
        FinderMenuIPCContract.rootDirectory()
#endif
    }

    /// Applies the feature availability and the persisted configuration. Safe
    /// to call repeatedly; it is the one entry point used by FeatureRuntime.
    func syncWithPreferences() {
        let available = AppFeature.finderContextMenu.isAvailable
        let configuration = store.load()
        guard available, configuration.isEnabled else {
            stopListening()
            store.removeSnapshot(rootDirectory: rootDirectory)
            removeStaleMessages()
            return
        }
        startListening()
        let strings = FeatureStrings.finderMenu(L10n.shared.language)
        do {
            try store.publishSnapshot(rootDirectory: rootDirectory,
                                      title: { strings.title(for: $0) },
                                      symbolName: { $0.defaultSymbolName })
        } catch {
            NSLog("[FinderMenu] snapshot publish failed: %@", String(describing: error))
        }
        queue.async { [weak self] in self?.processPendingRequests() }
    }

    // MARK: - IPC

    private func startListening() {
        guard !isListening else { return }
        isListening = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.requestNotificationCallback,
            FinderMenuIPCContract.requestNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static let requestNotificationCallback: CFNotificationCallback = {
        _, observer, _, _, _ in
        guard let observer else { return }
        let service = Unmanaged<FinderMenuService>
            .fromOpaque(observer).takeUnretainedValue()
        service.queue.async { [weak service] in
            service?.processPendingRequests()
        }
    }

    private func stopListening() {
        guard isListening else { return }
        isListening = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(FinderMenuIPCContract.requestNotification as CFString),
            nil
        )
    }

    private func processPendingRequests() {
        let fileManager = FileManager.default
        let requestsDirectory = FinderMenuIPCContract.requestsDirectory(rootDirectory: rootDirectory)
        guard let names = try? fileManager.contentsOfDirectory(atPath: requestsDirectory.path) else {
            return
        }
        let urls = names
            .filter(FinderMenuIPCContract.isMessageFileName)
            .map { requestsDirectory.appendingPathComponent($0, isDirectory: false) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls.prefix(50) {
            guard let data = try? Data(contentsOf: url),
                  let request = try? PropertyListDecoder().decode(FinderMenuRequest.self, from: data)
            else {
                try? fileManager.removeItem(at: url)
                continue
            }
            let response = execute(request)
            write(response)
            try? fileManager.removeItem(at: url)
        }
    }

    private func write(_ response: FinderMenuResponse) {
        do {
            try FinderMenuIPCContract.prepare(rootDirectory: rootDirectory)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let url = FinderMenuIPCContract.responseURL(id: response.id,
                                                        rootDirectory: rootDirectory)
            try encoder.encode(response).write(to: url, options: .atomic)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(FinderMenuIPCContract.responseNotification as CFString),
                nil, nil, true
            )
        } catch {
            NSLog("[FinderMenu] response write failed: %@", String(describing: error))
        }
    }

    private func removeStaleMessages() {
        let fileManager = FileManager.default
        for directory in [FinderMenuIPCContract.requestsDirectory(rootDirectory: rootDirectory),
                          FinderMenuIPCContract.responsesDirectory(rootDirectory: rootDirectory)] {
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
                continue
            }
            for name in names where FinderMenuIPCContract.isMessageFileName(name) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Requests

    private func execute(_ request: FinderMenuRequest) -> FinderMenuResponse {
        do {
            try request.validated()
            let message = try perform(request)
            return FinderMenuResponse(id: request.id, succeeded: true, message: message)
        } catch {
            return FinderMenuResponse(id: request.id,
                                      succeeded: false,
                                      message: String(describing: error))
        }
    }

    /// The scan queue is background work, so AppKit and AppleScript calls hop
    /// to the main thread and this helper waits for them. Never call this from
    /// the main thread or the wait would deadlock.
    private func onMainSync<T>(_ body: @escaping () throws -> T) throws -> T {
        if Thread.isMainThread { return try body() }
        var result: Result<T, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = Result { try body() }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result else { throw FinderMenuOperationError.operationFailed("Main thread") }
        return try result.get()
    }

    private func perform(_ request: FinderMenuRequest) throws -> String? {
        let selected = request.selectedPaths.map { URL(fileURLWithPath: $0) }
        let target = request.targetDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }

        switch request.action {
        case .copyPath:
            try copyToPasteboard(selected.map(\.path).joined(separator: "\n"))
            return nil
        case .copy:
            try copyToPasteboard(objects: selected.map { $0 as NSURL })
            return nil
        case .cut:
            guard AppFeature.finderCutPaste.isAvailable else {
                throw FinderMenuOperationError.featureUnavailable("Cut & Paste")
            }
            try onMainSync { FinderCutPaste.shared.markForMove(selected) }
            return nil
        case .paste:
            guard let target else { throw FinderMenuRequestError.missingTargetDirectory }
            let hasMarkedItems = try onMainSync { FinderCutPaste.shared.hasMarkedItems }
            if hasMarkedItems {
                try moveMarked(into: target)
            } else {
                try copyPasteboardFiles(into: target)
            }
            return nil
        case .delete:
            try trash(selected)
            return nil
        case .compress:
            try compress(selected, targetDirectory: target ?? selected[0].deletingLastPathComponent())
            return nil
        case .extract:
            try extract(selected, into: target ?? selected[0].deletingLastPathComponent())
            return nil
        case .newTerminal:
            try run("/usr/bin/open", ["-a", "Terminal", (target ?? URL(fileURLWithPath: NSHomeDirectory())).path])
            return nil
        case .hiddenFiles:
            try toggleHiddenFiles()
            return nil
        case .emptyTrash:
            try emptyTrash()
            return nil
        case .newFile:
            guard let target else { throw FinderMenuRequestError.missingTargetDirectory }
            try createNewFile(in: target)
            return nil
        case .networkInfo:
            let addresses = NetworkAddressService.readLocalAddresses()
            guard !addresses.isEmpty else { throw FinderMenuOperationError.noNetworkAddress }
            try copyToPasteboard(addresses.joined(separator: "\n"))
            return addresses.joined(separator: "\n")
        case .restartFinder:
            try run("/usr/bin/killall", ["Finder"])
            return nil
        case .uninstallApp:
            guard let appURL = selected.first else {
                throw FinderMenuRequestError.emptySelection
            }
            guard appURL.pathExtension.lowercased() == "app" else {
                throw FinderMenuRequestError.invalidApplicationPath
            }
            guard AppFeature.uninstaller.isAvailable else {
                AppFeature.uninstaller.showInFeatures()
                throw FinderMenuOperationError.featureUnavailable("Uninstaller")
            }
            try onMainSync {
                guard AppUninstaller.shared.select(appURL: appURL) else {
                    throw FinderMenuOperationError.uninstallRefused
                }
                SettingsRouter.shared.request(FeatureSettingsDestination(.uninstaller))
                (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            }
            return nil
        case .openWithApp:
            guard let appPath = request.appPath else {
                throw FinderMenuRequestError.invalidApplicationPath
            }
            try open(selected, with: URL(fileURLWithPath: appPath))
            return nil
        }
    }

    // MARK: - Operations

    private func validateExistingFiles(_ urls: [URL]) throws {
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            throw FinderMenuOperationError.missingFile(url.path)
        }
    }

    private func trash(_ urls: [URL]) throws {
        try validateExistingFiles(urls)
        for url in urls {
            guard !FinderMenuOperationSupport.isProtectedDeletionPath(url.path) else {
                throw FinderMenuOperationError.protectedPath(url.path)
            }
        }
        var failures: [String] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if !failures.isEmpty {
            throw FinderMenuOperationError.operationFailed(failures.joined(separator: ", "))
        }
    }

    private func compress(_ urls: [URL], targetDirectory: URL) throws {
        try validateExistingFiles(urls)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: targetDirectory.path) else {
            throw FinderMenuOperationError.missingDirectory(targetDirectory.path)
        }
        let destination = Self.uniqueURL(in: targetDirectory,
                                         base: urls.count == 1
                                            ? urls[0].deletingPathExtension().lastPathComponent
                                            : "Archive",
                                         extension: "zip")
        if urls.count == 1 {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: urls[0].path, isDirectory: &isDirectory)
            var arguments = ["-c", "-k", "--sequesterRsrc"]
            if isDirectory.boolValue {
                arguments.append("--keepParent")
            }
            arguments.append(contentsOf: [urls[0].path, destination.path])
            let result = try runProcess("/usr/bin/ditto", arguments)
            guard result.status == 0 else {
                throw FinderMenuOperationError.operationFailed(result.errorText)
            }
        } else {
            let parents = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
            guard parents.count == 1, let parent = parents.first else {
                throw FinderMenuOperationError.operationFailed("Select items from one folder")
            }
            let result = try runProcess("/usr/bin/zip",
                                        ["-r", "-X", "-q", destination.path]
                                        + urls.map(\.lastPathComponent),
                                        currentDirectory: parent)
            guard result.status == 0 else {
                throw FinderMenuOperationError.operationFailed(result.errorText)
            }
        }
    }

    private func extract(_ urls: [URL], into targetDirectory: URL) throws {
        try validateExistingFiles(urls)
        guard FileManager.default.fileExists(atPath: targetDirectory.path) else {
            throw FinderMenuOperationError.missingDirectory(targetDirectory.path)
        }
        var unsupported: [String] = []
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "zip":
                let result = try runProcess("/usr/bin/ditto", ["-x", "-k", url.path, targetDirectory.path])
                guard result.status == 0 else {
                    throw FinderMenuOperationError.operationFailed(result.errorText)
                }
            case "tar", "gz", "tgz", "bz2", "xz":
                let result = try runProcess("/usr/bin/tar", ["-xf", url.path, "-C", targetDirectory.path])
                guard result.status == 0 else {
                    throw FinderMenuOperationError.operationFailed(result.errorText)
                }
            default:
                unsupported.append(url.lastPathComponent)
            }
        }
        if !unsupported.isEmpty {
            throw FinderMenuOperationError.unsupportedArchive(unsupported.joined(separator: ", "))
        }
    }

    private func createNewFile(in directory: URL) throws {
        let destination = Self.uniqueURL(in: directory, base: "Untitled", extension: "txt")
        guard FileManager.default.createFile(atPath: destination.path, contents: Data()) else {
            throw FinderMenuOperationError.operationFailed(destination.lastPathComponent)
        }
    }

    private func toggleHiddenFiles() throws {
        let domain = "com.apple.finder" as CFString
        let key = "AppleShowAllFiles" as CFString
        let current = CFPreferencesCopyAppValue(key, domain) as? Bool ?? false
        CFPreferencesSetAppValue(key, (!current) as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        try run("/usr/bin/killall", ["Finder"])
    }

    private func emptyTrash() throws {
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else {
            throw FinderMenuOperationError.automationDenied
        }
        let success = try onMainSync {
            AppleScriptRunner.run("tell application \"Finder\" to empty trash").ok
        }
        guard success else { throw FinderMenuOperationError.operationFailed("Finder") }
    }

    private func moveMarked(into directory: URL) throws {
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            FinderCutPaste.shared.moveMarked(into: directory) { ok in
                success = ok
                semaphore.signal()
            }
        }
        semaphore.wait()
        guard success else { throw FinderMenuOperationError.operationFailed("Paste") }
    }

    private func copyPasteboardFiles(into directory: URL) throws {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects: [NSURL] = try onMainSync {
            NSPasteboard.general.readObjects(forClasses: classes, options: options) as? [NSURL] ?? []
        }
        let urls = objects.map { $0 as URL }
        guard !urls.isEmpty else { throw FinderMenuOperationError.noPasteboardFiles }
        try validateExistingFiles(urls)
        for source in urls {
            let destination = Self.uniqueURL(in: directory,
                                             base: source.deletingPathExtension().lastPathComponent,
                                             extension: source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func open(_ urls: [URL], with appURL: URL) throws {
        try validateExistingFiles(urls)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw FinderMenuOperationError.missingFile(appURL.path)
        }
        var failure: Error?
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.open(urls, withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            failure = error
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
    }

    private func copyToPasteboard(_ string: String) throws {
        try onMainSync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    private func copyToPasteboard(objects: [NSURL]) throws {
        try onMainSync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(objects)
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let result = try runProcess(executable, arguments)
        guard result.status == 0 else {
            throw FinderMenuOperationError.operationFailed(result.errorText)
        }
    }

    private func runProcess(_ executable: String,
                            _ arguments: [String],
                            currentDirectory: URL? = nil) throws -> (status: Int32, errorText: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, errorText)
    }

    private static func uniqueURL(in directory: URL, base: String, extension ext: String) -> URL {
        let fileManager = FileManager.default
        let trimmed = base.isEmpty ? "Archive" : base
        var candidate = directory.appendingPathComponent(ext.isEmpty ? trimmed : "\(trimmed).\(ext)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(trimmed) \(index)" : "\(trimmed) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}

enum FinderMenuOperationError: Error, CustomStringConvertible {
    case featureUnavailable(String)
    case missingFile(String)
    case missingDirectory(String)
    case protectedPath(String)
    case unsupportedArchive(String)
    case noNetworkAddress
    case noPasteboardFiles
    case automationDenied
    case uninstallRefused
    case operationFailed(String)

    var description: String {
        switch self {
        case .featureUnavailable(let feature): return "\(feature) is not installed"
        case .missingFile(let path): return "Missing file: \(path)"
        case .missingDirectory(let path): return "Missing folder: \(path)"
        case .protectedPath(let path): return "Refusing to delete \(path)"
        case .unsupportedArchive(let names): return "Unsupported archive: \(names)"
        case .noNetworkAddress: return "No local network address"
        case .noPasteboardFiles: return "The clipboard has no files"
        case .automationDenied: return "Finder automation permission is required"
        case .uninstallRefused: return "The uninstaller refused this app"
        case .operationFailed(let message): return message.isEmpty ? "Operation failed" : message
        }
    }
}

enum FinderMenuOperationSupport {
    static func isProtectedDeletionPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let protected = ["/", "/System", "/Library", "/Applications", "/Users", "/Volumes",
                         NSHomeDirectory()]
        return protected.contains(standardized)
    }
}
