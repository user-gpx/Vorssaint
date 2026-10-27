// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum UnifiedMonitorCardID: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpu, gpu, memory, disk, network, temperature, battery, processes

    var id: String { rawValue }

    var defaultSymbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer.medium"
        case .battery: return "battery.75percent"
        case .processes: return "list.bullet.rectangle"
        }
    }
}

enum UnifiedMonitorSeverity: String, Equatable, Sendable {
    case neutral, normal, warning, critical
}

enum UnifiedMonitorBadgeKind: String, Equatable, Sendable {
    case temperature, capacity, pressure, network, power, percentage
}

struct UnifiedMonitorBadge: Equatable, Sendable {
    var kind: UnifiedMonitorBadgeKind
    var text: String
    var severity: UnifiedMonitorSeverity
}

enum UnifiedMonitorChartStyle: String, Equatable, Sendable {
    case line, area, bars, none
}

enum UnifiedLoadLevel: String, Equatable, Sendable {
    case low, medium, high
}

struct UnifiedLoadState: Equatable, Sendable {
    var level: UnifiedLoadLevel
    var average: Double
    var coreCount: Int
}

/// One card after formatting. `value` already contains its unit so the view
/// can render a single large label; `percent` is only for progress bars.
struct UnifiedMonitorCardModel: Identifiable, Equatable, Sendable {
    var id: UnifiedMonitorCardID
    var value: String
    var percent: Double?
    var badge: UnifiedMonitorBadge?
    var detail: String?
    var history: [Double]
    var secondaryHistory: [Double]
    var chartStyle: UnifiedMonitorChartStyle
    var load: UnifiedLoadState?
    var isAvailable: Bool
    var isEnabled: Bool
}

struct UnifiedMonitorHeaderModel: Equatable, Sendable {
    var chipName: String
    var memoryTotalBytes: UInt64?
    var osVersion: String
    var uptime: TimeInterval
    var date: Date
}

struct UnifiedMonitorProcessRow: Identifiable, Equatable, Sendable {
    var pid: Int32
    var name: String
    var memoryBytes: UInt64?
    var cpuPercent: Double?

    var id: Int32 { pid }
}

struct UnifiedMonitorModel: Equatable, Sendable {
    var header: UnifiedMonitorHeaderModel
    var cards: [UnifiedMonitorCardModel]
    var processes: [UnifiedMonitorProcessRow]

    var visibleCards: [UnifiedMonitorCardModel] {
        cards.filter { $0.isAvailable && $0.isEnabled }
    }
}

/// Card order and visibility, persisted separately from the sampled data.
/// Arrays keep the type Codable and deterministic; `hiddenCards` also accepts
/// a set at the call site for test and UI convenience.
struct UnifiedMonitorCardPreferences: Equatable, Sendable {
    static let defaultOrder = UnifiedMonitorCardID.allCases

    var order: [UnifiedMonitorCardID]
    var hiddenCards: Set<UnifiedMonitorCardID>

    init(order: [UnifiedMonitorCardID] = UnifiedMonitorCardPreferences.defaultOrder,
         hiddenCards: Set<UnifiedMonitorCardID> = []) {
        self.order = order
        self.hiddenCards = hiddenCards
    }

    func normalized() -> UnifiedMonitorCardPreferences {
        var seen = Set<UnifiedMonitorCardID>()
        var result: [UnifiedMonitorCardID] = []
        for id in order where seen.insert(id).inserted {
            result.append(id)
        }
        for id in UnifiedMonitorCardID.allCases where seen.insert(id).inserted {
            result.append(id)
        }
        return UnifiedMonitorCardPreferences(order: result,
                                             hiddenCards: hiddenCards.intersection(UnifiedMonitorCardID.allCases))
    }

    func isEnabled(_ id: UnifiedMonitorCardID) -> Bool {
        !hiddenCards.contains(id)
    }
}

enum UnifiedMemoryPressure: String, Equatable, Sendable {
    case normal, warning, critical, unknown
}

/// Hardware-independent input. The app maps `SystemSnapshot`, `PowerReading`
/// and `ProcessUsage` into this value; tests can fill it directly without IOKit.
struct UnifiedMonitorInput: Equatable {
    var cpuUsage: Double? = nil
    var cpuTemperature: Double? = nil
    var cpuHistory: [Double] = []
    var loadAverage: Double? = nil
    var coreCount: Int = 0

    var gpuUsage: Double? = nil
    var gpuTemperature: Double? = nil
    var gpuHistory: [Double] = []

    var memoryUsed: UInt64? = nil
    var memoryAppUsed: UInt64? = nil
    var memoryTotal: UInt64? = nil
    var memoryPressure: UnifiedMemoryPressure = .unknown
    var memoryHistory: [Double] = []

    var disk: DiskReading? = nil
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []

    var netDownBytesPerSec: Double? = nil
    var netUpBytesPerSec: Double? = nil
    var netTotalDown: UInt64? = nil
    var netTotalUp: UInt64? = nil
    var netDownHistory: [Double] = []
    var netUpHistory: [Double] = []
    var networkAvailable: Bool = true

    var batteryTemperature: Double? = nil
    var fanSpeeds: [Double] = []
    var power: UnifiedPowerInput? = nil
    var batteryHistory: [Double] = []

    var processes: [UnifiedProcessInput] = []
    var machine: UnifiedMachineInput = .init()
}

struct UnifiedPowerInput: Equatable, Sendable {
    var systemWatts: Double?
    var adapterWatts: Double?
    var batteryWatts: Double?
    var chargePercent: Int?
    var timeRemainingSeconds: TimeInterval?
    var healthPercent: Double?
    var isCharging: Bool = false
    var externalConnected: Bool = false
    var hasBattery: Bool = false
}

struct UnifiedProcessInput: Equatable, Sendable {
    var pid: Int32
    var name: String
    var memoryBytes: UInt64?
    var cpuPercent: Double?
}

struct UnifiedMachineInput: Equatable, Sendable {
    var chipName: String = "Mac"
    var osVersion: String = ""
    var uptime: TimeInterval = 0
    var date: Date = Date()
}
