import SwiftUI
import AppKit
import WebKit

// MARK: - Device Detail Sheet

struct DeviceDetailSheetMac: View {
    let device: NetworkDevice
    let devices: [NetworkDevice]
    let config: ScanConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设备详情").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Status + Type + Confidence
                    HStack {
                        Circle().fill(device.isOnline ? Color.green : Color.gray).frame(width: 12, height: 12)
                        Text(device.isOnline ? "在线" : "离线")
                            .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(device.deviceType.rawValue).font(.system(size: 12)).foregroundColor(.cyan)
                            confidenceBadge
                        }
                    }

                    InfoRowMac(label: "IP 地址", value: device.ipAddress)
                    InfoRowMac(label: "MAC 地址", value: device.macAddress ?? "未知")
                    InfoRowMac(label: "厂商", value: device.vendor ?? "未知")
                    InfoRowMac(label: "主机名", value: device.hostname ?? "未获取")
                    if let lat = device.latencyMs {
                        InfoRowMac(label: "延迟", value: String(format: "%.1f ms", lat))
                    }

                    // Risk
                    if !device.riskNotes.isEmpty || device.riskLevel != .low {
                        Divider().background(Color(hex: "#1e293b"))
                        HStack {
                            Text("风险等级").font(.system(size: 12)).foregroundColor(.gray)
                            riskBadge
                        }
                        ForEach(device.riskNotes, id: \.self) { note in
                            Text("• \(note)").font(.system(size: 11)).foregroundColor(.orange)
                        }
                    }

                    // Discovery sources
                    if !device.discoverySources.isEmpty {
                        Divider().background(Color(hex: "#1e293b"))
                        Text("发现来源").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        HStack(spacing: 6) {
                            ForEach(device.discoverySources, id: \.self) { src in
                                Text(src.rawValue)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.15))
                                    .foregroundColor(.cyan)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Identification evidence
                    if !device.identificationEvidence.isEmpty {
                        Text("识别依据").font(.system(size: 12, weight: .semibold)).foregroundColor(.white).padding(.top, 4)
                        ForEach(device.identificationEvidence, id: \.self) { ev in
                            Text(ev)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }

                    // Open ports
                    if !device.openPorts.isEmpty {
                        Divider().background(Color(hex: "#1e293b"))
                        Text("开放端口").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        Text(device.openPorts.map(String.init).joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("开放端口可能带来安全风险，请确保仅在必要时开放。")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .background(Color(hex: "#020617"))
    }

    var confidenceBadge: some View {
        let c = device.identificationConfidence
        let color: Color = c == .high ? .green : c == .medium ? .yellow : .gray
        return Text(c.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    var riskBadge: some View {
        let color: Color = device.riskLevel == .high ? .red : device.riskLevel == .medium ? .orange : .green
        return Text(device.riskLevel.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct InfoRowMac: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.gray).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
        }
    }
}

// MARK: - Device List Sheet

struct DeviceListSheetMac: View {
    let devices: [NetworkDevice]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\u{8BBE}\u{5907}\u{6E05}\u{5355}").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            List(devices) { dev in
                HStack {
                    Circle().fill(dev.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dev.ipAddress).font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                        Text(dev.deviceType.rawValue).font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    if let lat = dev.latencyMs {
                        Text(String(format: "%.1fms", lat))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(lat < 10 ? .green : lat < 50 ? .yellow : .red)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
        .background(Color(hex: "#020617"))
    }
}

// MARK: - Recommendation Sheet

struct RecommendationSheetMac: View {
    let recommendations: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\u{5347}\u{7EA7}\u{5EFA}\u{8BAE}").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if recommendations.isEmpty {
                        Text("\u{7F51}\u{7EDC}\u{72B6}\u{51B5}\u{826F}\u{597D}\u{FF0C}\u{6682}\u{65E0}\u{5EFA}\u{8BAE}")
                            .foregroundColor(.gray).font(.system(size: 13))
                    } else {
                        ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundColor(.cyan).font(.system(size: 14))
                                Text(rec).font(.system(size: 13)).foregroundColor(.gray)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(hex: "#020617"))
    }
}

// MARK: - Health Detail Sheet

struct HealthDetailSheet: View {
    let breakdown: ScanOrchestrator.HealthBreakdown
    let tips: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("健康详情").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Total score
                    HStack {
                        Text("总分").font(.system(size: 14)).foregroundColor(.gray)
                        Spacer()
                        Text("\(breakdown.total)/100")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(scoreColor)
                    }

                    Divider().background(Color(hex: "#1e293b"))

                    // Breakdown items
                    ScoreRow(
                        label: "基础分", value: "+\(breakdown.baseScore)",
                        color: .green, detail: "起始满分"
                    )

                    if breakdown.offlinePenalty > 0 {
                        ScoreRow(
                            label: "离线设备", value: "-\(breakdown.offlinePenalty)",
                            color: .orange, detail: "\(breakdown.offlineCount) 台设备离线，每台 -2，上限 -15"
                        )
                    }

                    if breakdown.latencyPenalty > 0 {
                        ScoreRow(
                            label: "网络延迟", value: "-\(breakdown.latencyPenalty)",
                            color: breakdown.latencyPenalty >= 15 ? .red : .orange,
                            detail: "平均延迟偏高" + (breakdown.avgLatency.map { String(format: " (%.0fms)", $0) } ?? "")
                        )
                    }

                    if breakdown.portPenalty > 0 {
                        ScoreRow(
                            label: "危险端口", value: "-\(breakdown.portPenalty)",
                            color: .red,
                            detail: "\(breakdown.dangerousPortCount) 个端口暴露（Telnet/RDP/VNC），每个 -3，上限 -15"
                        )
                    }

                    if breakdown.unknownPenalty > 0 {
                        ScoreRow(
                            label: "未识别设备", value: "-\(breakdown.unknownPenalty)",
                            color: .yellow,
                            detail: "\(breakdown.unknownCount) 台设备类型未知，每台 -1，上限 -5"
                        )
                    }

                    if !tips.isEmpty {
                        Divider().background(Color(hex: "#1e293b"))
                        Text("建议").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                            Text("• \(tip)").font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(hex: "#020617"))
    }

    var scoreColor: Color {
        let s = breakdown.total
        return s >= 80 ? .green : s >= 60 ? .yellow : s >= 40 ? .orange : .red
    }
}

struct ScoreRow: View {
    let label: String
    let value: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundColor(.gray)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Export Report Sheet

struct ExportReportSheet: View {
    let devices: [NetworkDevice]
    let config: ScanConfig
    let tips: [String]
    let score: Int
    @Environment(\.dismiss) private var dismiss

    private var onlineCount: Int { devices.filter(\.isOnline).count }
    private var riskDevices: [NetworkDevice] { devices.filter { $0.riskLevel == .high || $0.riskLevel == .medium } }
    private var typeBreakdown: [(DeviceType, Int)] {
        Dictionary(grouping: devices, by: \.deviceType).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("导出 PDF 报告").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preview header
                    HStack {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NetDiagnose 网络诊断报告")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            Text("\(config.cidrNotation) · \(Date().formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                    .padding(12)
                    .background(Color.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Report contents preview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("报告包含").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        
                        previewItem(icon: "heart.fill", color: score >= 80 ? .green : .orange,
                                    text: "健康评分 \(score)/100")
                        previewItem(icon: "list.bullet.rectangle", color: .cyan,
                                    text: "\(devices.count) 台设备清单（\(onlineCount) 在线）")
                        previewItem(icon: "chart.pie", color: .purple,
                                    text: "\(typeBreakdown.count) 类设备分布: \(typeBreakdown.prefix(3).map { "\($0.0.rawValue)×\($0.1)" }.joined(separator: ", "))")
                        if !riskDevices.isEmpty {
                            previewItem(icon: "exclamationmark.shield", color: .red,
                                        text: "\(riskDevices.count) 台设备有风险需关注")
                        }
                        if !tips.isEmpty {
                            previewItem(icon: "lightbulb", color: .yellow,
                                        text: "\(tips.count) 条诊断建议")
                        }
                        previewItem(icon: "antenna.radiowaves.left.and.right", color: .gray,
                                    text: "网络配置摘要（网关/子网/接口）")
                    }

                    Divider().background(Color(hex: "#1e293b"))

                    // Privacy notice
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield").foregroundColor(.green).font(.system(size: 12))
                        Text("所有扫描数据仅保存在本机，不上传服务器。PDF 仅供个人参考。")
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }

                    // Save button
                    Button("保存 PDF...") {
                        // 统一走 ExportService：报告内容与导出面板完全一致
                        let findings = tips.map {
                            DiagnosticFinding(severity: .info, title: "诊断建议", explanation: $0, action: "")
                        }
                        let html = ExportService.generateHTML(
                            devices: devices, config: config, findings: findings,
                            score: score, notes: DeviceNotesService.shared.allNotes()
                        )
                        ExportService.savePDF(html: html, defaultName: "NetDiagnose-\(Date().ISO8601Short).pdf") { _ in }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .background(Color(hex: "#020617"))
    }

    func previewItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11))
                .foregroundColor(color).frame(width: 18)
            Text(text).font(.system(size: 12)).foregroundColor(.gray)
        }
    }

}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            .sRGB,
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Date Helper

extension Date {
    var ISO8601Short: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: self)
    }
}
