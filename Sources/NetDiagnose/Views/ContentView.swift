import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var scanner = ScanOrchestrator()
    @State private var showSavePanel = false
    @State private var showExportError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Scan Button
                    scanSection

                    // Progress
                    if scanner.isScanning {
                        progressSection
                    }

                    // Results
                    if let result = scanner.scanResult, !scanner.isScanning {
                        healthScoreSection(result: result)
                        deviceTableSection(result: result)
                        tipsSection
                        exportSection

                        // Bottom: email + CTA
                        bottomSection
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 600)
        .fileExporter(isPresented: $showSavePanel,
                      document: PDFDocument(content: generatePDFContent()),
                      contentType: .pdf,
                      defaultFilename: "网络诊断报告_\(Date().ISO8601Short).pdf") { result in
            if case .failure = result { showExportError = true }
        }
        .alert("导出失败", isPresented: $showExportError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("PDF 报告生成失败，请重试。若持续失败，可直接截图保存报告。")
        }
    }

    // MARK: - Header

    var headerView: some View {
        HStack {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.title)
                .foregroundColor(.accentColor)
            Text("NetDiagnose")
                .font(.title2.bold())
            Spacer()
            Text("免费网络健康诊断")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Scan Button

    var scanSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                if scanner.isScanning { scanner.reset() }
                else { scanner.startScan() }
            }) {
                Label(
                    scanner.isScanning ? "停止" : "一键诊断",
                    systemImage: scanner.isScanning ? "stop.circle.fill" : "play.circle.fill"
                )
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(scanner.isScanning && scanner.progressValue > 0.9)

            if scanner.isScanning {
                Text(scanner.scanProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Progress

    var progressSection: some View {
        ProgressView(value: Double(scanner.progressValue), total: 1.0)
            .tint(.accentColor)
    }

    // MARK: - Health Score

    func healthScoreSection(result: ScanResult) -> some View {
        HStack(spacing: 20) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(result.healthScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(result.healthScore)")
                        .font(.title.bold())
                    Text("/100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scoreLabel)
                    .font(.headline)

                HStack(spacing: 16) {
                    Label("\(result.onlineCount) 在线", systemImage: "wifi")
                    Label("\(result.devices.count - result.onlineCount) 离线", systemImage: "wifi.slash")
                    if let avg = result.avgLatency {
                        Label("\(String(format: "%.0f", avg))ms 均延", systemImage: "stopwatch")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("扫描耗时")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f 秒", result.scanDuration))
                    .font(.body.monospacedDigit())
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var scoreColor: Color {
        switch scanner.healthScore {
        case 80...: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    var scoreLabel: String {
        switch scanner.healthScore {
        case 90...: return "👍 网络健康"
        case 70..<90: return "😐 网络基本正常"
        case 50..<70: return "⚠️ 网络需要关注"
        default: return "🔴 网络状况不佳"
        }
    }

    // MARK: - Device Table

    func deviceTableSection(result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("设备清单 (\(result.devices.count) 台)", systemImage: "list.bullet.rectangle")
                .font(.headline)

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("IP").frame(width: 120, alignment: .leading)
                    Text("MAC").frame(width: 140, alignment: .leading)
                    Text("厂商").frame(width: 80, alignment: .leading)
                    Text("类型").frame(width: 70, alignment: .leading)
                    Text("延迟").frame(width: 60, alignment: .trailing)
                    Text("状态").frame(width: 50, alignment: .center)
                }
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary)

                // Rows
                ForEach(result.devices.sorted { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) { device in
                    HStack(spacing: 8) {
                        Text(device.ipAddress)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 120, alignment: .leading)

                        Text(device.macAddress ?? "--")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 140, alignment: .leading)

                        Text(device.vendor ?? "--")
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: device.deviceType.icon)
                                .font(.caption2)
                            Text(device.deviceType.rawValue)
                                .font(.caption)
                        }
                        .frame(width: 70, alignment: .leading)

                        latencyView(device.latencyMs)
                            .frame(width: 60, alignment: .trailing)

                        Circle()
                            .fill(device.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .frame(width: 50)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(device.isGateway ? Color.orange.opacity(0.08) : .clear)

                    Divider()
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    func latencyView(_ latency: Double?) -> some View {
        guard let ms = latency else {
            return AnyView(Text("--").font(.caption).foregroundColor(.secondary))
        }
        let color: Color = ms < 5 ? .green : ms < 15 ? .mint : ms < 50 ? .yellow : ms < 100 ? .orange : .red
        return AnyView(
            Text(String(format: "%.1fms", ms))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
        )
    }

    // MARK: - Tips

    var tipsSection: some View {
        Group {
            if !scanner.healthTips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("诊断建议", systemImage: "lightbulb")
                        .font(.headline)
                    ForEach(scanner.healthTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).padding(.top, 6)
                            Text(tip).font(.callout)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Export

    var exportSection: some View {
        HStack {
            Button(action: { showSavePanel = true }) {
                Label("导出 PDF 报告", systemImage: "doc.richtext")
            }
            .buttonStyle(.bordered)

            Text("报告内含 \"Generated by NetDiagnose\" 标识")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Bottom (email + CTA)

    var bottomSection: some View {
        VStack(spacing: 12) {
            Divider()

            if scanner.healthScore < 80 {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("网络评分 \(scanner.healthScore)/100 · 想提升？")
                            .font(.subheadline.bold())
                        Text("用 NetTopo 深度分析网络拓扑，找出问题根源")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("了解更多") {
                        NSWorkspace.shared.open(URL(string: "https://nettopo.app")!)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Text("遇到问题或有建议？")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("去 GitHub 反馈") {
                    if let url = URL(string: "https://github.com/wordwu/NetDiagnose/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - PDF Content

    func generatePDFContent() -> String {
        guard let result = scanner.scanResult else { return "" }

        var html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body{font-family:-apple-system;padding:40px;color:#1a1a1a}
          h1{color:#007AFF;margin-bottom:4px}
          .meta{color:#666;font-size:12px;margin-bottom:24px}
          .score-box{background:#f0f6ff;border-radius:12px;padding:20px;margin-bottom:20px}
          .score{font-size:48px;font-weight:bold;color:#007AFF}
          table{width:100%;border-collapse:collapse;margin-bottom:20px}
          th{background:#f5f5f7;text-align:left;padding:8px 12px;font-size:12px;color:#666}
          td{padding:6px 12px;font-size:12px;border-bottom:1px solid #eee;font-family:monospace}
          .tip{padding:6px 0;color:#e67e22}
          .footer{text-align:center;margin-top:40px;padding-top:20px;border-top:1px solid #eee}
          .watermark{color:#007AFF;font-size:11px;opacity:0.6}
        </style></head><body>

        <h1>NetDiagnose — 网络健康诊断报告</h1>
        <p class="meta">生成时间：\(Date().formatted()) · 扫描耗时 \(String(format: "%.1f", result.scanDuration)) 秒</p>

        <div class="score-box">
          <p style="margin:0;color:#666">网络健康评分</p>
          <p class="score" style="margin:8px 0">\(result.healthScore)/100</p>
          <p style="margin:0;color:#666">子网 \(result.config.cidrNotation) · 接口 \(result.config.interfaceName) · \(result.onlineCount) 在线 / \(result.devices.count) 共</p>
        </div>

        <h2>设备清单</h2>
        <table>
          <tr><th>IP 地址</th><th>MAC 地址</th><th>厂商</th><th>类型</th><th>延迟</th><th>在线</th></tr>
        """

        for d in result.devices.sorted(by: { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) {
            let latStr = d.latencyMs.map { String(format: "%.1f ms", $0) } ?? "--"
            let online = d.isOnline ? "✓" : "✗"
            html += "<tr><td>\(d.ipAddress)</td><td>\(d.macAddress ?? "--")</td><td>\(d.vendor ?? "--")</td><td>\(d.deviceType.rawValue)</td><td>\(latStr)</td><td>\(online)</td></tr>"
        }
        html += "</table>"

        if !scanner.healthTips.isEmpty {
            html += "<h2>诊断建议</h2>"
            for t in scanner.healthTips {
                html += "<p class='tip'>• \(t)</p>"
            }
        }

        html += """
        <div class="footer">
          <p class="watermark">Generated by NetDiagnose — 免费网络健康诊断工具</p>
          <p style="font-size:10px;color:#999">NetTopo · 网络拓扑可视化专家 · nettopo.app</p>
        </div>
        </body></html>
        """
        return html
    }
}

// MARK: - PDF Document for fileExporter

struct PDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var content: String

    init(content: String) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try WebViewPDFRenderer.render(html: content)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - WebView PDF renderer

enum WebViewPDFRenderer {
    /// 在主线程用 WKWebView 渲染 HTML → PDF（支持多页，不阻塞 UI）
    static func render(html: String) throws -> Data {
        if Thread.isMainThread {
            return try Renderer().render(html: html)
        }
        return try DispatchQueue.main.sync {
            try Renderer().render(html: html)
        }
    }

    private final class Renderer: NSObject, WKNavigationDelegate {
        private let webView = WKWebView()
        private let loadSemaphore = DispatchSemaphore(value: 0)
        private let pdfSemaphore = DispatchSemaphore(value: 0)
        private var pdfData = Data()
        private var loadFailed = false

        func render(html: String) throws -> Data {
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: nil)

            // 等待页面加载完成（最长 10 秒）
            _ = loadSemaphore.wait(timeout: .now() + 10)
            guard !loadFailed else {
                throw ExportError.pageLoadFailed
            }

            // rect 默认 null → 输出整个内容（多页）
            webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let data): self.pdfData = data
                case .failure: self.loadFailed = true
                }
                self.pdfSemaphore.signal()
            }
            _ = pdfSemaphore.wait(timeout: .now() + 10)

            guard !pdfData.isEmpty else {
                throw ExportError.renderFailed
            }
            return pdfData
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadSemaphore.signal()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadFailed = true
            loadSemaphore.signal()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadFailed = true
            loadSemaphore.signal()
        }
    }

    enum ExportError: LocalizedError {
        case pageLoadFailed
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .pageLoadFailed: return "报告页面加载失败"
            case .renderFailed: return "PDF 生成失败"
            }
        }
    }
}

// MARK: - Date helper

extension Date {
    var ISO8601Short: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: self)
    }
}
