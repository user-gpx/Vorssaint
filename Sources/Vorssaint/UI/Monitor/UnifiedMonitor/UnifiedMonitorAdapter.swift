// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure mapping from Vorssaint's sampled values to the unified dashboard.
/// Keeping it free of IOKit/AppKit lets the layout and formatting rules run in
/// the standalone test target.
enum UnifiedMonitorAdapter {
    static func make(input: UnifiedMonitorInput,
                     preferences: UnifiedMonitorCardPreferences = .init(),
                     temperatureUnit: TemperatureUnit = .celsius) -> UnifiedMonitorModel {
        let preferences = preferences.normalized()
        let rows = processRows(input.processes)
        let cards: [UnifiedMonitorCardID: UnifiedMonitorCardModel] = [
            .cpu: cpuCard(input, unit: temperatureUnit, enabled: preferences.isEnabled(.cpu)),
            .gpu: gpuCard(input, unit: temperatureUnit, enabled: preferences.isEnabled(.gpu)),
            .memory: memoryCard(input, enabled: preferences.isEnabled(.memory)),
            .disk: diskCard(input, enabled: preferences.isEnabled(.disk)),
            .network: networkCard(input, enabled: preferences.isEnabled(.network)),
            .temperature: temperatureCard(input, unit: temperatureUnit,
                                          enabled: preferences.isEnabled(.temperature)),
            .battery: batteryCard(input, enabled: preferences.isEnabled(.battery)),
            .processes: processCard(rows, enabled: preferences.isEnabled(.processes))
        ]
        return UnifiedMonitorModel(
            header: UnifiedMonitorHeaderModel(chipName: input.machine.chipName,
                                              memoryTotalBytes: input.memoryTotal,
                                              osVersion: input.machine.osVersion,
                                              uptime: input.machine.uptime,
                                              date: input.machine.date),
            cards: preferences.order.compactMap { cards[$0] },
            processes: rows
        )
    }

    private static func cpuCard(_ input: UnifiedMonitorInput,
                                unit: TemperatureUnit,
                                enabled: Bool) -> UnifiedMonitorCardModel {
        let usage = clamp(input.cpuUsage ?? 0)
        return UnifiedMonitorCardModel(
            id: .cpu,
            value: MetricFormat.percent(usage),
            percent: usage,
            badge: temperatureBadge(input.cpuTemperature, unit: unit),
            detail: nil,
            history: history(input.cpuHistory, clamped: true),
            secondaryHistory: [],
            chartStyle: .area,
            load: loadState(average: input.loadAverage, cores: input.coreCount),
            isAvailable: input.cpuUsage != nil,
            isEnabled: enabled
        )
    }

    private static func gpuCard(_ input: UnifiedMonitorInput,
                                unit: TemperatureUnit,
                                enabled: Bool) -> UnifiedMonitorCardModel {
        let usage = clamp(input.gpuUsage ?? 0)
        return UnifiedMonitorCardModel(
            id: .gpu,
            value: MetricFormat.percent(usage),
            percent: usage,
            badge: temperatureBadge(input.gpuTemperature, unit: unit),
            detail: nil,
            history: history(input.gpuHistory, clamped: true),
            secondaryHistory: [],
            chartStyle: .area,
            load: nil,
            isAvailable: input.gpuUsage != nil,
            isEnabled: enabled
        )
    }

    private static func memoryCard(_ input: UnifiedMonitorInput, enabled: Bool) -> UnifiedMonitorCardModel {
        let total = input.memoryTotal ?? 0
        let used = min(input.memoryUsed ?? 0, total)
        let fraction = total > 0 ? Double(used) / Double(total) : nil
        let pressure = pressureBadge(input.memoryPressure)
        return UnifiedMonitorCardModel(
            id: .memory,
            value: fraction.map(MetricFormat.percent) ?? "—",
            percent: fraction,
            badge: pressure,
            detail: total > 0 ? "\(memoryBytes(used)) / \(memoryBytes(total))" : nil,
            history: history(input.memoryHistory, clamped: true),
            secondaryHistory: [],
            chartStyle: .none,
            load: nil,
            isAvailable: total > 0,
            isEnabled: enabled
        )
    }

    private static func diskCard(_ input: UnifiedMonitorInput, enabled: Bool) -> UnifiedMonitorCardModel {
        let device = input.disk?.devices.first(where: \.isInternal) ?? input.disk?.devices.first
        let fraction = device.map(\.usedFraction)
        return UnifiedMonitorCardModel(
            id: .disk,
            value: fraction.map(MetricFormat.percent) ?? "—",
            percent: fraction,
            badge: device.map {
                UnifiedMonitorBadge(kind: .capacity,
                                    text: MetricFormat.diskBytes($0.totalBytes),
                                    severity: diskSeverity(used: fraction ?? 0))
            },
            detail: device.map {
                "\(MetricFormat.diskBytes($0.usedBytes)) / \(MetricFormat.diskBytes($0.totalBytes))"
            },
            history: [],
            secondaryHistory: [],
            chartStyle: .none,
            load: nil,
            isAvailable: device != nil,
            isEnabled: enabled
        )
    }

    private static func networkCard(_ input: UnifiedMonitorInput, enabled: Bool) -> UnifiedMonitorCardModel {
        let down = max(0, input.netDownBytesPerSec ?? 0)
        let up = max(0, input.netUpBytesPerSec ?? 0)
        let available = input.networkAvailable
        return UnifiedMonitorCardModel(
            id: .network,
            value: available ? MetricFormat.bytesPerSec(down) : "—",
            percent: nil,
            badge: UnifiedMonitorBadge(kind: .network,
                                       text: available ? "Online" : "Offline",
                                       severity: available ? .normal : .critical),
            detail: available ? "↑\(MetricFormat.bytesPerSec(up)) · ↓\(MetricFormat.bytesPerSec(down))" : nil,
            history: history(input.netDownHistory, clamped: false),
            secondaryHistory: history(input.netUpHistory, clamped: false),
            chartStyle: .line,
            load: nil,
            isAvailable: available && (input.netDownBytesPerSec != nil || input.netUpBytesPerSec != nil),
            isEnabled: enabled
        )
    }

    private static func temperatureCard(_ input: UnifiedMonitorInput,
                                        unit: TemperatureUnit,
                                        enabled: Bool) -> UnifiedMonitorCardModel {
        let temperatures = [input.cpuTemperature, input.gpuTemperature, input.batteryTemperature].compactMap { $0 }
        let peak = temperatures.max()
        var detail: [String] = []
        if let cpu = input.cpuTemperature { detail.append("CPU \(MetricFormat.temperature(cpu, unit: unit))") }
        if let gpu = input.gpuTemperature { detail.append("GPU \(MetricFormat.temperature(gpu, unit: unit))") }
        if let battery = input.batteryTemperature { detail.append("Battery \(MetricFormat.temperature(battery, unit: unit))") }
        if let fan = input.fanSpeeds.first {
            detail.append(String(format: "Fan %.0f rpm", locale: MetricFormat.locale, fan))
        }
        return UnifiedMonitorCardModel(
            id: .temperature,
            value: peak.map { MetricFormat.temperature($0, unit: unit) } ?? "—",
            percent: nil,
            badge: peak.map { UnifiedMonitorBadge(kind: .temperature,
                                                  text: temperatureStatusText($0),
                                                  severity: temperatureSeverity($0)) },
            detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
            history: [],
            secondaryHistory: [],
            chartStyle: .none,
            load: nil,
            isAvailable: peak != nil,
            isEnabled: enabled
        )
    }

    private static func batteryCard(_ input: UnifiedMonitorInput, enabled: Bool) -> UnifiedMonitorCardModel {
        guard let power = input.power, power.hasBattery else {
            return UnifiedMonitorCardModel(id: .battery,
                                           value: "—",
                                           percent: nil,
                                           badge: nil,
                                           detail: nil,
                                           history: [],
                                           secondaryHistory: [],
                                           chartStyle: .none,
                                           load: nil,
                                           isAvailable: false,
                                           isEnabled: enabled)
        }
        let charge = clamp(Double(power.chargePercent ?? 0) / 100)
        let status = batteryStatus(power, charge: charge)
        let watts = [power.systemWatts, power.adapterWatts]
            .compactMap { $0 }
            .map(MetricFormat.watts)
            .joined(separator: " · ")
        let detail = watts.isEmpty ? batteryRemainder(power) : watts
        return UnifiedMonitorCardModel(
            id: .battery,
            value: power.chargePercent.map { "\($0)%" } ?? "—",
            percent: power.chargePercent == nil ? nil : charge,
            badge: status,
            detail: detail,
            history: history(input.batteryHistory, clamped: true),
            secondaryHistory: [],
            chartStyle: .none,
            load: nil,
            isAvailable: true,
            isEnabled: enabled
        )
    }

    private static func processCard(_ rows: [UnifiedMonitorProcessRow], enabled: Bool) -> UnifiedMonitorCardModel {
        UnifiedMonitorCardModel(id: .processes,
                                value: rows.isEmpty ? "—" : "\(rows.count)",
                                percent: nil,
                                badge: nil,
                                detail: nil,
                                history: [],
                                secondaryHistory: [],
                                chartStyle: .none,
                                load: nil,
                                isAvailable: !rows.isEmpty,
                                isEnabled: enabled)
    }

    private static func processRows(_ processes: [UnifiedProcessInput]) -> [UnifiedMonitorProcessRow] {
        processes
            .sorted {
                let lhsCPU = $0.cpuPercent ?? -1
                let rhsCPU = $1.cpuPercent ?? -1
                if lhsCPU != rhsCPU { return lhsCPU > rhsCPU }
                return ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
            }
            .prefix(4)
            .map {
                UnifiedMonitorProcessRow(pid: $0.pid,
                                         name: $0.name,
                                         memoryBytes: $0.memoryBytes,
                                         cpuPercent: $0.cpuPercent)
            }
    }

    private static func loadState(average: Double?, cores: Int) -> UnifiedLoadState? {
        guard let average, average.isFinite, cores > 0 else { return nil }
        let ratio = max(0, average) / Double(cores)
        let level: UnifiedLoadLevel = ratio < 0.5 ? .low : (ratio < 0.8 ? .medium : .high)
        return UnifiedLoadState(level: level, average: average, coreCount: cores)
    }

    private static func temperatureBadge(_ celsius: Double?,
                                         unit: TemperatureUnit) -> UnifiedMonitorBadge? {
        guard let celsius else { return nil }
        return UnifiedMonitorBadge(kind: .temperature,
                                   text: MetricFormat.temperature(celsius, unit: unit),
                                   severity: temperatureSeverity(celsius))
    }

    private static func pressureBadge(_ pressure: UnifiedMemoryPressure) -> UnifiedMonitorBadge {
        switch pressure {
        case .normal:
            return UnifiedMonitorBadge(kind: .pressure, text: "Normal", severity: .normal)
        case .warning:
            return UnifiedMonitorBadge(kind: .pressure, text: "Warning", severity: .warning)
        case .critical:
            return UnifiedMonitorBadge(kind: .pressure, text: "Critical", severity: .critical)
        case .unknown:
            return UnifiedMonitorBadge(kind: .pressure, text: "Unknown", severity: .neutral)
        }
    }

    private static func batteryStatus(_ power: UnifiedPowerInput, charge: Double) -> UnifiedMonitorBadge {
        if power.isCharging {
            return UnifiedMonitorBadge(kind: .power, text: "Charging", severity: .normal)
        }
        if charge < 0.2 {
            return UnifiedMonitorBadge(kind: .power, text: "Low", severity: .critical)
        }
        if power.externalConnected {
            return UnifiedMonitorBadge(kind: .power, text: "On Power", severity: .normal)
        }
        if charge < 0.4 {
            return UnifiedMonitorBadge(kind: .power, text: "Low", severity: .warning)
        }
        return UnifiedMonitorBadge(kind: .power, text: "Normal", severity: .normal)
    }

    private static func batteryRemainder(_ power: UnifiedPowerInput) -> String? {
        guard let seconds = power.timeRemainingSeconds, seconds > 0 else { return nil }
        return MetricFormat.uptime(Int(seconds))
    }

    private static func temperatureSeverity(_ celsius: Double) -> UnifiedMonitorSeverity {
        if celsius >= 85 { return .critical }
        if celsius >= 70 { return .warning }
        return .normal
    }

    private static func temperatureStatusText(_ celsius: Double) -> String {
        switch temperatureSeverity(celsius) {
        case .critical: return "Hot"
        case .warning: return "Warm"
        case .normal, .neutral: return "Normal"
        }
    }

    private static func diskSeverity(used: Double) -> UnifiedMonitorSeverity {
        if used >= 0.9 { return .critical }
        if used >= 0.8 { return .warning }
        return .normal
    }

    private static func memoryBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, Double(bytes))
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if units[index] == "B" {
            return String(format: "%.0f B", locale: MetricFormat.locale, value)
        }
        if value.rounded() == value {
            return String(format: "%.0f %@", locale: MetricFormat.locale, value, units[index])
        }
        return String(format: "%.2f %@", locale: MetricFormat.locale, value, units[index])
    }

    private static func history(_ values: [Double], clamped: Bool) -> [Double] {
        values
            .filter(\.isFinite)
            .suffix(60)
            .map { clamped ? clamp($0) : max(0, $0) }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }
}
