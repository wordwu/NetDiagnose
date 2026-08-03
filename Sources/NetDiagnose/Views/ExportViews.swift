import SwiftUI

struct ExportSheetInline: View {
    let devices: [NetworkDevice]
    let config: ScanConfig
    let findings: [DiagnosticFinding]
    let score: Int
    let notes: [DeviceNote]
    @Binding var showShareCard: Bool

    private var onlineCount: Int { devices.filter(\.isOnline).count }
    private var typeBreakdown: [(DeviceType, Int)] {
        Dictionary(grouping: devices, by: \.deviceType).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Report preview
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 28)).foregroundColor(.cyan)
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

                    previewItem(icon: "heart.fill", color: score >= 80 ? .green : .orange, text: "健康评分 \(score)/100")
                    previewItem(icon: "list.bullet.rectangle", color: .cyan, text: "\(devices.count) 台设备（\(onlineCount) 在线）")
                    previewItem(icon: "stethoscope", color: .purple, text: "\(findings.count) 条诊断结果")
                }

                Divider().background(Color(hex: "#1e293b"))

                // Format picker
                VStack(alignment: .leading, spacing: 10) {
                    Text("导出格式").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)

                    HStack(spacing: 12) {
                        exportButton(format: "PDF", icon: "doc.fill", color: .cyan) {
                            let html = ExportService.generateHTML(devices: devices, config: config, findings: findings, score: score, notes: notes)
                            ExportService.savePDF(html: html, defaultName: "NetDiagnose-\(Date().ISO8601Short).pdf") { _ in }
                        }
                        exportButton(format: "HTML", icon: "safari", color: .orange) {
                            let html = ExportService.generateHTML(devices: devices, config: config, findings: findings, score: score, notes: notes)
                            ExportService.saveText(content: html, ext: "html", defaultName: "NetDiagnose-\(Date().ISO8601Short).html")
                        }
                        exportButton(format: "Markdown", icon: "doc.plaintext", color: .green) {
                            let md = ExportService.generateMarkdown(devices: devices, config: config, findings: findings, score: score, notes: notes)
                            ExportService.saveText(content: md, ext: "md", defaultName: "NetDiagnose-\(Date().ISO8601Short).md")
                        }
                        exportButton(format: "CSV", icon: "tablecells", color: .blue) {
                            let csv = ExportService.generateCSV(devices: devices, findings: findings, score: score, notes: notes)
                            ExportService.saveText(content: csv, ext: "csv", defaultName: "NetDiagnose-\(Date().ISO8601Short).csv")
                        }
                        exportButton(format: "JSON", icon: "curlybraces", color: .purple) {
                            let json = ExportService.generateJSON(devices: devices, config: config, findings: findings, score: score, notes: notes)
                            ExportService.saveText(content: json, ext: "json", defaultName: "NetDiagnose-\(Date().ISO8601Short).json")
                        }
                    }
                }

                Divider().background(Color(hex: "#1e293b"))

                // Share card
                VStack(alignment: .leading, spacing: 8) {
                    Text("分享卡片").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text("生成一张诊断结果分享图，适合发朋友圈或即刻")
                        .font(.system(size: 12)).foregroundColor(.gray)

                    Button("预览分享卡片") {
                        showShareCard = true
                    }
                    .buttonStyle(.bordered).tint(.cyan)
                }

                Divider().background(Color(hex: "#1e293b"))

                // Privacy
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").foregroundColor(.green).font(.system(size: 12))
                    Text("所有扫描数据仅保存在本机，不上传服务器。")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            .padding(20)
        }
    }

    func previewItem(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color).frame(width: 18)
            Text(text).font(.system(size: 12)).foregroundColor(.gray)
        }
    }

    func exportButton(format: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 24)).foregroundColor(color)
                Text(format).font(.system(size: 11, weight: .medium)).foregroundColor(.white)
            }
            .frame(width: 80, height: 70)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Sheet version for multi-format export
struct ExportSheetNew: View {
    let devices: [NetworkDevice]
    let config: ScanConfig
    let findings: [DiagnosticFinding]
    let score: Int
    let notes: [DeviceNote]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .pdf

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("导出报告").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(spacing: 16) {
                Picker("格式", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                switch selectedFormat {
                case .pdf, .html:
                    // HTML preview
                    ScrollView {
                        Text(ExportService.generateHTML(devices: devices, config: config, findings: findings, score: score, notes: notes)
                            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).prefix(2000))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding()
                    }
                    .frame(height: 200)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                case .markdown:
                    previewMD
                }

                Button("保存...") {
                    switch selectedFormat {
                    case .pdf:
                        let html = ExportService.generateHTML(devices: devices, config: config, findings: findings, score: score, notes: notes)
                        ExportService.savePDF(html: html, defaultName: "NetDiagnose-\(Date().ISO8601Short).pdf") { _ in
                            dismiss()
                        }
                    case .html:
                        let html = ExportService.generateHTML(devices: devices, config: config, findings: findings, score: score, notes: notes)
                        ExportService.saveText(content: html, ext: "html", defaultName: "NetDiagnose-\(Date().ISO8601Short).html")
                        dismiss()
                    case .markdown:
                        let md = ExportService.generateMarkdown(devices: devices, config: config, findings: findings, score: score, notes: notes)
                        ExportService.saveText(content: md, ext: "md", defaultName: "NetDiagnose-\(Date().ISO8601Short).md")
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent).tint(.cyan).controlSize(.large)
            }
            .padding(24)
        }
        .background(Color(hex: "#020617"))
    }

    var previewMD: some View {
        let md = ExportService.generateMarkdown(devices: devices, config: config, findings: findings, score: score, notes: notes)
        return ScrollView {
            Text(md)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .padding()
        }
        .frame(height: 200)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
