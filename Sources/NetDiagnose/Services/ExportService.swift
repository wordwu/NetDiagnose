import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case html = "HTML"
    case markdown = "Markdown"
    var id: String { rawValue }
}

// WKWebView wrapper that waits for HTML to finish loading before PDF generation
class PDFWebView: NSView, WKNavigationDelegate {
    private let webView = WKWebView()
    var onReady: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        webView.frame = bounds
        webView.navigationDelegate = self
        addSubview(webView)
    }

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadHTML(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
        onReady = nil
    }

    func generatePDF(to url: URL) {
        let config = WKPDFConfiguration()
        // rect 保持默认（null）→ 输出整个内容，长报告自动多页，不会截断
        webView.createPDF(configuration: config) { result in
            if case .success(let data) = result {
                try? data.write(to: url)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onReady = nil
    }
}

class ExportService {
    static func generateHTML(devices: [NetworkDevice], config: ScanConfig, findings: [DiagnosticFinding], score: Int, notes: [DeviceNote]) -> String {
        let onlineCount = devices.filter(\.isOnline).count
        let noteMap = Dictionary(uniqueKeysWithValues: notes.map { ($0.ip, $0) })

        var html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body{font-family:-apple-system,sans-serif;padding:40px;color:#1a1a1a;max-width:800px;margin:0 auto}
          h1{color:#007AFF;margin-bottom:4px}
          .meta{color:#666;font-size:12px;margin-bottom:24px}
          .score-box{background:#f0f6ff;border-radius:12px;padding:20px;margin-bottom:20px}
          .score{font-size:48px;font-weight:bold;color:#007AFF}
          .finding{padding:10px 14px;margin:6px 0;border-radius:8px;font-size:13px}
          .finding.critical{background:#fff0f0;border-left:4px solid #e74c3c}
          .finding.warning{background:#fff8e1;border-left:4px solid #f39c12}
          .finding.info{background:#f0f6ff;border-left:4px solid #3498db}
          .finding.good{background:#e8f5e9;border-left:4px solid #27ae60}
          table{width:100%;border-collapse:collapse;margin:20px 0}
          th{background:#f5f5f7;text-align:left;padding:8px 12px;font-size:12px;color:#666}
          td{padding:6px 12px;font-size:12px;border-bottom:1px solid #eee;font-family:monospace}
          .note-tag{background:#e8f5e9;color:#2e7d32;padding:2px 8px;border-radius:10px;font-size:10px}
          .footer{text-align:center;margin-top:40px;padding-top:20px;border-top:1px solid #eee}
          .watermark{color:#007AFF;font-size:11px;opacity:0.6}
        </style></head><body>
        <h1>NetDiagnose — 网络健康诊断报告</h1>
        <p class="meta">子网 \(config.cidrNotation) · 接口 \(config.interfaceName) · 网关 \(config.gatewayIP) · 掩码 \(config.netmask) · \(Date().formatted()) · \(onlineCount)/\(devices.count) 在线</p>
        <div class="score-box"><p style="margin:0;color:#666">网络健康评分</p>
        <p class="score" style="margin:8px 0">\(score)/100</p>
        <p style="margin:0;color:#666">P90 延迟: \(p90Text(devices)) · 在线率 \(onlineCount)/\(devices.count)</p></div>
        """

        if !findings.isEmpty {
            html += "<h2>诊断结果</h2>"
            for f in findings {
                html += "<div class=\"finding \(f.severity == .critical ? "critical" : f.severity == .warning ? "warning" : f.severity == .info ? "info" : "good")\">"
                html += "<strong>\(f.title)</strong><br>\(f.explanation)"
                if !f.action.isEmpty { html += "<br><em>建议: \(f.action)</em>" }
                html += "</div>"
            }
        }

        html += "<h2>设备清单</h2><table><tr><th>IP</th><th>MAC</th><th>厂商</th><th>类型</th><th>延迟</th><th>状态</th><th>风险</th><th>备注</th></tr>"
        for d in devices.sorted(by: { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) {
            let lat = d.latencyMs.map { String(format: "%.1f ms", $0) } ?? "--"
            let note = noteMap[d.ipAddress]
            let noteText = note?.label ?? note?.memo ?? ""
            let risk = d.riskLevel == .high ? "<span style=\"color:#e74c3c;font-weight:600\">高</span>"
                : d.riskLevel == .medium ? "<span style=\"color:#f39c12;font-weight:600\">中</span>" : "低"
            let lowConf = d.identificationConfidence == .low && d.deviceType != .unknown ? " ⚠️" : ""
            let status = d.isOnline ? "✓" : (d.isStealth ? "隐身" : "✗")
            html += "<tr><td>\(d.ipAddress)</td><td>\(d.macAddress ?? "--")</td><td>\(d.vendor ?? "--")</td><td>\(d.deviceType.rawValue)\(lowConf)</td><td>\(lat)</td><td>\(status)</td><td>\(risk)</td><td><span class=\"note-tag\">\(noteText)</span></td></tr>"
        }
        html += "</table>"

        html += """
        <div class="footer"><p class="watermark">Generated by NetDiagnose — 免费网络健康诊断工具</p>
        <p style="font-size:10px;color:#999">反馈与建议: github.com/wordwu/NetDiagnose/issues</p></div></body></html>
        """
        return html
    }

    static func generateMarkdown(devices: [NetworkDevice], config: ScanConfig, findings: [DiagnosticFinding], score: Int, notes: [DeviceNote]) -> String {
        var md = "# NetDiagnose 网络诊断报告\n\n"
        md += "**子网**: \(config.cidrNotation) · **接口**: \(config.interfaceName) · **网关**: \(config.gatewayIP) · **时间**: \(Date().formatted())\n\n"
        md += "## 健康评分: \(score)/100\n\n"
        md += "**P90 延迟**: \(p90Text(devices))\n\n"

        if !findings.isEmpty {
            md += "## 诊断结果\n\n"
            for f in findings {
                let emoji = f.severity == .critical ? "🔴" : f.severity == .warning ? "🟡" : f.severity == .info ? "🔵" : "🟢"
                md += "- \(emoji) **\(f.title)**: \(f.explanation)\n"
                if !f.action.isEmpty { md += "  - 建议: \(f.action)\n" }
            }
            md += "\n"
        }

        md += "## 设备清单\n\n"
        let noteMap = Dictionary(uniqueKeysWithValues: notes.map { ($0.ip, $0) })
        md += "| IP | MAC | 厂商 | 类型 | 延迟 | 状态 | 风险 | 备注 |\n"
        md += "|---|---|---|---|---|---|---|---|\n"
        for d in devices.sorted(by: { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) {
            let lat = d.latencyMs.map { String(format: "%.1f ms", $0) } ?? "--"
            let note = noteMap[d.ipAddress]?.label ?? ""
            let lowConf = d.identificationConfidence == .low && d.deviceType != .unknown ? " ⚠️" : ""
            let status = d.isOnline ? "✓" : (d.isStealth ? "隐身" : "✗")
            md += "| \(d.ipAddress) | \(d.macAddress ?? "--") | \(d.vendor ?? "--") | \(d.deviceType.rawValue)\(lowConf) | \(lat) | \(status) | \(d.riskLevel.rawValue) | \(note) |\n"
        }
        md += "\n---\n*Generated by NetDiagnose · 反馈: github.com/wordwu/NetDiagnose/issues*"
        return md
    }

    /// 计算 P90 延迟（90% 分位数，比平均值更抗干扰）
    static func p90Text(_ devices: [NetworkDevice]) -> String {
        let lats = devices.compactMap { $0.latencyMs }.sorted()
        guard !lats.isEmpty else { return "--" }
        let idx = Int((Double(lats.count - 1) * 0.9).rounded())
        return String(format: "%.1f ms", lats[idx])
    }


    // MARK: - CSV Export

    static func generateCSV(devices: [NetworkDevice], findings: [DiagnosticFinding], score: Int, notes: [DeviceNote]) -> String {
        var csv = "IP,MAC,Vendor,Type,Hostname,Latency(ms),Online,Risk,OpenPorts,Notes\n"
        let noteMap = Dictionary(uniqueKeysWithValues: notes.map { ($0.ip, $0) })
        for d in devices.sorted(by: { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) {
            let lat = d.latencyMs.map { String(format: "%.1f", $0) } ?? ""
            let ports = d.openPorts.sorted().map(String.init).joined(separator: ";")
            let note = noteMap[d.ipAddress]?.label.replacingOccurrences(of: ",", with: "，") ?? ""
            let hostname = (d.hostname ?? "").replacingOccurrences(of: ",", with: "，")
            csv += "\(d.ipAddress),\(d.macAddress ?? ""),\(d.vendor ?? ""),\(d.deviceType.rawValue),\(hostname),\(lat),\(d.isOnline ? "Yes" : "No"),\(d.riskLevel.rawValue),\(ports),\(note)\n"
        }

        // Append findings summary
        csv += "\nDiagnostic Findings\n"
        csv += "Severity,Title,Explanation,Action\n"
        for f in findings {
            let title = f.title.replacingOccurrences(of: ",", with: "，")
            let explanation = f.explanation.replacingOccurrences(of: ",", with: "，")
            let action = f.action.replacingOccurrences(of: ",", with: "，")
            csv += "\(f.severity.rawValue),\(title),\(explanation),\(action)\n"
        }
        return csv
    }

    // MARK: - JSON Export

    static func generateJSON(devices: [NetworkDevice], config: ScanConfig, findings: [DiagnosticFinding], score: Int, notes: [DeviceNote]) -> String {
        let onlineCount = devices.filter(\.isOnline).count
        let noteMap = Dictionary(uniqueKeysWithValues: notes.map { ($0.ip, $0) })

        struct JSONReport: Codable {
            let app: String
            let generatedAt: String
            let subnet: String
            let gateway: String
            let healthScore: Int
            let deviceCount: Int
            let onlineCount: Int
            let devices: [JSONDevice]
            let findings: [JSONFinding]
        }

        struct JSONDevice: Codable {
            let ip: String
            let mac: String?
            let vendor: String?
            let hostname: String?
            let type: String
            let openPorts: [Int]
            let isOnline: Bool
            let latencyMs: Double?
            let riskLevel: String
            let note: String?
        }

        struct JSONFinding: Codable {
            let severity: String
            let title: String
            let explanation: String
            let action: String
            let affectedIPs: [String]
        }

        let jsonDevices = devices.sorted(by: { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }).map { d in
            JSONDevice(
                ip: d.ipAddress, mac: d.macAddress, vendor: d.vendor,
                hostname: d.hostname, type: d.deviceType.rawValue,
                openPorts: d.openPorts.sorted(), isOnline: d.isOnline,
                latencyMs: d.latencyMs, riskLevel: d.riskLevel.rawValue,
                note: noteMap[d.ipAddress]?.label
            )
        }

        let jsonFindings = findings.map { f in
            JSONFinding(
                severity: f.severity.rawValue, title: f.title,
                explanation: f.explanation, action: f.action,
                affectedIPs: f.affectedIPs
            )
        }

        let report = JSONReport(
            app: "NetDiagnose",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            subnet: config.cidrNotation,
            gateway: config.gatewayIP,
            healthScore: score,
            deviceCount: devices.count,
            onlineCount: onlineCount,
            devices: jsonDevices,
            findings: jsonFindings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    // PDF save with proper WKWebView lifecycle management
    static func savePDF(html: String, defaultName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }

            // Create a window to host the WKWebView (needed for rendering)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 612, height: 792),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false

            let pdfView = PDFWebView()
            pdfView.onReady = {
                pdfView.generatePDF(to: url)
                DispatchQueue.main.async {
                    window.close()
                    completion(url)
                }
            }
            pdfView.loadHTML(html)
            window.contentView = pdfView
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func saveText(content: String, ext: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "html" ? [.html] : [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = defaultName
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
