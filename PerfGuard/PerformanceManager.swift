import Foundation
import AppKit
import Combine

// MARK: - Process Info Model
struct ProcessInfo: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryMB: Double
    let isApproved: Bool
}

// MARK: - Performance Manager
class PerformanceManager: ObservableObject {
    @Published var ramUsedGB: Double = 0
    @Published var ramTotalGB: Double = 0
    @Published var ramPressure: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var runningProcesses: [ProcessInfo] = []
    @Published var approvedApps: Set<String> = [
        "Finder", "Safari", "Chrome", "Firefox", "Code", "Terminal",
        "Xcode", "Slack", "Zoom", "Mail", "Messages", "Music",
        "Notes", "Calendar", "SystemPreferences", "System Preferences",
        "PerfGuard", "loginwindow", "WindowServer", "Dock", "Spotlight"
    ]
    @Published var lastCleanupTime: Date? = nil
    @Published var cleanupLog: [String] = []

    private var monitoringTimer: Timer?
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUCount: mach_msg_type_number_t = 0

    // MARK: - Monitoring
    func startMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.updateStats()
        }
        updateStats()
    }

    func stopMonitoring() {
        monitoringTimer?.invalidate()
    }

    func updateStats() {
        DispatchQueue.global(qos: .background).async {
            let (used, total, pressure) = self.getRAMStats()
            let processes = self.getRunningProcesses()
            DispatchQueue.main.async {
                self.ramUsedGB = used
                self.ramTotalGB = total
                self.ramPressure = pressure
                self.runningProcesses = processes
            }
        }
    }

    // MARK: - RAM Stats
    private func getRAMStats() -> (Double, Double, Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = Double(vm_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var used = total

        if result == KERN_SUCCESS {
            let free = Double(stats.free_count) * pageSize
            let inactive = Double(stats.inactive_count) * pageSize
            used = total - free - inactive
            let pressure = used / total
            return (used / 1_073_741_824, total / 1_073_741_824, pressure)
        }
        return (used / 1_073_741_824, total / 1_073_741_824, 0.5)
    }

    // MARK: - Process List
    func getRunningProcesses() -> [ProcessInfo] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid,pcpu,rss,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var processes: [ProcessInfo] = []
        let lines = output.components(separatedBy: "\n").dropFirst()

        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Double(parts[2]) else { continue }

            let fullPath = parts[3...].joined(separator: " ")
            let name = (fullPath as NSString).lastPathComponent

            let approved = approvedApps.contains(name) || approvedApps.contains(where: { name.contains($0) })
            processes.append(ProcessInfo(pid: pid, name: name, cpuUsage: cpu, memoryMB: rss / 1024, isApproved: approved))
        }

        return processes
            .filter { $0.memoryMB > 1 }
            .sorted { $0.memoryMB > $1.memoryMB }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Kill Process
    func killProcess(_ process: ProcessInfo) {
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-9", "\(process.pid)"]
        try? task.run()
        task.waitUntilExit()
        DispatchQueue.main.async {
            self.cleanupLog.insert("🔴 Killed: \(process.name)", at: 0)
            self.updateStats()
        }
    }

    // MARK: - RAM Boost (purge inactive memory)
    func boostRAM() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Request system to purge inactive memory via malloc pressure
            let task = Process()
            task.launchPath = "/usr/bin/memory_pressure"
            task.arguments = ["-S", "-l", "warn"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()

            DispatchQueue.main.async {
                self.cleanupLog.insert("⚡ RAM Boost applied", at: 0)
                self.updateStats()
            }
        }
    }

    // MARK: - Cache Cleanup
    func runCleanup() {
        DispatchQueue.global(qos: .background).async {
            var cleaned: [String] = []

            // Clear user caches
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
                var totalSize: Int64 = 0
                for file in files {
                    if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(size)
                    }
                    try? FileManager.default.removeItem(at: file)
                }
                if totalSize > 0 {
                    let mb = Double(totalSize) / 1_048_576
                    cleaned.append("🧹 Cleared \(String(format: "%.1f", mb))MB from caches")
                }
            }

            // Clear temp files
            let tempDir = FileManager.default.temporaryDirectory
            if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                let removed = files.filter { (try? FileManager.default.removeItem(at: $0)) != nil }
                if !removed.isEmpty {
                    cleaned.append("🧹 Cleared \(removed.count) temp files")
                }
            }

            DispatchQueue.main.async {
                self.lastCleanupTime = Date()
                if cleaned.isEmpty { cleaned = ["✅ System already clean"] }
                self.cleanupLog.insert(contentsOf: cleaned.reversed(), at: 0)
                if self.cleanupLog.count > 20 { self.cleanupLog = Array(self.cleanupLog.prefix(20)) }
                self.updateStats()
            }
        }
    }

    // MARK: - Kill Unapproved
    func killUnapprovedProcesses() {
        let unapproved = runningProcesses.filter { !$0.isApproved && $0.memoryMB > 50 }
        for process in unapproved {
            killProcess(process)
        }
        if unapproved.isEmpty {
            cleanupLog.insert("✅ No unauthorized heavy processes found", at: 0)
        }
    }

    // MARK: - Approve / Unapprove
    func toggleApproval(for name: String) {
        if approvedApps.contains(name) {
            approvedApps.remove(name)
        } else {
            approvedApps.insert(name)
        }
        updateStats()
    }
}
