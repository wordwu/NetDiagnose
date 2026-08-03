import SwiftUI
import AppKit
import WebKit

// MARK: - Dynamic HTML Topology (replaces old TopologyCanvas)

struct TopologyHTMLView: NSViewRepresentable {
    let devices: [NetworkDevice]
    let config: ScanConfig
    @Binding var selectedDevice: NetworkDevice?

    init(devices: [NetworkDevice], config: ScanConfig, selectedDevice: Binding<NetworkDevice?>) {
        self.devices = devices
        self.config = config
        self._selectedDevice = selectedDevice
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "deviceClick")
        config.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.configuration.suppressesIncrementalRendering = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML()
        webView.loadHTMLString(html, baseURL: nil)
    }

    // ── Grouping ──

    func classify(_ d: NetworkDevice) -> String {
        if d.isGateway { return "router" }
        let vendor = (d.vendor ?? "").lowercased()
        let hostname = (d.hostname ?? "").lowercased()
        let type = d.deviceType
        if type == .nas { return "nas" }
        if type == .computer || type == .phone || type == .tablet || d.isLocalDevice { return "compute" }
        // Smart home heuristics
        let smartKeywords = ["xiaomi", "yeelight", "viomi", "aqara", "mi home", "yeelink", "chuangmi", "lumi"]
        for kw in smartKeywords { if vendor.contains(kw) || hostname.contains(kw) { return "smarthome" } }
        if type == .iot || type == .camera { return "smarthome" }
        return "other"
    }

    var router: NetworkDevice? { devices.first { $0.isGateway } }

    func htmlTextEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    func htmlAttrEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    func jsStringEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
         .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Legacy alias: basic HTML text escape (for backward compat in SVG text nodes)
    func htmlEscape(_ s: String) -> String { htmlTextEscape(s) }

    // ── HTML Generator ──

    func generateHTML() -> String {
        let groups = Dictionary(grouping: devices.filter { !$0.isGateway }, by: classify)
        let compute = groups["compute"] ?? []
        let smarthome = groups["smarthome"] ?? []
        let nas = groups["nas"] ?? []
        let other = groups["other"] ?? []

        let onlineCount = devices.filter({ $0.isOnline }).count
        let now = Date()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"

        let gw = router
        let gwIP = gw?.ipAddress ?? config.gatewayIP
        let gwMAC = gw?.macAddress ?? "--"
        let gwVendor = gw?.vendor ?? "路由器"
        let gwHostname = gw?.hostname ?? config.gatewayIP

        func hostnameOrNil(_ d: NetworkDevice) -> String? {
            guard let h = d.hostname, !h.isEmpty, h != d.ipAddress else { return nil }
            return h
        }

        // Calculate dynamic SVG height
        let secTop = 165
        let localCardH = localDevice != nil ? 75 : 0
        let computeNonLocal = compute.filter { !$0.isLocalDevice }
        let compBoxH = localCardH + computeNonLocal.count * 75 + 30
        let smH = max(60, smarthome.count * 75 + 35)
        let nasY = secTop + max(compBoxH, smH) + 15
        let nasBoxH = nas.isEmpty ? 0 : nas.count * 75 + 35
        let otherY = nasY + nasBoxH + (nasBoxH > 0 ? 15 : 0)
        let otherBoxH = other.isEmpty ? 0 : other.count * 72 + 35
        let totalHeight = otherY + otherBoxH + 40
        let svgHeight = max(400, totalHeight)

        // ── SVG generation ──
        // Layout: Internet cloud top-left → Router center-top
        //          Computing (left)  |  Smart home (right)
        //          NAS (left-below)  |
        //          Unknown (bottom wide)
        // Total SVG: ~1000x760

        func devCard(_ d: NetworkDevice, _ x: Int, _ y: Int, _ color: String, _ emoji: String, _ label: String) -> String {
            let isOnline = d.isOnline
            let mac = d.macAddress ?? "--"
            let vendor = d.vendor ?? ""
            let host = hostnameOrNil(d)
            let latStr = d.latencyMs.map { String(format: "%.1f ms", $0) } ?? "--"
            let status = isOnline ? "✅ 在线" : "⬜ 离线"
            let statusColor = isOnline ? "#22d3ee" : "#64748b"
            let macShort = mac.count > 17 ? String(mac.prefix(17)) : mac

            // Identification source
            var idSource = ""
            if d.isGateway { idSource = "识别: 网关IP + ARP" }
            else if let v = d.vendor, !v.isEmpty { idSource = "识别: OUI(\(htmlEscape(v)))" }
            else if let h = host { idSource = "识别: ARP(\(htmlEscape(h)))" }
            else if !d.openPorts.isEmpty { idSource = "识别: 端口(\(d.openPorts.map{String($0)}.joined(separator:",")))" }

            let idLine = idSource.isEmpty ? "" : "<text x=\"\(x+15)\" y=\"\(y+68)\" fill=\"#6366f1\" font-size=\"7\">\(idSource)</text>"

            var lines = ""
            lines += "<rect x=\"\(x)\" y=\"\(y)\" width=\"290\" height=\"70\" rx=\"6\" fill=\"rgba(8,51,68,0.15)\" stroke=\"\(color)\" stroke-width=\"1.2\" class=\"device-card\" onclick=\"deviceClicked('\(jsStringEscape(d.ipAddress))')\"/>"
            lines += "<text x=\"\(x+15)\" y=\"\(y+22)\" fill=\"\(color)\" font-size=\"10\" font-weight=\"600\" style=\"pointer-events:none\">\(emoji) \(htmlEscape(label))</text>"
            lines += "<text x=\"\(x+15)\" y=\"\(y+38)\" fill=\"white\" font-size=\"9\" style=\"pointer-events:none\">\(htmlEscape(d.ipAddress))</text>"
            if let h = host {
                lines += "<text x=\"\(x+15)\" y=\"\(y+52)\" fill=\"#94a3b8\" font-size=\"8\" style=\"pointer-events:none\">\(htmlEscape(h)) · MAC: \(macShort)</text>"
            } else {
                lines += "<text x=\"\(x+15)\" y=\"\(y+52)\" fill=\"#94a3b8\" font-size=\"8\" style=\"pointer-events:none\">MAC: \(macShort)\(vendor.isEmpty ? "" : " · \(htmlEscape(vendor))")</text>"
            }
            lines += "<text x=\"\(x+15)\" y=\"\(y+64)\" fill=\"\(statusColor)\" font-size=\"7\" style=\"pointer-events:none\">\(status) · 延迟 \(latStr)</text>"
            lines += idLine
            return lines
        }

        var svg = ""
        svg += "<svg viewBox=\"0 0 1000 \(svgHeight)\">"
        svg += "<defs>"
        svg += "<marker id=\"arr\" markerWidth=\"8\" markerHeight=\"6\" refX=\"7\" refY=\"3\" orient=\"auto\"><polygon points=\"0 0, 8 3, 0 6\" fill=\"#64748b\"/></marker>"
        svg += "<marker id=\"arr-cyan\" markerWidth=\"8\" markerHeight=\"6\" refX=\"7\" refY=\"3\" orient=\"auto\"><polygon points=\"0 0, 8 3, 0 6\" fill=\"#22d3ee\"/></marker>"
        svg += "<marker id=\"arr-emerald\" markerWidth=\"8\" markerHeight=\"6\" refX=\"7\" refY=\"3\" orient=\"auto\"><polygon points=\"0 0, 8 3, 0 6\" fill=\"#34d399\"/></marker>"
        svg += "<marker id=\"arr-violet\" markerWidth=\"8\" markerHeight=\"6\" refX=\"7\" refY=\"3\" orient=\"auto\"><polygon points=\"0 0, 8 3, 0 6\" fill=\"#a78bfa\"/></marker>"
        svg += "<marker id=\"arr-rose\" markerWidth=\"8\" markerHeight=\"6\" refX=\"7\" refY=\"3\" orient=\"auto\"><polygon points=\"0 0, 8 3, 0 6\" fill=\"#fb7185\"/></marker>"
        svg += "<pattern id=\"grid\" width=\"40\" height=\"40\" patternUnits=\"userSpaceOnUse\"><path d=\"M 40 0 L 0 0 0 40\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"0.5\"/></pattern>"
        svg += "</defs>"
        svg += "<rect width=\"100%\" height=\"100%\" fill=\"url(#grid)\"/>"

        // Router Y center
        let ry = 60

        // ── Internet cloud ──
        svg += "<rect x=\"25\" y=\"\(ry-25)\" width=\"130\" height=\"60\" rx=\"10\" fill=\"rgba(30,41,59,0.6)\" stroke=\"#94a3b8\" stroke-width=\"1.2\"/>"
        svg += "<text x=\"90\" y=\"\(ry+5)\" fill=\"#94a3b8\" font-size=\"10\" font-weight=\"600\" text-anchor=\"middle\">🌐 INTERNET</text>"
        svg += "<text x=\"90\" y=\"\(ry+20)\" fill=\"#64748b\" font-size=\"8\" text-anchor=\"middle\">WAN / 光猫</text>"

        // ── Router ──
        let rw = 460, rx = 180
        svg += "<rect x=\"\(rx)\" y=\"\(ry-25)\" width=\"\(rw)\" height=\"58\" rx=\"10\" fill=\"rgba(120,53,15,0.12)\" stroke=\"#fbbf24\" stroke-width=\"1.5\" class=\"device-card\" onclick=\"deviceClicked('\(jsStringEscape(gwIP))')\"/>"
        svg += "<text x=\"\(rx+rw/2)\" y=\"\(ry+1)\" fill=\"#fbbf24\" font-size=\"11\" font-weight=\"700\" text-anchor=\"middle\" style=\"pointer-events:none\">\(htmlEscape(gwHostname)) · \(gwIP)</text>"
        svg += "<text x=\"\(rx+rw/2)\" y=\"\(ry+17)\" fill=\"white\" font-size=\"9\" text-anchor=\"middle\" style=\"pointer-events:none\">网关 / DHCP / DNS</text>"
        svg += "<text x=\"\(rx+rw/2)\" y=\"\(ry+30)\" fill=\"#94a3b8\" font-size=\"8\" text-anchor=\"middle\" style=\"pointer-events:none\">\(gwVendor) · MAC: \(gwMAC)</text>"

        // WAN → Router line
        svg += "<line x1=\"155\" y1=\"\(ry+5)\" x2=\"\(rx)\" y2=\"\(ry+4)\" stroke=\"#64748b\" stroke-width=\"1.5\" marker-end=\"url(#arr)\"/>"

        // ── WiFi indicator ──
        svg += "<ellipse cx=\"\(rx+rw/2)\" cy=\"125\" rx=\"260\" ry=\"22\" fill=\"rgba(34,211,238,0.03)\" stroke=\"#22d3ee\" stroke-width=\"0.8\" stroke-dasharray=\"6,4\"/>"
        svg += "<text x=\"\(rx+rw/2)\" y=\"129\" fill=\"#22d3ee\" font-size=\"8\" text-anchor=\"middle\">📶 WiFi 2.4GHz + 5GHz</text>"

        // ── Layout sections ──
        let leftX = 35, rightX = 540

        // Helper: draw a section box
        func sectionBox(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: String, _ title: String) -> String {
            return """
            <rect x="\(x)" y="\(y)" width="\(w)" height="\(h)" rx="10" fill="none" stroke="\(color)" stroke-width="1" stroke-dasharray="8,4" opacity="0.6"/>
            <text x="\(x+12)" y="\(y+18)" fill="\(color)" font-size="9" font-weight="600">\(title)</text>
            """
        }

        // ── Local device (this Mac) highlight ──
        if let local = devices.first(where: { $0.isLocalDevice }) {
            svg += "<rect x=\"\(leftX+10)\" y=\"\(secTop+5)\" width=\"290\" height=\"62\" rx=\"6\" fill=\"rgba(8,51,68,0.35)\" stroke=\"#22d3ee\" stroke-width=\"1.8\" class=\"device-card\" onclick=\"deviceClicked('\(jsStringEscape(local.ipAddress))')\"/>"
            svg += "<text x=\"\(leftX+25)\" y=\"\(secTop+25)\" fill=\"#22d3ee\" font-size=\"10\" font-weight=\"700\" style=\"pointer-events:none\">🖥️ \(htmlEscape(hostnameOrNil(local) ?? local.ipAddress)) · 本机</text>"
            svg += "<text x=\"\(leftX+25)\" y=\"\(secTop+40)\" fill=\"white\" font-size=\"9\" style=\"pointer-events:none\">\(htmlEscape(local.ipAddress))</text>"
            svg += "<text x=\"\(leftX+25)\" y=\"\(secTop+54)\" fill=\"#94a3b8\" font-size=\"8\" style=\"pointer-events:none\">macOS · MAC: \(local.macAddress ?? "--") · ✅ 在线</text>"
        }

        // ── Compute section ──
        svg += sectionBox(leftX, secTop, 310, compBoxH, "#22d3ee", "计算设备")
        for (i, d) in computeNonLocal.enumerated() {
            let y = secTop + 28 + (localDevice != nil ? 75 : 0) + i * 75
            svg += devCard(d, leftX+10, y, "#22d3ee", d.deviceType == .phone ? "📱" : "💻", hostnameOrNil(d) ?? d.deviceType.rawValue)
        }

        // ── Smart home section ──
        svg += sectionBox(rightX, secTop, 310, smH, "#34d399", "智能家居 · IoT")
        for (i, d) in smarthome.enumerated() {
            svg += devCard(d, rightX+10, secTop+28+i*75, "#34d399", "🏠", hostnameOrNil(d) ?? d.deviceType.rawValue)
        }

        // ── NAS section ──
        if !nas.isEmpty {
            svg += sectionBox(leftX, nasY, 310, nasBoxH, "#a78bfa", "存储 / NAS")
            for (i, d) in nas.enumerated() {
                svg += devCard(d, leftX+10, nasY+28+i*75, "#a78bfa", "🗄️", hostnameOrNil(d) ?? d.deviceType.rawValue)
            }
        }

        // ── Other / Unknown section ──
        if !other.isEmpty {
            let otherBoxW = 625
            let otherX = (1000 - otherBoxW) / 2
            svg += sectionBox(otherX, otherY, otherBoxW, otherBoxH, "#fb7185", "未识别 / 其他设备")
            for (i, d) in other.enumerated() {
                svg += devCard(d, otherX+10, otherY+28+i*72, "#fb7185", "❓", hostnameOrNil(d) ?? d.deviceType.rawValue)
            }
        }

        // ── Connection lines: Router → each device ──
        let rCenterX = rx + rw/2
        let rBottomY = ry + 35

        struct DevPos { let x: Int; let y: Int }
        var conns: [(Int, Int, String)] = []

        func addConns(_ devs: [NetworkDevice], _ cardX: Int, _ startY: Int, _ color: String) {
            for (i, _) in devs.enumerated() {
                let cx = cardX + 155
                let cy = startY + i * 75 + 35
                conns.append((cx, cy, color))
            }
        }

        if localDevice != nil { conns.append((leftX+155, secTop+35, "#22d3ee")) }
        addConns(computeNonLocal, leftX+10, secTop+28+(localDevice != nil ? 75 : 0), "#22d3ee")
        addConns(smarthome, rightX+10, secTop+28, "#34d399")
        if !nas.isEmpty { addConns(nas, leftX+10, nasY+28, "#a78bfa") }
        if !other.isEmpty {
            let oX = (1000 - 625) / 2 + 10
            for (i, _) in other.enumerated() {
                conns.append((oX + 155, otherY + 28 + i * 72 + 35, "#fb7185"))
            }
        }

        for (cx, cy, color) in conns {
            let marker = color == "#22d3ee" ? "url(#arr-cyan)" : color == "#34d399" ? "url(#arr-emerald)" : color == "#a78bfa" ? "url(#arr-violet)" : color == "#fb7185" ? "url(#arr-rose)" : "url(#arr)"
            svg += "<line x1=\"\(rCenterX)\" y1=\"\(rBottomY)\" x2=\"\(cx)\" y2=\"\(cy-30)\" stroke=\"\(color)\" stroke-width=\"0.8\" stroke-dasharray=\"4,3\" marker-end=\"\(marker)\" opacity=\"0.6\"/>"
        }

        // ── Legend ──
        svg += "<rect x=\"870\" y=\"165\" width=\"115\" height=\"155\" rx=\"6\" fill=\"rgba(15,23,42,0.85)\" stroke=\"#1e293b\" stroke-width=\"0.8\"/>"
        svg += "<text x=\"927\" y=\"183\" fill=\"white\" font-size=\"9\" font-weight=\"600\" text-anchor=\"middle\">图例</text>"
        let legendItems: [(String, String)] = [
            ("#fbbf24", "路由器/网关"), ("#22d3ee", "计算设备"), ("#34d399", "智能家居"),
            ("#a78bfa", "NAS/存储"), ("#fb7185", "未识别设备"), ("#94a3b8", "外部/WAN")
        ]
        for (i, (color, label)) in legendItems.enumerated() {
            let ly = 196 + i * 18
            svg += "<rect x=\"882\" y=\"\(ly)\" width=\"12\" height=\"8\" rx=\"2\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"1\"/>"
            svg += "<text x=\"900\" y=\"\(ly+7)\" fill=\"#94a3b8\" font-size=\"7\">\(label)</text>"
        }
        svg += "<line x1=\"882\" y1=\"298\" x2=\"894\" y2=\"298\" stroke=\"#64748b\" stroke-width=\"0.8\" stroke-dasharray=\"3,3\"/>"
        svg += "<text x=\"900\" y=\"301\" fill=\"#94a3b8\" font-size=\"7\">WiFi 连接</text>"

        svg += "</svg>"

        // ── Full page HTML with click handler ──
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          *{margin:0;padding:0;box-sizing:border-box}
          body{font-family:'JetBrains Mono','SF Mono',monospace;background:#020617;color:white;padding:1rem}
          .header{margin-bottom:1rem}
          .header-row{display:flex;align-items:center;gap:0.5rem;margin-bottom:0.25rem}
          .pulse-dot{width:10px;height:10px;background:#22d3ee;border-radius:50%;animation:pulse 2s infinite}
          @keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
          h1{font-size:1.2rem;font-weight:700}
          .subtitle{color:#94a3b8;font-size:0.75rem;margin-left:1.25rem}
          .diagram-container{background:rgba(15,23,42,0.4);border-radius:0.75rem;border:1px solid #1e293b;padding:1rem;overflow:auto}
          svg{width:100%;min-width:900px;display:block}
          .footer{text-align:center;margin-top:1rem;color:#475569;font-size:0.65rem}
          rect.device-card{cursor:pointer;transition:filter 0.15s}
          rect.device-card:hover{filter:brightness(1.4)}
        </style>
        <script>
        function deviceClicked(ip) {
            window.webkit.messageHandlers.deviceClick.postMessage(ip);
        }
        </script></head><body>
        <div class="header">
          <div class="header-row">
            <div class="pulse-dot"></div>
            <h1>网络拓扑</h1>
          </div>
          <p class="subtitle">\(htmlEscape(config.cidrNotation)) · 在线 \(onlineCount) / \(devices.count) 台 · \(df.string(from: now))</p>
        </div>
        <div class="diagram-container">
          \(svg)
        </div>
        <p class="footer">扫描方式: ARP + ICMP Ping + SSDP/UPnP + TCP 端口 · NetDiagnose</p>
        </body></html>
        """
    }

    // Helper to know if there's a local device
    var localDevice: NetworkDevice? { devices.first { $0.isLocalDevice } }

    // MARK: - Coordinator for JavaScript bridge
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: TopologyHTMLView

        init(parent: TopologyHTMLView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "deviceClick",
                  let ip = message.body as? String else { return }
            if let device = parent.devices.first(where: { $0.ipAddress == ip }) {
                DispatchQueue.main.async {
                    self.parent.selectedDevice = device
                }
            }
        }
    }
}
