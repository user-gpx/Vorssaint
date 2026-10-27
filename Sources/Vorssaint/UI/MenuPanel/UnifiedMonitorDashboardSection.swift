// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The unified monitor overview: one header and a compact grid of live cards,
/// replacing the separate System, Network, Disk and Power tabs while enabled.
struct UnifiedMonitorDashboardSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.unifiedMonitorCardOrder) private var cardOrderRaw = ""
    @AppStorage(DefaultsKey.unifiedMonitorHiddenCards) private var hiddenCardsRaw = ""
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    var collapsible = true
    var openMetric: (MetricDetailKind) -> Void = { _ in }
    @State private var processRows: [ProcessUsage] = []
    @State private var processRowsLoading = false
    @State private var lastProcessRefresh = Date.distantPast
    private static let chipName = UnifiedMonitorSupport.chipName()

    var body: some View {
        PanelSection(.monitorDashboard, title: l10n.s.tabMonitor, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 8) {
                header
                cardGrid
                if !processRows.isEmpty, processCard != nil {
                    processList
                }
            }
        }
        .onAppear {
            refreshProcessRows(force: true)
        }
        .onReceive(monitor.$snapshot) { _ in
            refreshProcessRows(force: false)
        }
        .onDisappear {
            processRows = []
            processRowsLoading = false
        }
    }

    private var unit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    private var model: UnifiedMonitorModel {
        let snapshot = monitor.snapshot
        var input = UnifiedMonitorInput()
        input.cpuUsage = snapshot.cpuUsage
        input.cpuTemperature = snapshot.cpuTemperature
        input.cpuHistory = snapshot.cpuHistory
        input.loadAverage = UnifiedMonitorSupport.loadAverage()
        input.coreCount = ProcessInfo.processInfo.activeProcessorCount
        input.gpuUsage = snapshot.gpuUsage
        input.gpuTemperature = snapshot.gpuTemperature
        input.gpuHistory = snapshot.gpuHistory
        input.memoryUsed = snapshot.memoryUsed
        input.memoryAppUsed = snapshot.memoryAppUsed
        input.memoryTotal = snapshot.memoryTotal
        input.memoryPressure = memoryPressure(snapshot.memoryPressure)
        input.memoryHistory = snapshot.memoryHistory
        input.disk = snapshot.disk
        input.diskReadHistory = snapshot.diskReadHistory
        input.diskWriteHistory = snapshot.diskWriteHistory
        input.netDownBytesPerSec = snapshot.netDownBytesPerSec
        input.netUpBytesPerSec = snapshot.netUpBytesPerSec
        input.netTotalDown = snapshot.netTotalDown
        input.netTotalUp = snapshot.netTotalUp
        input.netDownHistory = snapshot.netDownHistory
        input.netUpHistory = snapshot.netUpHistory
        input.networkAvailable = snapshot.netDownBytesPerSec != nil || snapshot.netUpBytesPerSec != nil
        input.batteryTemperature = snapshot.batteryTemperature
        input.fanSpeeds = snapshot.fanSpeeds
        input.power = snapshot.power.map {
            UnifiedPowerInput(systemWatts: $0.systemWatts,
                              adapterWatts: $0.adapterWatts,
                              batteryWatts: $0.batteryWatts,
                              chargePercent: $0.chargePercent,
                              timeRemainingSeconds: $0.timeRemainingSeconds,
                              healthPercent: $0.healthPercent,
                              isCharging: $0.isCharging,
                              externalConnected: $0.externalConnected,
                              hasBattery: $0.hasBattery)
        }
        input.batteryHistory = snapshot.batteryHistory
        input.processes = UnifiedMonitorSupport.processInputs(processRows)
        input.machine = UnifiedMachineInput(chipName: Self.chipName,
                                            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                            uptime: ProcessInfo.processInfo.systemUptime,
                                            date: Date())
        return UnifiedMonitorAdapter.make(input: input,
                                          preferences: cardPreferences,
                                          temperatureUnit: unit)
    }

    private var cardPreferences: UnifiedMonitorCardPreferences {
        _ = cardOrderRaw
        let order = PanelLayout.itemOrder(UnifiedMonitorCardID.self,
                                          key: DefaultsKey.unifiedMonitorCardOrder)
        return UnifiedMonitorCardPreferences(order: order,
                                             hiddenCards: unavailableHiddenCards.union(storedHiddenCards))
    }

    private var storedHiddenCards: Set<UnifiedMonitorCardID> {
        Set(hiddenCardsRaw.split(separator: ",").compactMap {
            UnifiedMonitorCardID(rawValue: String($0))
        })
    }

    private var unavailableHiddenCards: Set<UnifiedMonitorCardID> {
        var hidden = Set<UnifiedMonitorCardID>()
        if !AppFeature.monitorCPU.isAvailable { hidden.insert(.cpu) }
        if !AppFeature.monitorGPU.isAvailable { hidden.insert(.gpu) }
        if !AppFeature.monitorMemory.isAvailable { hidden.insert(.memory) }
        if !AppFeature.monitorNetwork.isAvailable { hidden.insert(.network) }
        if !AppFeature.monitorDisk.isAvailable { hidden.insert(.disk) }
        if !AppFeature.monitorPower.isAvailable {
            hidden.insert(.battery)
        }
        if !AppFeature.monitorCPU.isAvailable,
           !AppFeature.monitorGPU.isAvailable,
           !AppFeature.monitorPower.isAvailable {
            hidden.insert(.temperature)
        }
        return hidden
    }

    private var visibleCards: [UnifiedMonitorCardModel] {
        model.visibleCards.filter { $0.id != .processes }
    }

    private var processCard: UnifiedMonitorCardModel? {
        model.visibleCards.first { $0.id == .processes }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [PanelMetricColor.cyan(for: colorScheme),
                                                      PanelMetricColor.green(for: colorScheme)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .opacity(0.24)
                    Image(systemName: "memorychip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PanelMetricColor.cyan(for: colorScheme))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.header.chipName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        if let memory = model.header.memoryTotalBytes {
                            Text(MetricFormat.diskBytes(memory))
                            Text("·")
                        }
                        Text(cleanOSVersion(model.header.osVersion))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(model.header.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Label(uptimeText, systemImage: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(PanelMetricColor.green(for: colorScheme))
            }
        }
        .panelCard()
    }

    private var cardGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)],
                  spacing: 8) {
            ForEach(visibleCards) { card in
                cardButton(card)
            }
        }
    }

    @ViewBuilder
    private func cardButton(_ card: UnifiedMonitorCardModel) -> some View {
        if let metric = metric(for: card.id) {
            Button {
                openMetric(metric)
            } label: {
                cardBody(card)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title(for: card.id))
            .accessibilityValue(card.value)
        } else {
            cardBody(card)
                .accessibilityElement(children: .combine)
        }
    }

    private func cardBody(_ card: UnifiedMonitorCardModel) -> some View {
        let tint = color(for: card.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: card.id.defaultSymbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title(for: card.id))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(card.value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if let badge = card.badge {
                    Text(badge.text)
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(badgeColor(badge, fallback: tint))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor(badge, fallback: tint).opacity(0.12),
                                    in: Capsule())
                }
            }

            if let percent = card.percent {
                progress(percent, tint: tint)
            }

            if card.history.count >= 2 {
                Sparkline(values: card.history,
                          color: tint,
                          maxValue: card.chartStyle == .line ? nil : 1,
                          fillOpacity: 0.14,
                          lineWidth: 1.2)
                    .frame(height: 25)
            }

            if let detail = card.detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let load = card.load {
                Text("Load \(loadText(load)) · \(load.coreCount) cores")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Top Processes", systemImage: "list.bullet.rectangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(processRows.prefix(4)) { row in
                ProcessUsageRow(row: row,
                                value: String(format: "%.1f%%",
                                              locale: MetricFormat.locale,
                                              MetricFormat.boundedPercentage(row.value)),
                                iconSize: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private func progress(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
    }

    private func metric(for id: UnifiedMonitorCardID) -> MetricDetailKind? {
        switch id {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .disk: return .disk
        case .network: return .network
        case .battery: return .battery
        case .temperature, .processes: return nil
        }
    }

    private func title(for id: UnifiedMonitorCardID) -> String {
        switch id {
        case .cpu: return l10n.s.cpuLabel
        case .gpu: return l10n.s.gpuLabel
        case .memory: return l10n.s.memorySection
        case .disk: return l10n.s.diskSection
        case .network: return l10n.s.networkSection
        case .temperature: return l10n.s.temperatures
        case .battery: return l10n.s.batteryLabel
        case .processes: return "Processes"
        }
    }

    private func color(for id: UnifiedMonitorCardID) -> Color {
        switch id {
        case .cpu: return PanelMetricColor.cyan(for: colorScheme)
        case .gpu: return PanelMetricColor.pink(for: colorScheme)
        case .memory: return PanelMetricColor.green(for: colorScheme)
        case .disk: return PanelMetricColor.orange(for: colorScheme)
        case .network: return Color.accentColor
        case .temperature: return PanelMetricColor.pink(for: colorScheme)
        case .battery: return PanelMetricColor.green(for: colorScheme)
        case .processes: return .secondary
        }
    }

    private func badgeColor(_ badge: UnifiedMonitorBadge, fallback: Color) -> Color {
        switch badge.severity {
        case .normal: return fallback
        case .warning: return PanelMetricColor.yellow(for: colorScheme)
        case .critical: return PanelMetricColor.red(for: colorScheme)
        case .neutral: return .secondary
        }
    }

    private var uptimeText: String {
        let seconds = Int(max(0, model.header.uptime))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func loadText(_ load: UnifiedLoadState) -> String {
        String(format: "%.2f", locale: MetricFormat.locale, load.average)
    }

    private func cleanOSVersion(_ version: String) -> String {
        version.replacingOccurrences(of: "Version ", with: "")
    }

    private func memoryPressure(_ pressure: MemoryPressure) -> UnifiedMemoryPressure {
        switch pressure {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        case .unknown: return .unknown
        }
    }

    private func refreshProcessRows(force: Bool) {
        let interval = TimeInterval(Defaults.sanitizedMonitorInterval(monitorInterval))
        guard force || Date().timeIntervalSince(lastProcessRefresh) >= max(1, interval * 0.8) else {
            return
        }
        lastProcessRefresh = Date()
        if let cached = ProcessUsageService.shared.cachedTop(.cpu, limit: 4) {
            processRows = cached
            return
        }
        guard !processRowsLoading else { return }
        processRowsLoading = true
        let cpuPercentage = monitor.snapshot.cpuUsage.map { $0 * 100 }
        DispatchQueue.global(qos: .utility).async {
            let rows = ProcessUsageService.shared.top(.cpu,
                                                      limit: 4,
                                                      sampleInterval: interval,
                                                      cpuPercentage: cpuPercentage)
            DispatchQueue.main.async {
                processRowsLoading = false
                if !rows.isEmpty {
                    processRows = rows
                }
            }
        }
    }
}

extension UnifiedMonitorCardID: PanelOrderItem {}
