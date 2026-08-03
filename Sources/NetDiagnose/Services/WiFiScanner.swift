import Foundation

/// WiFi scanner via system_profiler. SSID is redacted on macOS 14+ but channel/band/security
/// data from neighbor networks enables congestion analysis.
struct WiFiScanner {

    struct WiFiNetwork: Identifiable {
        var id = UUID()
        let ssid: String
        let bssid: String
        let channel: Int
        let band: String
        let rssi: Int
        let security: String
        let phyMode: String
        let isCurrent: Bool
    }

    struct ChannelCongestion: Identifiable {
        var id: String { "\(band)-\(channel)" }
        let channel: Int
        let band: String
        let networkCount: Int
        let recommendation: String
    }

    static func scanNearbyNetworks(interface: String = "en1") -> [WiFiNetwork] {
        // Try airport (older macOS)
        if let r = tryAirport() { return r }
        return trySystemProfiler()
    }

    private static func tryAirport() -> [WiFiNetwork]? {
        let paths = ["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "/usr/sbin/airport"]
        guard let p = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        let result = NetworkScanner.runProcess(p, args: ["-s"], timeout: 8)
        guard result.status == 0 else { return nil }
        return parseAirportOutput(result.output)
    }

    private static func parseAirportOutput(_ out: String) -> [WiFiNetwork] {
        var nets = [WiFiNetwork](); var skip = false
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if !skip && (trimmed.hasPrefix("SSID") || trimmed.contains("BSSID")) { skip = true; continue }
            guard skip else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 4 else { continue }
            var ssid = "", bssid = "", rssi = 0, ch = 0, sec = ""
            for (i, p) in parts.enumerated() {
                if p.range(of: #"^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$"#, options: .regularExpression) != nil {
                    ssid = parts[0..<i].joined(separator: " ")
                    bssid = p
                    if i+1 < parts.count { rssi = Int(parts[i+1]) ?? 0 }
                    if i+2 < parts.count { ch = Int(parts[i+2]) ?? 0 }
                    if parts.count > i+5 { sec = parts[i+5] }
                    nets.append(WiFiNetwork(ssid: ssid, bssid: bssid, channel: ch, band: ch <= 14 ? "2.4GHz" : "5GHz", rssi: rssi, security: sec, phyMode: "", isCurrent: false))
                    break
                }
            }
        }
        return nets
    }

    private static func trySystemProfiler() -> [WiFiNetwork] {
        let result = NetworkScanner.runProcess("/usr/sbin/system_profiler", args: ["SPAirPortDataType"], timeout: 12)
        guard result.status != -1 else { return [] }
        return parseSystemProfiler(result.output)
    }

    private static func parseSystemProfiler(_ out: String) -> [WiFiNetwork] {
        var nets = [WiFiNetwork]()
        let lines = out.components(separatedBy: "\n")
        var inOtherNetworks = false
        var currentCh = 0, currentRSSI = -50, currentSec = "WPA2", currentPHY = ""

        // Parse current network info first
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "Current Network Information:" {
                for j in (i+1)..<min(i+15, lines.count) {
                    let l = lines[j].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("PHY Mode:") { currentPHY = l.replacingOccurrences(of: "PHY Mode:", with: "").trimmingCharacters(in: .whitespaces) }
                    if l.hasPrefix("Channel:") {
                        let chStr = l.replacingOccurrences(of: "Channel:", with: "").trimmingCharacters(in: .whitespaces)
                        currentCh = Int(chStr.components(separatedBy: " ").first ?? "0") ?? 0
                    }
                    if l.hasPrefix("Security:") { currentSec = l.replacingOccurrences(of: "Security:", with: "").trimmingCharacters(in: .whitespaces) }
                    if l.hasPrefix("Signal / Noise:") {
                        let parts = l.replacingOccurrences(of: "Signal / Noise:", with: "").trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                        if let v = Int(parts.first ?? "") { currentRSSI = v }
                    }
                }
            }
        }

        // Add current network
        if currentCh > 0 {
            nets.append(WiFiNetwork(ssid: "当前连接", bssid: "", channel: currentCh,
                band: currentCh <= 14 ? "2.4GHz" : "5GHz", rssi: currentRSSI,
                security: currentSec, phyMode: currentPHY, isCurrent: true))
        }

        // Parse other local wireless networks
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Other Local Wi") { inOtherNetworks = true; continue }
            guard inOtherNetworks else { continue }
            if t.isEmpty { continue }

            if t.hasPrefix("<redacted>:") || t.hasPrefix("PHY Mode:") {
                // If we were tracking a previous network and hit a new one, save the previous
                if currentCh > 0 && (t.hasPrefix("<redacted>:") || t.hasPrefix("PHY Mode:")) {
                    let band = currentCh <= 14 ? "2.4GHz" : "5GHz"
                    nets.append(WiFiNetwork(ssid: "邻近网络 #\(nets.count)", bssid: "",
                        channel: currentCh, band: band, rssi: currentRSSI,
                        security: currentSec, phyMode: currentPHY, isCurrent: false))
                    // Reset for next network
                    currentPHY = ""; currentCh = 0; currentSec = "WPA2"; currentRSSI = -50
                }
                if t.hasPrefix("PHY Mode:") {
                    currentPHY = t.replacingOccurrences(of: "PHY Mode:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
            if t.hasPrefix("Channel:") {
                let chStr = t.replacingOccurrences(of: "Channel:", with: "").trimmingCharacters(in: .whitespaces)
                currentCh = Int(chStr.components(separatedBy: " ").first ?? "0") ?? 0
            }
            if t.hasPrefix("Security:") { currentSec = t.replacingOccurrences(of: "Security:", with: "").trimmingCharacters(in: .whitespaces) }
            if t.hasPrefix("Signal / Noise:") {
                let parts = t.replacingOccurrences(of: "Signal / Noise:", with: "").trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                if let v = Int(parts.first ?? "") { currentRSSI = v }
            }
        }

        return nets
    }

    static func analyzeCongestion(_ networks: [WiFiNetwork]) -> [ChannelCongestion] {
        var counts = [String: (Int, String, Int)]()
        for n in networks {
            let k = "\(n.band):\(n.channel)"
            let prev = counts[k]
            counts[k] = (n.channel, n.band, (prev?.2 ?? 0) + 1)
        }
        return counts.values.map { c in
            let rec: String
            if c.1 == "2.4GHz" {
                if c.2 > 8 { rec = "严重拥塞" }
                else if c.2 > 4 { rec = "中度拥挤" }
                else { rec = "良好" }
            } else {
                if c.2 > 4 { rec = "较拥挤" }
                else { rec = "通畅" }
            }
            return ChannelCongestion(channel: c.0, band: c.1, networkCount: c.2, recommendation: rec)
        }.sorted { $0.networkCount > $1.networkCount }
    }
}
