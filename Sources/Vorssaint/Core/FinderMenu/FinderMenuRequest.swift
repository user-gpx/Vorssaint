// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderMenuRequest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumSelectedPaths = 200
    static let maximumPathBytes = 4096
    static let maximumMessageBytes = 2048
    static let maximumAge: TimeInterval = 60
    static let clockSkew: TimeInterval = 5

    var version: Int
    var id: UUID
    var action: FinderMenuAction
    var selectedPaths: [String]
    var targetDirectory: String?
    var appPath: String?
    var createdAt: Date

    init(version: Int = FinderMenuRequest.currentVersion,
         id: UUID = UUID(),
         action: FinderMenuAction,
         selectedPaths: [String] = [],
         targetDirectory: String? = nil,
         appPath: String? = nil,
         createdAt: Date = Date()) {
        self.version = version
        self.id = id
        self.action = action
        self.selectedPaths = selectedPaths
        self.targetDirectory = targetDirectory
        self.appPath = appPath
        self.createdAt = createdAt
    }

    /// Structural validation only. The main app still checks that every
    /// selected path exists before performing an operation.
    func validated(now: Date = Date()) throws {
        guard version == Self.currentVersion else {
            throw FinderMenuRequestError.unsupportedVersion(version)
        }
        let age = now.timeIntervalSince(createdAt)
        guard age <= Self.maximumAge, age >= -Self.clockSkew else {
            throw FinderMenuRequestError.stale
        }
        guard selectedPaths.count <= Self.maximumSelectedPaths else {
            throw FinderMenuRequestError.tooManyPaths
        }
        guard selectedPaths.allSatisfy(Self.isValidPath) else {
            throw FinderMenuRequestError.invalidPath
        }
        guard !action.requiresSelection || !selectedPaths.isEmpty else {
            throw FinderMenuRequestError.emptySelection
        }
        guard action.allowsMultipleSelection || selectedPaths.count <= 1 else {
            throw FinderMenuRequestError.tooManySelections
        }
        if let targetDirectory {
            guard Self.isValidPath(targetDirectory) else {
                throw FinderMenuRequestError.invalidTargetDirectory
            }
        } else if action == .newFile || action == .paste {
            throw FinderMenuRequestError.missingTargetDirectory
        }
        if action.requiresApplicationPath {
            guard let appPath, Self.isValidPath(appPath),
                  URL(fileURLWithPath: appPath).pathExtension.lowercased() == "app"
            else {
                throw FinderMenuRequestError.invalidApplicationPath
            }
        } else if appPath != nil {
            throw FinderMenuRequestError.unexpectedApplicationPath
        }
    }

    private static func isValidPath(_ path: String) -> Bool {
        !path.isEmpty
            && path.hasPrefix("/")
            && path.utf8.count <= maximumPathBytes
            && !path.contains("\0")
            && !path.contains("\n")
            && !path.contains("\r")
    }
}

enum FinderMenuRequestError: Error, Equatable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case stale
    case tooManyPaths
    case invalidPath
    case emptySelection
    case tooManySelections
    case invalidTargetDirectory
    case missingTargetDirectory
    case invalidApplicationPath
    case unexpectedApplicationPath
    case messageTooLong

    var description: String {
        switch self {
        case .unsupportedVersion(let version): return "unsupported request version \(version)"
        case .stale: return "request is stale"
        case .tooManyPaths: return "too many selected paths"
        case .invalidPath: return "invalid selected path"
        case .emptySelection: return "action requires a selection"
        case .tooManySelections: return "action accepts one selected item"
        case .invalidTargetDirectory: return "invalid target directory"
        case .missingTargetDirectory: return "missing target directory"
        case .invalidApplicationPath: return "invalid application path"
        case .unexpectedApplicationPath: return "unexpected application path"
        case .messageTooLong: return "response message is too long"
        }
    }
}

struct FinderMenuResponse: Codable, Equatable, Sendable {
    var version: Int
    var id: UUID
    var succeeded: Bool
    var message: String?
    var createdAt: Date

    init(version: Int = FinderMenuRequest.currentVersion,
         id: UUID,
         succeeded: Bool,
         message: String? = nil,
         createdAt: Date = Date()) {
        self.version = version
        self.id = id
        self.succeeded = succeeded
        self.message = message
        self.createdAt = createdAt
    }

    func validated() throws {
        guard version == FinderMenuRequest.currentVersion else {
            throw FinderMenuRequestError.unsupportedVersion(version)
        }
        if let message, message.utf8.count > FinderMenuRequest.maximumMessageBytes {
            throw FinderMenuRequestError.messageTooLong
        }
    }
}
