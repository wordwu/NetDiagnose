import SwiftUI

struct DiagnosticConclusionView: View {
    let findings: [DiagnosticFinding]
    let score: Int
    let devices: [NetworkDevice]
    let scanDuration: TimeInterval
    let previousSnapshot: ScanSnapshot?
    let expertMode: Bool

    @StateObject private var notesService = DeviceNotesService.shared

    var visibleFindings: [DiagnosticFinding] {
        if expertMode { return findings }
        // Simple mode: hide .info and .good, only show warnings and critical
        return findings.filter { $0.severity == .warning || $0.severity == .critical }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Score + summary header
                scoreHeader

                // Key metrics row
                metricsRow

                // Finding cards
                if visibleFindings.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleFindings) { finding in
                        FindingCard(finding: finding)
                    }
                }

                // Previous scan comparison
                if let prev = previousSnapshot {
                    previousCompareView(prev: prev)
                }

                // Simple mode hint
                if !expertMode && findings.count > visibleFindings.count {
                    HStack {
                        Image(systemName: "eye.slash").font(.system(size: 11)).foregroundColor(.gray)
                        Text("隐藏了 \(findings.count - visibleFindings.count) 条提示信息，切换到「专家」模式查看全部")
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(Color(hex: "#020617"))
    }

    var scoreHeader: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(criticalCount > 0 ? Color.red.opacity(0.2) : Color.green.opacity(0.2), lineWidth: 10)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(score)").font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text("健康分").font(.system(size: 11)).foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(summaryTitle).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                HStack(spacing: 12) {
                    Label("\(findings.filter {$0.severity == .critical}.count) 严重", systemImage: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 12))
                    Label("\(findings.filter {$0.severity == .warning}.count) 注意", systemImage: "exclamationmark.circle").foregroundColor(.yellow).font(.system(size: 12))
                    Label("\(findings.filter {$0.severity == .info}.count) 提示", systemImage: "info.circle").foregroundColor(.blue).font(.system(size: 12))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("扫描耗时").font(.system(size: 11)).foregroundColor(.gray)
                Text(String(format: "%.1f 秒", scanDuration)).font(.system(size: 15, design: .monospaced)).foregroundColor(.white)
            }
        }
        .padding(20)
        .background(Color(hex: "#0f172a"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var metricsRow: some View {
        let online = devices.filter(\.isOnline).count
        let risky = devices.filter { $0.riskLevel != .low }.count
        let avgLat = devices.compactMap(\.latencyMs).isEmpty ? 0.0 : devices.compactMap(\.latencyMs).reduce(0.0, +) / Double(devices.filter { $0.latencyMs != nil }.count)

        return HStack(spacing: 12) {
            metricCard(icon: "wifi", label: "在线", value: "\(online)/\(devices.count)", color: .green)
            metricCard(icon: "shield", label: "风险", value: "\(risky)", color: risky > 0 ? .red : .green)
            metricCard(icon: "stopwatch", label: "均延迟", value: String(format: "%.0fms", avgLat), color: avgLat < 50 ? .green : .orange)
            metricCard(icon: "cpu", label: "类型", value: "\(Dictionary(grouping: devices, by: \.deviceType).count)", color: .cyan)
        }
    }

    func metricCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 40)).foregroundColor(.green)
            Text("网络状态良好").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Text("未发现需要关注的问题").font(.system(size: 13)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    func previousCompareView(prev: ScanSnapshot) -> some View {
        let prevIPs = Set(prev.devices.map(\.ipAddress))
        let currIPs = Set(devices.map(\.ipAddress))
        let newCount = currIPs.subtracting(prevIPs).count
        let lostCount = prevIPs.subtracting(currIPs).count

        return VStack(alignment: .leading, spacing: 8) {
            Label("与上次扫描对比 (\(prev.timestamp.formatted(date: .abbreviated, time: .shortened)))", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            HStack(spacing: 20) {
                Label("+\(newCount) 新增", systemImage: "plus.circle").foregroundColor(.green).font(.system(size: 13))
                Label("-\(lostCount) 离线", systemImage: "minus.circle").foregroundColor(.gray).font(.system(size: 13))
                Label("\(currIPs.intersection(prevIPs).count) 不变", systemImage: "equal.circle").foregroundColor(.blue).font(.system(size: 13))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Helpers
    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }

    var scoreColor: Color {
        score >= 80 ? .green : score >= 60 ? .yellow : score >= 40 ? .orange : .red
    }

    var summaryTitle: String {
        if criticalCount > 0 { return "需要立即处理" }
        if warningCount > 0 { return "有改进空间" }
        if score >= 80 { return "网络健康" }
        return "网络需关注"
    }
}

struct FindingCard: View {
    let finding: DiagnosticFinding
    let notes = DeviceNotesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName).foregroundColor(iconColor)
                Text(finding.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text(finding.severity.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(severityColor.opacity(0.15))
                    .foregroundColor(severityColor)
                    .clipShape(Capsule())
            }
            Text(finding.explanation).font(.system(size: 13)).foregroundColor(.gray)
            if !finding.action.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                    Text(finding.action).font(.system(size: 12))
                }
                .foregroundColor(.cyan.opacity(0.8))
            }
            if !finding.affectedIPs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(finding.affectedIPs, id: \.self) { ip in
                            Button(ip) {
                                // Could open device detail
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.1))
                            .foregroundColor(.cyan)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#0f172a"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var iconName: String {
        switch finding.severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle"
        case .info: return "info.circle"
        case .good: return "checkmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .good: return .green
        }
    }

    var severityColor: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .good: return .green
        }
    }
}

struct FindingRow: View {
    let finding: DiagnosticFinding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(severityColor).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title).font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                Text(finding.explanation).font(.system(size: 12)).foregroundColor(.gray)
            }
        }
    }

    var severityColor: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .good: return .green
        }
    }
}
