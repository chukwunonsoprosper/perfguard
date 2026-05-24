import SwiftUI

// MARK: - Main Dashboard
struct DashboardView: View {
    @ObservedObject var manager: PerformanceManager
    @State private var selectedTab: Tab = .dashboard

    enum Tab { case dashboard, processes, cleanup }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "0D0F1A"), Color(hex: "111827")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HeaderView()

                // Tab Bar
                TabBarView(selected: $selectedTab)

                // Content
                Group {
                    switch selectedTab {
                    case .dashboard:  MainDashboard(manager: manager)
                    case .processes:  ProcessListView(manager: manager)
                    case .cleanup:    CleanupView(manager: manager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 380, height: 520)
    }
}

// MARK: - Header
struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "bolt.shield.fill")
                .foregroundColor(Color(hex: "00E5FF"))
                .font(.system(size: 18, weight: .bold))
            Text("PerfGuard")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Circle()
                .fill(Color(hex: "00FF88"))
                .frame(width: 6, height: 6)
            Text("ACTIVE")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "00FF88"))
                .kerning(1.5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(hex: "0D0F1A").opacity(0.8))
    }
}

// MARK: - Tab Bar
struct TabBarView: View {
    @Binding var selected: DashboardView.Tab

    var body: some View {
        HStack(spacing: 0) {
            TabButton(title: "Dashboard", icon: "gauge", tab: .dashboard, selected: $selected)
            TabButton(title: "Processes", icon: "list.bullet", tab: .processes, selected: $selected)
            TabButton(title: "Cleanup", icon: "sparkles", tab: .cleanup, selected: $selected)
        }
        .background(Color(hex: "161829"))
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let tab: DashboardView.Tab
    @Binding var selected: DashboardView.Tab

    var isSelected: Bool { selected == tab }

    var body: some View {
        Button(action: { selected = tab }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(isSelected ? Color(hex: "00E5FF") : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color(hex: "00E5FF").opacity(0.08) : Color.clear
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color(hex: "00E5FF") : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Dashboard Tab
struct MainDashboard: View {
    @ObservedObject var manager: PerformanceManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // RAM Card
                RAMGaugeCard(manager: manager)

                // Quick Actions
                HStack(spacing: 8) {
                    ActionButton(title: "RAM Boost", icon: "bolt.fill", color: Color(hex: "00E5FF")) {
                        manager.boostRAM()
                    }
                    ActionButton(title: "Kill Unused", icon: "xmark.circle.fill", color: Color(hex: "FF6B6B")) {
                        manager.killUnapprovedProcesses()
                    }
                    ActionButton(title: "Clean Cache", icon: "sparkles", color: Color(hex: "00FF88")) {
                        manager.runCleanup()
                    }
                }

                // Stats Row
                HStack(spacing: 8) {
                    StatCard(title: "Total RAM", value: String(format: "%.0fGB", manager.ramTotalGB), icon: "memorychip")
                    StatCard(title: "Used", value: String(format: "%.1fGB", manager.ramUsedGB), icon: "chart.bar.fill")
                    StatCard(title: "Processes", value: "\(manager.runningProcesses.count)", icon: "app.badge")
                }

                // Unapproved Warning
                let unapproved = manager.runningProcesses.filter { !$0.isApproved }
                if !unapproved.isEmpty {
                    UnapprovedWarning(count: unapproved.count)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - RAM Gauge
struct RAMGaugeCard: View {
    @ObservedObject var manager: PerformanceManager

    var pressureColor: Color {
        if manager.ramPressure < 0.6 { return Color(hex: "00FF88") }
        if manager.ramPressure < 0.8 { return Color(hex: "FFB800") }
        return Color(hex: "FF6B6B")
    }

    var pressureLabel: String {
        if manager.ramPressure < 0.6 { return "NORMAL" }
        if manager.ramPressure < 0.8 { return "MODERATE" }
        return "HIGH"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("MEMORY PRESSURE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .kerning(1.5)
                Spacer()
                Text(pressureLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(pressureColor)
                    .kerning(1.5)
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(hex: "00E5FF"), pressureColor], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * manager.ramPressure, height: 8)
                        .animation(.spring(), value: manager.ramPressure)
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.1f GB used", manager.ramUsedGB))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "of %.0f GB", manager.ramTotalGB))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "161829")))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "00E5FF").opacity(0.7))
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .kerning(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "161829")))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Unapproved Warning
struct UnapprovedWarning: View {
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "FFB800"))
            Text("\(count) unauthorized process\(count > 1 ? "es" : "") running in background")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "FFB800"))
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "FFB800").opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "FFB800").opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Process List Tab
struct ProcessListView: View {
    @ObservedObject var manager: PerformanceManager

    var body: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("PROCESS")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.3)).kerning(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("MEM")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.3)).kerning(1)
                    .frame(width: 45)
                Text("CPU")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.3)).kerning(1)
                    .frame(width: 40)
                Text("STATUS")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.3)).kerning(1)
                    .frame(width: 60)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "161829"))

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(manager.runningProcesses) { process in
                        ProcessRow(process: process, manager: manager)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }
}

struct ProcessRow: View {
    let process: ProcessInfo
    @ObservedObject var manager: PerformanceManager
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Approved dot
            Circle()
                .fill(process.isApproved ? Color(hex: "00FF88") : Color(hex: "FF6B6B"))
                .frame(width: 5, height: 5)

            Text(process.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.0fM", process.memoryMB))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 45)

            Text(String(format: "%.1f%%", process.cpuUsage))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(process.cpuUsage > 10 ? Color(hex: "FFB800") : .white.opacity(0.5))
                .frame(width: 40)

            HStack(spacing: 4) {
                Button(action: { manager.toggleApproval(for: process.name) }) {
                    Text(process.isApproved ? "✓" : "Block")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(process.isApproved ? Color(hex: "00FF88") : Color(hex: "00E5FF"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(
                            process.isApproved ? Color(hex: "00FF88").opacity(0.1) : Color(hex: "00E5FF").opacity(0.1)
                        ))
                }
                .buttonStyle(.plain)

                if !process.isApproved {
                    Button(action: { manager.killProcess(process) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color(hex: "FF6B6B"))
                            .padding(3)
                            .background(Circle().fill(Color(hex: "FF6B6B").opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { hovered = $0 }
    }
}

// MARK: - Cleanup Tab
struct CleanupView: View {
    @ObservedObject var manager: PerformanceManager

    var body: some View {
        VStack(spacing: 12) {
            // Big cleanup button
            Button(action: { manager.runCleanup() }) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "00E5FF"))
                    Text("Run Full Cleanup")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Clears caches, temp files & inactive memory")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "00E5FF").opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "00E5FF").opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if let lastTime = manager.lastCleanupTime {
                Text("Last cleanup: \(lastTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
            }

            // Auto-cleanup info
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(Color(hex: "00FF88"))
                    .font(.system(size: 11))
                Text("Auto-cleanup every 30 minutes")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "00FF88").opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "00FF88").opacity(0.15), lineWidth: 1))

            // Log
            if !manager.cleanupLog.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ACTIVITY LOG")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .kerning(1.5)
                        .padding(.bottom, 6)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(manager.cleanupLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
            }

            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
