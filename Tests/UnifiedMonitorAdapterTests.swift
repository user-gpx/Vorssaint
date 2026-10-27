// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The unified dashboard's production formatter runs against plain values.
/// No sampler, SMC or window is involved.
enum UnifiedMonitorAdapterTests {
    static func run(_ suite: TestSuite) {
        let previousLocale = MetricFormat.locale
        MetricFormat.locale = Locale(identifier: "en_US_POSIX")
        defer { MetricFormat.locale = previousLocale }

        let disk = DiskDeviceReading(
            id: "internal",
            name: "Macintosh HD",
            mountPath: "/",
            volumeUUID: "volume",
            bsdName: "disk1s1",
            wholeDisk: "disk1",
            ioCounterID: "disk1",
            fileSystem: "apfs",
            totalBytes: 460_000_000_000,
            freeBytes: 381_000_000_000,
            purgeableBytes: nil,
            usedBytes: 79_000_000_000,
            isInternal: true,
            isRemovable: false,
            isEjectable: false,
            smart: nil,
            readBytesPerSec: nil,
            writeBytesPerSec: nil,
            totalReadBytes: nil,
            totalWrittenBytes: nil
        )
        let input = UnifiedMonitorInput(
            cpuUsage: 0.12,
            cpuTemperature: 33,
            cpuHistory: [0.1, 0.12],
            loadAverage: 1.2,
            coreCount: 10,
            gpuUsage: 0.26,
            gpuTemperature: 33,
            gpuHistory: [0.2, 0.26],
            memoryUsed: 16_870_000_000,
            memoryAppUsed: 8_000_000_000,
            memoryTotal: 32_000_000_000,
            memoryPressure: .normal,
            memoryHistory: [0.5, 0.53],
            disk: DiskReading(devices: [disk]),
            netDownBytesPerSec: 4_096,
            netUpBytesPerSec: 1_024,
            netTotalDown: 10_000,
            netTotalUp: 5_000,
            netDownHistory: [1_024, 4_096],
            netUpHistory: [512, 1_024],
            batteryTemperature: 30,
            fanSpeeds: [1_200],
            power: UnifiedPowerInput(systemWatts: 7,
                                     adapterWatts: 7,
                                     batteryWatts: nil,
                                     chargePercent: 85,
                                     timeRemainingSeconds: nil,
                                     healthPercent: 95,
                                     isCharging: false,
                                     externalConnected: true,
                                     hasBattery: true),
            batteryHistory: [0.8, 0.85],
            processes: [
                UnifiedProcessInput(pid: 1, name: "WindowServer", memoryBytes: 1_000_000_000, cpuPercent: 12),
                UnifiedProcessInput(pid: 2, name: "Vorssaint", memoryBytes: 500_000_000, cpuPercent: 40),
                UnifiedProcessInput(pid: 3, name: "ControlCenter", memoryBytes: 200_000_000, cpuPercent: 5),
                UnifiedProcessInput(pid: 4, name: "Qind", memoryBytes: 300_000_000, cpuPercent: 20),
                UnifiedProcessInput(pid: 5, name: "Fifth", memoryBytes: 100_000_000, cpuPercent: 1)
            ],
            machine: UnifiedMachineInput(chipName: "Apple M5",
                                         osVersion: "macOS 26.6",
                                         uptime: 3_600,
                                         date: Date(timeIntervalSince1970: 1_000))
        )

        let model = UnifiedMonitorAdapter.make(input: input)
        suite.expect(model.header.chipName == "Apple M5", "the header keeps the chip name")
        suite.expect(model.header.memoryTotalBytes == 32_000_000_000,
                     "the header reports physical memory")
        suite.expect(model.header.osVersion == "macOS 26.6", "the header carries the OS version")
        suite.expect(model.header.uptime == 3_600, "the header carries uptime")
        suite.expect(model.cards.map(\.id) == UnifiedMonitorCardID.allCases,
                     "all cards are present in the default order")
        suite.expect(model.visibleCards.count == 8, "every available card is visible by default")

        let cpu = model.cards.first { $0.id == .cpu }!
        suite.expect(cpu.value == "12%", "CPU shows a rounded percentage")
        suite.expect(cpu.percent == 0.12, "CPU keeps its progress fraction")
        suite.expect(cpu.badge?.text == "33 °C" && cpu.badge?.severity == .normal,
                     "CPU shows the temperature with a normal badge")
        suite.expect(cpu.load == UnifiedLoadState(level: .low, average: 1.2, coreCount: 10),
                     "CPU maps load average and core count")
        suite.expect(cpu.history == [0.1, 0.12] && cpu.chartStyle == .area,
                     "CPU keeps its history and area chart style")

        var fahrenheitInput = input
        fahrenheitInput.cpuTemperature = 40
        let fahrenheit = UnifiedMonitorAdapter.make(input: fahrenheitInput,
                                                    temperatureUnit: .fahrenheit)
        suite.expect(fahrenheit.cards.first { $0.id == .cpu }?.badge?.text == "104 °F",
                     "CPU temperature badge follows the selected unit")

        let gpu = model.cards.first { $0.id == .gpu }!
        suite.expect(gpu.value == "26%", "GPU shows a rounded percentage")
        suite.expect(gpu.badge?.text == "33 °C", "GPU shows its temperature")
        suite.expect(gpu.chartStyle == .area, "GPU uses an area chart")

        let memory = model.cards.first { $0.id == .memory }!
        suite.expect(memory.value == "53%", "memory shows used / total as a percentage")
        suite.expect(memory.detail == "16.87 GB / 32 GB", "memory uses a precise byte label")
        suite.expect(memory.badge?.text == "Normal" && memory.badge?.severity == .normal,
                     "memory pressure becomes a badge")

        let diskCard = model.cards.first { $0.id == .disk }!
        suite.expect(diskCard.value == "17%", "disk shows the internal volume usage")
        suite.expect(diskCard.badge?.text == "460 GB", "disk shows total capacity")
        suite.expect(diskCard.detail == "79 GB / 460 GB", "disk shows used and total capacity")

        let network = model.cards.first { $0.id == .network }!
        suite.expect(network.value == "4.0 KB/s", "network shows the down rate")
        suite.expect(network.detail == "↑1.0 KB/s · ↓4.0 KB/s",
                     "network shows both directions")
        suite.expect(network.badge?.text == "Online" && network.badge?.severity == .normal,
                     "network shows an online badge")
        suite.expect(network.secondaryHistory == [512, 1_024],
                     "network keeps the upload history separately")

        let temperature = model.cards.first { $0.id == .temperature }!
        suite.expect(temperature.value == "33 °C", "temperature shows the hottest sensor")
        suite.expect(temperature.badge?.text == "Normal", "temperature shows its status")
        suite.expect(temperature.detail == "CPU 33 °C · GPU 33 °C · Battery 30 °C · Fan 1200 rpm",
                     "temperature lists its component readings")

        let battery = model.cards.first { $0.id == .battery }!
        suite.expect(battery.value == "85%", "battery shows charge")
        suite.expect(battery.badge?.text == "On Power", "battery shows external power")
        suite.expect(battery.detail == "7.0 W · 7.0 W", "battery shows system and adapter watts")

        let processes = model.cards.first { $0.id == .processes }!
        suite.expect(processes.isAvailable && processes.value == "4",
                     "the process card reports its visible row count")
        suite.expect(model.processes.map(\.name) == ["Vorssaint", "Qind", "WindowServer", "ControlCenter"],
                     "processes sort by CPU and stop at four rows")

        let reordered = UnifiedMonitorAdapter.make(
            input: input,
            preferences: UnifiedMonitorCardPreferences(order: [.network, .cpu],
                                                       hiddenCards: [.gpu])
        )
        suite.expect(reordered.cards.map(\.id) == [.network, .cpu, .gpu, .memory, .disk,
                                                   .temperature, .battery, .processes],
                     "unknown order entries are appended in canonical order")
        suite.expect(reordered.cards.first { $0.id == .gpu }?.isEnabled == false,
                     "hidden cards stay in the model but are disabled")
        suite.expect(!reordered.visibleCards.contains { $0.id == .gpu },
                     "hidden cards are absent from the visible list")

        var missing = UnifiedMonitorInput()
        missing.machine = input.machine
        let empty = UnifiedMonitorAdapter.make(input: missing)
        suite.expect(empty.cards.allSatisfy { !$0.isAvailable },
                     "missing hardware makes every card unavailable")
        suite.expect(empty.visibleCards.isEmpty, "an unavailable dashboard renders no cards")
        suite.expect(empty.processes.isEmpty, "no process input produces no rows")

        var hot = input
        hot.cpuUsage = 0.95
        hot.cpuTemperature = 90
        hot.memoryPressure = .warning
        hot.disk = DiskReading(devices: [disk.with(used: 440_000_000_000)])
        hot.power = UnifiedPowerInput(systemWatts: 5,
                                      adapterWatts: nil,
                                      batteryWatts: -5,
                                      chargePercent: 10,
                                      timeRemainingSeconds: 600,
                                      healthPercent: 80,
                                      isCharging: false,
                                      externalConnected: false,
                                      hasBattery: true)
        let warning = UnifiedMonitorAdapter.make(input: hot)
        suite.expect(warning.cards.first { $0.id == .cpu }?.badge?.severity == .critical,
                     "a hot CPU is critical")
        suite.expect(warning.cards.first { $0.id == .memory }?.badge?.severity == .warning,
                     "memory pressure warnings pass through")
        suite.expect(warning.cards.first { $0.id == .disk }?.badge?.severity == .critical,
                     "a nearly full disk is critical")
        suite.expect(warning.cards.first { $0.id == .battery }?.badge?.severity == .critical,
                     "a low battery is critical")
        suite.expect(warning.cards.first { $0.id == .battery }?.detail == "5.0 W",
                     "battery falls back to the one available watt reading")

        var offline = input
        offline.networkAvailable = false
        let offlineModel = UnifiedMonitorAdapter.make(input: offline)
        suite.expect(offlineModel.cards.first { $0.id == .network }?.badge?.text == "Offline",
                     "an offline network gets an offline badge")
        suite.expect(offlineModel.cards.first { $0.id == .network }?.isAvailable == false,
                     "an offline network card is unavailable")

        var longHistory = input
        var points: [Double] = []
        for index in 0..<100 {
            if index == 0 {
                points.append(-1)
            } else if index == 1 {
                points.append(2)
            } else {
                points.append(Double(index) / 100)
            }
        }
        points[2] = .nan
        longHistory.cpuHistory = points
        let clipped = UnifiedMonitorAdapter.make(input: longHistory)
            .cards.first { $0.id == .cpu }?.history ?? []
        suite.expect(clipped.count == 60, "history is capped at 60 points")
        suite.expect(clipped.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 },
                     "CPU history is clamped and never contains NaN")
    }
}

private extension DiskDeviceReading {
    func with(used: UInt64) -> DiskDeviceReading {
        var copy = self
        copy.usedBytes = used
        copy.freeBytes = totalBytes - used
        return copy
    }
}
