// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum UnifiedMonitorSupport {
    static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 0
        else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0
        else { return "Mac" }
        let name = buffer.withUnsafeBufferPointer {
            String(cString: $0.baseAddress!)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Mac" : name
    }

    static func loadAverage() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return nil }
        return loads[0]
    }

    static func processInputs(_ rows: [ProcessUsage]) -> [UnifiedProcessInput] {
        rows.map {
            UnifiedProcessInput(pid: $0.pid,
                                name: $0.name,
                                memoryBytes: nil,
                                cpuPercent: $0.value)
        }
    }
}
