import Foundation
import Network
import Darwin

// ---- Ping Result ----
struct PingResult {
    let ip: String
    let hostname: String?
    let latency: Double?
}

// ---- ARP Entry ----
struct ArpEntry {
    let ip: String
    let mac: String
    let interface: String
    let permanent: Bool
}

// ---- mDNS Service ----
struct BonjourService {
    let name: String
    let type: String
    let hostname: String
    let ip: String
    let port: Int
}

// ---- Local Network Info ----
struct LocalNetworkInfo {
    let subnet: String
    let localIP: String
    let gatewayIP: String
    let netmask: String
    let interfaceName: String
    let isWiFi: Bool
}

// ---- Network Scanner (macOS native, comprehensive) ----
class NetworkScanner {

    // MARK: - ARP Table

    /// Parse `arp -a` for MAC addresses
    static func arpTable() -> [ArpEntry] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        task.arguments = ["-a"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var entries = [ArpEntry]()
        for line in output.components(separatedBy: "\n") {
            // Format: "? (192.168.50.87) at e4:fe:43:5:41:b1 on en1 ifscope [ethernet]"
            // Or: "rt-ac1900p-1218 (192.168.50.1) at b0:6e:bf:57:12:18 on en1 ifscope [ethernet]"
            guard let parenStart = line.firstIndex(of: "("),
                  let parenEnd = line.firstIndex(of: ")"),
                  let atRange = line.range(of: " at "),
                  let onRange = line.range(of: " on ") else { continue }

            let hostname = String(line[..<parenStart]).trimmingCharacters(in: .whitespaces)
            let ip = String(line[line.index(after: parenStart)..<parenEnd])
            let macStr = String(line[atRange.upperBound..<onRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let ifParts = String(line[onRange.upperBound...]).components(separatedBy: .whitespaces)
            let iface = ifParts.first ?? "?"
            let permanent = line.contains("permanent")

            // Sanitize MAC
            let mac = macStr  // Keep raw for vendor lookup
            entries.append(ArpEntry(ip: ip, mac: mac, interface: iface, permanent: permanent))
        }
        return entries
    }

    // MARK: - MAC Vendor Lookup

    /// Lookup vendor from MAC OUI prefix
    static func lookupVendor(mac: String) -> String? {
        let sanitized = mac.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard sanitized.count >= 6 else { return nil }
        let oui = String(sanitized.prefix(6))
        return OUI_DB[oui]
    }

    /// Lookup all ARP entries with vendors
    static func arpWithVendors() -> [(ArpEntry, String?)] {
        return arpTable().map { ($0, lookupVendor(mac: $0.mac)) }
    }

    // MARK: - mDNS / Bonjour

    /// Discover mDNS services using `dns-sd`
    static func bonjourScan(interface: String) -> [BonjourService] {
        let serviceTypes = ["_http._tcp.", "_hap._tcp.", "_airplay._tcp.",
                           "_printer._tcp.", "_smb._tcp."]
        var all = [BonjourService]()

        for stype in serviceTypes {
            if let results = bonjourBrowse(type: stype, interface: interface) {
                all.append(contentsOf: results)
            }
        }
        return all
    }

    private static func bonjourBrowse(type: String, interface: String) -> [BonjourService]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        task.arguments = ["-B", type, "local."]
        task.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        try? task.run()
        // Give it 1.5 seconds to collect
        Thread.sleep(forTimeInterval: 1.5)
        task.terminate()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var services = [BonjourService]()

        for line in output.components(separatedBy: "\n") {
            // Skip headers
            guard !line.hasPrefix("Browsing"), !line.hasPrefix("Timestamp"), !line.hasPrefix("DATE"),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            // Format: " 4  7 add  8000  1  0  service-name _http._tcp local."
            if parts.count >= 7, parts[2] == "add" {
                let name = parts[3]
                let svcType = type

                // Resolve this service
                if let resolved = bonjourResolve(name: name, type: svcType, interface: interface) {
                    services.append(resolved)
                }
            }
        }
        return services.isEmpty ? nil : services
    }

    private static func bonjourResolve(name: String, type: String, interface: String) -> BonjourService? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        task.arguments = ["-G", "v4", "\(name).\(type)local."]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        try? task.run()
        Thread.sleep(forTimeInterval: 0.3)
        task.terminate()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var hostname = name, ip = "", port = 0

        for line in output.components(separatedBy: "\n") {
            if line.contains("can be reached at"), let hostPart = line.components(separatedBy: "can be reached at").last {
                hostname = hostPart.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".local.", with: "")
                if hostname.hasSuffix(".") { hostname = String(hostname.dropLast()) }
            }
            if line.contains("Addr:"), let addrPart = line.components(separatedBy: "Addr:").last {
                ip = addrPart.trimmingCharacters(in: .whitespaces)
            }
            if line.contains("Port:"), let portPart = line.components(separatedBy: "Port:").last {
                port = Int(portPart.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        return BonjourService(name: name, type: type, hostname: hostname, ip: ip, port: port)
    }

    // MARK: - Ping Sweep

    /// Ping sweep a /24 subnet
    static func pingSweep(subnet: String, skipIPs: Set<String> = []) -> [PingResult] {
        var results = [PingResult]()
        let queue = DispatchQueue(label: "nettopo.ping", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()

        for i in 1...254 {
            let ip = "\(subnet).\(i)"
            if skipIPs.contains(ip) { continue }
            group.enter()
            queue.async {
                if ping(ip: ip) {
                    let hostname = resolveHostname(ip: ip)
                    lock.lock()
                    results.append(PingResult(ip: ip, hostname: hostname, latency: nil))
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        return results
    }

    /// Single ping via /sbin/ping
    static func ping(ip: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-W", "1000", ip]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// ★ Measure latency (ms) to an IP via ping
    static func measureLatency(ip: String) -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-W", "1000", ip]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        try? task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Parse: "64 bytes from 192.168.1.1: icmp_seq=0 ttl=64 time=2.123 ms"
        if let range = output.range(of: "time="),
           let endRange = output[range.upperBound...].range(of: " ms") {
            let timeStr = String(output[range.upperBound..<endRange.lowerBound])
            return Double(timeStr)
        }
        return nil
    }

    // MARK: - Port Scan

    /// Extended port scan
    static func checkPorts(ip: String) -> [Int] {
        let ports: [(Int, TimeInterval)] = [
            // Web
            (80, 0.2), (443, 0.2), (8080, 0.15), (3000, 0.15), (8443, 0.15),
            // Network / mgmt
            (22, 0.15), (23, 0.1), (161, 0.1),
            // NAS / file sharing
            (445, 0.15), (548, 0.15), (5000, 0.15), (5001, 0.15),
            // Printing
            (515, 0.1), (631, 0.1), (9100, 0.1),
            // Media / IoT
            (554, 0.15), (5543, 0.1), (1883, 0.15), (8883, 0.1),
            // Apple
            (62078, 0.1), (7000, 0.1),
            // UPnP / DLNA
            (1900, 0.1), (8200, 0.1),
            // mDNS
            (5353, 0.15)
        ]
        var open = [Int]()
        let group = DispatchGroup()

        for (port, timeout) in ports {
            group.enter()
            DispatchQueue.global().async {
                if tcpConnect(ip: ip, port: port, timeout: timeout) {
                    synchronized(self) { open.append(port) }
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 5)
        return open
    }

    private static func tcpConnect(ip: String, port: Int, timeout: TimeInterval) -> Bool {
        let host = NWEndpoint.Host(ip)
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
        let conn = NWConnection(host: host, port: nwPort, using: .tcp)

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        conn.stateUpdateHandler = { state in
            if case .ready = state { success = true; conn.cancel(); semaphore.signal() }
            if case .failed = state { conn.cancel(); semaphore.signal() }
            if case .cancelled = state { semaphore.signal() }
        }
        conn.start(queue: .global())
        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            conn.cancel()
        }
        return success
    }

    // MARK: - Reverse DNS

    static func resolveHostname(ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        inet_pton(AF_INET, ip, &addr.sin_addr)

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, 0)
            }
        }
        return result == 0 ? String(cString: hostname) : nil
    }

    // MARK: - Network Detection

    /// Detect local network info (auto-detect interface)
    static func detectLocalNetwork() -> LocalNetworkInfo? {
        // Get gateway from routing table
        let routeTask = Process()
        routeTask.executableURL = URL(fileURLWithPath: "/sbin/route")
        routeTask.arguments = ["-n", "get", "default"]
        let routePipe = Pipe()
        routeTask.standardOutput = routePipe
        try? routeTask.run()
        routeTask.waitUntilExit()
        let routeOutput = String(data: routePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var gatewayIP = "192.168.1.1"
        var routeInterface = "en0"
        for line in routeOutput.components(separatedBy: "\n") {
            if line.contains("gateway:") {
                gatewayIP = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if line.contains("interface:") {
                routeInterface = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "interface:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Find a real network interface (skip utun / tunnel interfaces)
        var interfaceName = routeInterface
        var localIP = "127.0.0.1"
        var netmask = "255.255.255.0"

        // First try the route interface
        if let info = getInterfaceInfo(interfaceName), !interfaceName.hasPrefix("utun") {
            localIP = info.ip
            netmask = info.mask
        } else {
            // Route goes through tunnel (VPN/proxy) — scan all enX interfaces
            for en in listInterfaces() where en.hasPrefix("en") {
                if let info = getInterfaceInfo(en), info.ip != "127.0.0.1",
                   isPrivateIP(info.ip) {
                    interfaceName = en
                    localIP = info.ip
                    netmask = info.mask
                    break
                }
            }
        }

        let subnet = ipToSubnet(localIP, netmask)
        let isWiFi = interfaceName.hasPrefix("en") && interfaceName != "en0"

        return LocalNetworkInfo(
            subnet: subnet, localIP: localIP, gatewayIP: gatewayIP,
            netmask: netmask, interfaceName: interfaceName, isWiFi: isWiFi
        )
    }

    private static func getInterfaceInfo(_ iface: String) -> (ip: String, mask: String)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = [iface]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var ip = ""
        var mask = ""
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("inet ") && ip.isEmpty {
                let parts = t.components(separatedBy: .whitespaces)
                if parts.count >= 2 { ip = parts[1] }
            }
            if (t.hasPrefix("netmask ") || t.contains("netmask ")) && mask.isEmpty {
                let parts = t.components(separatedBy: .whitespaces)
                for i in 0..<parts.count {
                    if parts[i] == "netmask" && i + 1 < parts.count {
                        var m = parts[i + 1]
                        if m.hasPrefix("0x") {
                            let hex = String(m.dropFirst(2))
                            if let val = UInt32(hex, radix: 16) {
                                m = "\(val >> 24).\((val >> 16) & 0xff).\((val >> 8) & 0xff).\(val & 0xff)"
                            }
                        }
                        mask = m
                        break
                    }
                }
            }
        }
        return ip.isEmpty ? nil : (ip, mask)
    }

    private static func listInterfaces() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["-l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
    }

    private static func isPrivateIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return (parts[0] == 10) ||
               (parts[0] == 192 && parts[1] == 168) ||
               (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31)
    }

    private static func ipToSubnet(_ ip: String, _ mask: String) -> String {
        let ipParts = ip.split(separator: ".").compactMap { Int($0) }
        let maskParts = mask.split(separator: ".").compactMap { Int($0) }
        guard ipParts.count == 4, maskParts.count == 4 else {
            return ip.components(separatedBy: ".").dropLast().joined(separator: ".")
        }
        return (0..<3).map { String(ipParts[$0] & maskParts[$0]) }.joined(separator: ".")
    }

    // MARK: - Device Type Guessing (enhanced)

    /// Guess device type from all available clues
    static func guessDevice(ip: String, mac: String?, vendor: String?, hostname: String?,
                           ports: [Int], bonjourServices: [String] = []) -> DeviceType {
        let portsSet = Set(ports)
        let hname = (hostname ?? "").lowercased()
        let vend = (vendor ?? "").lowercased()
        let macStr = (mac ?? "").lowercased()
        let svcSet = Set(bonjourServices)

        // 1. Gateway
        if ip.hasSuffix(".1") { return .router }

        // 2. By MAC vendor
        if vend.contains("asus") || vend.contains("tp-link") || vend.contains("netgear") ||
           vend.contains("ubiquiti") || vend.contains("mikrotik") || vend.contains("cisco") {
            return .router
        }

        // 3. By ports
        if portsSet.contains(554) || portsSet.contains(5543) { return .camera }
        if portsSet.contains(5000) || portsSet.contains(5001) { return .nas }
        if portsSet.contains(445) || portsSet.contains(548) { return .nas }
        if portsSet.contains(515) || portsSet.contains(631) || portsSet.contains(9100) { return .printer }
        if portsSet.contains(1883) || portsSet.contains(8883) { return .iot }

        // 4. By hostname keywords
        let nasWords = ["nas", "diskstation", "synology", "qnap", "wdmycloud", "freenas", "truenas"]
        let camWords = ["cam", "ipc", "camera", "hikvision", "dahua", "reolink", "doorbell"]
        let printerWords = ["printer", "brother", "hp-", "canon-", "epson", "xerox"]
        let iotWords = ["yeelight", "xiaomi", "mi-", "philips-hue", "tplink", "kasa", "wemo", "shelly",
                        "sonoff", "tasmota", "esphome", "esp-", "sensor", "thermometer", "hvac",
                        "purifier", "humidifier", "water", "plug", "switch", "light", "bulb", "outlet"]
        let phoneWords = ["iphone", "ipad", "android", "pixel", "samsung", "oneplus", "xiaomi", "huawei"]
        let appleWords = ["apple", "macbook", "imac", "macpro", "macmini", "iphone", "ipad", "ipod", "homepod"]

        for word in nasWords { if hname.contains(word) || vend.contains(word) { return .nas } }
        for word in camWords { if hname.contains(word) { return .camera } }
        for word in printerWords { if hname.contains(word) || vend.contains(word) { return .printer } }
        for word in iotWords { if hname.contains(word) || vend.contains(word) { return .iot } }
        for word in phoneWords { if hname.contains(word) { return .phone } }
        for word in appleWords { if hname.contains(word) || vend.contains("apple") { return .phone } }

        // 5. By vendor
        if vend.contains("intel") || vend.contains("dell") || vend.contains("hp") ||
           vend.contains("lenovo") || vend.contains("asus") && !ip.hasSuffix(".1") { return .computer }
        if vend.contains("raspberry") { return .computer }  // Pi often runs as server
        if vend.contains("sony") || vend.contains("samsung") || vend.contains("lg") { return .tv }
        if vend.contains("nest") || vend.contains("ring") || vend.contains("arlo") { return .camera }

        // 6. By Bonjour services
        if svcSet.contains("_airplay._tcp.") { return .tv }
        if svcSet.contains("_hap._tcp.") || svcSet.contains("_homekit._tcp.") { return .iot }
        if svcSet.contains("_printer._tcp.") { return .printer }
        if svcSet.contains("_smb._tcp.") { return .nas }

        // 7. Port-based fallback
        if portsSet.contains(80) || portsSet.contains(443) || portsSet.contains(8080) {
            return .computer
        }

        return .unknown
    }

    // MARK: - Thread-safe helper

    private static func synchronized<T>(_ lock: Any, _ block: () -> T) -> T {
        objc_sync_enter(lock); defer { objc_sync_exit(lock) }
        return block()
    }
}

// MARK: - OUI Database (common vendors)

private let OUI_DB: [String: String] = [
    // Apple
    "000A27": "Apple", "000A95": "Apple", "001124": "Apple", "001451": "Apple",
    "0016CB": "Apple", "001FF3": "Apple", "002312": "Apple", "002436": "Apple",
    "00254B": "Apple", "002608": "Apple", "003065": "Apple", "00CDFE": "Apple",
    "040CCE": "Apple", "0469F8": "Apple", "04DB56": "Apple", "080007": "Apple",
    "08107A": "Apple", "0C1539": "Apple", "0C3021": "Apple", "0C5101": "Apple",
    "0C771A": "Apple", "1495CE": "Apple", "183451": "Apple", "1C1AC0": "Apple",
    "1C9148": "Apple", "201D48": "Apple", "24A074": "Apple", "280BCA": "Apple",
    "28E02C": "Apple", "28E7CF": "Apple", "2C200B": "Apple", "3064C0": "Apple",
    "3451C9": "Apple", "38C986": "Apple", "3C15C2": "Apple", "404D7F": "Apple",
    "40A6D9": "Apple", "485D60": "Apple", "4C3275": "Apple", "5433CB": "Apple",
    "58404E": "Apple", "587F57": "Apple", "5C9699": "Apple", "5CF7E6": "Apple",
    "60334E": "Apple", "60FEC5": "Apple", "64703C": "Apple", "68A86D": "Apple",
    "689C70": "Apple", "6CC26B": "Apple", "70700D": "Apple", "741BB2": "Apple",
    "7811DC": "Apple", "78CA39": "Apple", "7CC537": "Apple", "80E650": "Apple",
    "841B5E": "Apple", "88644A": "Apple", "8C8590": "Apple", "909C4A": "Apple",
    "98B8E3": "Apple", "9CF48E": "Apple", "A4516F": "Apple", "A85B78": "Apple",
    "A886DD": "Apple", "A8BE27": "Apple", "ACBC32": "Apple", "B065BD": "Apple",
    "B09FBA": "Apple", "B41974": "Apple", "B844D9": "Apple", "BC4CC4": "Apple",
    "BC926B": "Apple", "C06394": "Apple", "C86F1D": "Apple", "CC08E0": "Apple",
    "CC25EF": "Apple", "CC29F5": "Apple", "CFD6AF": "Apple", "D4A33D": "Apple",
    "D81D72": "Apple", "DC2B61": "Apple", "E05F45": "Apple", "E8B2AC": "Apple",
    "F099B6": "Apple", "F0B0E7": "Apple", "F0DCE2": "Apple", "F431C3": "Apple",
    "F82793": "Apple", "FC253F": "Apple", "FCD848": "Apple",

    // ASUS
    "000C6E": "ASUS", "0011D8": "ASUS", "001FC6": "ASUS", "002354": "ASUS",
    "00248C": "ASUS", "08BFB8": "ASUS", "0C9D92": "ASUS", "1008B1": "ASUS",
    "1C87C8": "ASUS", "24A43C": "ASUS", "2C566D": "ASUS", "309A4A": "ASUS",
    "382B78": "ASUS", "38D547": "ASUS", "40B076": "ASUS", "485B39": "ASUS",
    "4CEDFB": "ASUS", "50465D": "ASUS", "54271E": "ASUS", "60A44C": "ASUS",
    "704E01": "ASUS", "7440BB": "ASUS", "781D03": "ASUS", "7C103B": "ASUS",
    "843497": "ASUS", "88D7F6": "ASUS", "8C85C1": "ASUS", "906108": "ASUS",
    "9C4E36": "ASUS", "A82BB9": "ASUS", "AC220B": "ASUS", "B06EBF": "ASUS",
    "C86000": "ASUS", "D017C2": "ASUS", "D41F0A": "ASUS", "D8452B": "ASUS",
    "E0CB4E": "ASUS", "F07959": "ASUS",

    // Intel
    "0001E6": "Intel", "0002B3": "Intel", "0003A9": "Intel", "0004E2": "Intel",
    "0007E9": "Intel", "000EAE": "Intel", "0013E8": "Intel", "001500": "Intel",
    "001517": "Intel", "00166F": "Intel", "0018DE": "Intel", "001D7E": "Intel",
    "001E64": "Intel", "0023A7": "Intel", "00259C": "Intel", "0026C6": "Intel",
    "0027D2": "Intel", "041B94": "Intel", "101F74": "Intel", "146A55": "Intel",
    "189B4B": "Intel", "1C69A5": "Intel", "202009": "Intel", "242F5C": "Intel",
    "3C5CC6": "Intel", "4C03AB": "Intel", "4C79EB": "Intel", "503A75": "Intel",
    "54044B": "Intel", "5CB066": "Intel", "60F118": "Intel", "64BC58": "Intel",
    "6854F2": "Intel", "6C25B4": "Intel", "705975": "Intel", "74E5B3": "Intel",
    "78D004": "Intel", "7C5DC6": "Intel", "80A8D3": "Intel", "84EF18": "Intel",
    "887609": "Intel", "8C8D28": "Intel", "985AEB": "Intel", "A002A8": "Intel",
    "A47637": "Intel", "AC9B8A": "Intel", "B8AE6D": "Intel", "C4D489": "Intel",
    "C8D9D2": "Intel", "D4FB2E": "Intel", "DCB536": "Intel", "E4B99A": "Intel",
    "E4FE43": "Intel", "F0C816": "Intel", "F4340B": "Intel", "F4D01D": "Intel",
    "F8978F": "Intel",

    // TP-Link
    "0016B6": "TP-Link", "001D0F": "TP-Link", "002719": "TP-Link",
    "00E04C": "TP-Link", "080026": "TP-Link", "10417F": "TP-Link",
    "10D7B0": "TP-Link", "142D27": "TP-Link", "18A6F7": "TP-Link",
    "1C61B4": "TP-Link", "2430A1": "TP-Link", "244B03": "TP-Link",
    "385918": "TP-Link", "40BBAE": "TP-Link", "442851": "TP-Link",
    "50C7BF": "TP-Link", "641187": "TP-Link", "64E5E8": "TP-Link",
    "6C5AB5": "TP-Link", "74DA88": "TP-Link", "7CB003": "TP-Link",
    "8038BC": "TP-Link", "84702B": "TP-Link", "8C8DDD": "TP-Link",
    "90203A": "TP-Link", "942B55": "TP-Link", "9845E0": "TP-Link",
    "A06CEC": "TP-Link", "B01CBF": "TP-Link", "B04F13": "TP-Link",
    "B82AD4": "TP-Link", "C02662": "TP-Link", "C04619": "TP-Link",
    "D03EC6": "TP-Link", "D86CE9": "TP-Link", "E09A54": "TP-Link",
    "EC086B": "TP-Link", "F0103A": "TP-Link",

    // Samsung
    "0000F0": "Samsung", "0001F4": "Samsung", "001632": "Samsung",
    "0018AF": "Samsung", "002171": "Samsung", "0403D6": "Samsung",
    "0821EF": "Samsung", "0C8910": "Samsung", "149AEC": "Samsung",
    "18105E": "Samsung", "1CAAA7": "Samsung", "2099E7": "Samsung",
    "248337": "Samsung", "280BA4": "Samsung", "2C09B3": "Samsung",
    "3881D7": "Samsung", "3CA0A7": "Samsung", "40D32D": "Samsung",
    "4458CB": "Samsung", "48CA43": "Samsung", "4C5759": "Samsung",
    "5079E2": "Samsung", "58D0A2": "Samsung", "5C5EB9": "Samsung",
    "60703C": "Samsung", "64D154": "Samsung", "6848E5": "Samsung",
    "700136": "Samsung", "74EE2A": "Samsung", "78BDBC": "Samsung",
    "7CBC84": "Samsung", "80009C": "Samsung", "84C2E4": "Samsung",
    "884A18": "Samsung", "8C79F5": "Samsung", "901B0E": "Samsung",
    "940422": "Samsung", "984E97": "Samsung", "9CF804": "Samsung",
    "A0D3C1": "Samsung", "A45055": "Samsung", "A883CC": "Samsung",
    "AC5D10": "Samsung", "B047BF": "Samsung", "B40E96": "Samsung",
    "B83A0B": "Samsung", "BC7663": "Samsung", "C05E79": "Samsung",
    "C453A3": "Samsung", "C8D51E": "Samsung", "CC05E8": "Samsung",
    "D0176A": "Samsung", "D45856": "Samsung", "D8973C": "Samsung",
    "DC6672": "Samsung", "E09D31": "Samsung", "E44EDE": "Samsung",
    "E89FEB": "Samsung", "EC24B8": "Samsung", "F0DDA1": "Samsung",
    "F40343": "Samsung", "F83991": "Samsung", "FC64BA": "Samsung",

    // Xiaomi
    "0C1DAF": "Xiaomi", "10B1F8": "Xiaomi", "14F65A": "Xiaomi",
    "181BEB": "Xiaomi", "1C8ADA": "Xiaomi", "206E9C": "Xiaomi",
    "244BFE": "Xiaomi", "28E31F": "Xiaomi", "2CB430": "Xiaomi",
    "3068CB": "Xiaomi", "34CE00": "Xiaomi", "38A49F": "Xiaomi",
    "3CA87B": "Xiaomi", "40D3EB": "Xiaomi", "4455E8": "Xiaomi",
    "4842E2": "Xiaomi", "4C1520": "Xiaomi", "508674": "Xiaomi",
    "5433A6": "Xiaomi", "583170": "Xiaomi", "5C89F0": "Xiaomi",
    "601876": "Xiaomi", "648E97": "Xiaomi", "689D0D": "Xiaomi",
    "6C9A5D": "Xiaomi", "7046AE": "Xiaomi", "742AEA": "Xiaomi",
    "783DC6": "Xiaomi", "7C3E9D": "Xiaomi", "806E6E": "Xiaomi",
    "847A88": "Xiaomi", "882231": "Xiaomi", "8C9E83": "Xiaomi",
    "906E1A": "Xiaomi", "942996": "Xiaomi", "98208E": "Xiaomi",
    "9C5D12": "Xiaomi", "A04E01": "Xiaomi", "A47605": "Xiaomi",
    "A8A648": "Xiaomi", "AC9A86": "Xiaomi", "B0E5F5": "Xiaomi",
    "B4760A": "Xiaomi", "B8602A": "Xiaomi", "BC5436": "Xiaomi",
    "C0EAC2": "Xiaomi", "C40B31": "Xiaomi", "C8A823": "Xiaomi",
    "CCA1C2": "Xiaomi", "D0971B": "Xiaomi", "D4609E": "Xiaomi",
    "D87775": "Xiaomi", "DC68BA": "Xiaomi", "E036E8": "Xiaomi",
    "E466E2": "Xiaomi", "E8825B": "Xiaomi", "EC5C68": "Xiaomi",
    "F04A8A": "Xiaomi", "F483CD": "Xiaomi", "F8811A": "Xiaomi",
    "FCC233": "Xiaomi",

    // Cisco
    "00000C": "Cisco", "000142": "Cisco", "00036B": "Cisco", "00059B": "Cisco",
    "0008E3": "Cisco", "000D65": "Cisco", "0011BB": "Cisco", "0013C4": "Cisco",
    "0018BA": "Cisco", "001D45": "Cisco", "002255": "Cisco", "0026C5": "Cisco",

    // Netgear
    "000FB5": "Netgear", "00146C": "Netgear", "001F33": "Netgear", "00223F": "Netgear",
    "04A151": "Netgear", "081FF3": "Netgear", "0C3CCD": "Netgear", "10DA43": "Netgear",
    "14CC20": "Netgear", "2C3033": "Netgear", "307496": "Netgear", "347877": "Netgear",
    "404A18": "Netgear", "44A56C": "Netgear", "4C9EFF": "Netgear", "580BDB": "Netgear",
    "5CB524": "Netgear", "60F59C": "Netgear", "6CB02B": "Netgear", "744DBF": "Netgear",
    "80B686": "Netgear", "84D81C": "Netgear", "88E3AB": "Netgear", "901AAC": "Netgear",
    "946A77": "Netgear", "982B92": "Netgear", "A04B87": "Netgear", "A8B1B5": "Netgear",
    "B07FB9": "Netgear", "B4A5EF": "Netgear", "C03FD4": "Netgear", "C4047B": "Netgear",
    "CC40D0": "Netgear", "D08DC6": "Netgear", "D4FDAC": "Netgear", "DC9FDB": "Netgear",
    "E091F5": "Netgear", "E46F13": "Netgear",

    // Google / Nest
    "001A11": "Google", "081735": "Google", "10090C": "Google", "14BB3D": "Google",
    "183146": "Google", "1C2863": "Google", "2022B4": "Google", "2455D5": "Google",
    "2894AF": "Google", "2CA5B8": "Google", "3077C7": "Google", "34A2A2": "Google",
    "3871DE": "Google", "3C28A0": "Google", "409D71": "Google", "4430A9": "Google",
    "4855EA": "Google", "4CE8CC": "Google", "507081": "Google", "5470F1": "Google",
    "586CCD": "Google", "5CAAFD": "Google", "60B3C4": "Google", "6496F7": "Google",
    "6872C0": "Google", "6CA100": "Google", "763205": "Google",

    // HP
    // HP (remaining unique)
    "001321": "HP",
    "0019BB": "HP", "0021D7": "HP", "002655": "HP", "0027CB": "HP",
    "003018": "HP", "080009": "HP", "0C4C8A": "HP", "104F58": "HP",
    "187ED5": "HP", "1C98EC": "HP", "200BC0": "HP", "28CD4C": "HP",
    "308294": "HP", "3863BB": "HP", "3C52A1": "HP", "408493": "HP",
    "48DF37": "HP", "4C0F6E": "HP", "505B96": "HP", "5812CF": "HP",
    "609C9A": "HP", "64EBCD": "HP", "68B599": "HP", "6C0B84": "HP",
    "705A0F": "HP", "78F5FD": "HP", "7C2E0D": "HP", "809C85": "HP",
    "8439EC": "HP", "8875C3": "HP", "8C1F64": "HP", "9077EE": "HP",
    "9447F3": "HP", "98E7F4": "HP", "9C29F5": "HP", "A0D1D7": "HP",
    "A48CD6": "HP", "A834C7": "HP", "AC7289": "HP", "B05ADA": "HP",

    // Synology
    "001132": "Synology",

    // Dell
    "00023E": "Dell", "00045A": "Dell", "000BDB": "Dell", "000F1F": "Dell",
    "001018": "Dell", "001372": "Dell", "0014F1": "Dell", "0018C4": "Dell",
    "002170": "Dell", "0026B9": "Dell", "08001F": "Dell", "0C1AB5": "Dell",
    "18FB7B": "Dell", "1C876C": "Dell", "24B6FD": "Dell", "285AEB": "Dell",
    "346895": "Dell", "3C07F6": "Dell", "40B034": "Dell", "482A58": "Dell",
    "5079D6": "Dell", "54220F": "Dell", "5849BA": "Dell", "5C6F4F": "Dell",
    "6420F1": "Dell", "684B88": "Dell", "6C3E6D": "Dell", "74E50B": "Dell",
    "78D6FC": "Dell", "7C3BD6": "Dell", "80645F": "Dell", "845B12": "Dell",
    "881F5E": "Dell", "8CB863": "Dell", "9099F3": "Dell", "940EBC": "Dell",
    "984FEE": "Dell", "9C0597": "Dell", "A036FA": "Dell", "A41D21": "Dell",
    "A8346A": "Dell", "AC1F6B": "Dell", "B08CF4": "Dell", "B82A72": "Dell",

    // Sony
    "000127": "Sony", "0013A9": "Sony", "001637": "Sony", "001DBA": "Sony",
    "0024BE": "Sony", "080046": "Sony", "0C3B50": "Sony", "104FA5": "Sony",
    "147052": "Sony", "1832F1": "Sony", "2022E5": "Sony", "24BEBA": "Sony",
    "288023": "Sony", "2CA4B2": "Sony", "3061EB": "Sony", "3433B2": "Sony",
    "38845B": "Sony", "3C0771": "Sony", "407D0F": "Sony", "445EFD": "Sony",
    "485A3F": "Sony", "4C153A": "Sony", "502680": "Sony", "5453ED": "Sony",
    "5849B4": "Sony", "5C2DDE": "Sony", "60156C": "Sony", "64D855": "Sony",
    "68764F": "Sony", "6C1E90": "Sony", "701DC4": "Sony", "74D7EB": "Sony",
    "78709E": "Sony", "7C60B9": "Sony", "84455B": "Sony",
    "882C1A": "Sony", "8CA6DF": "Sony", "908D6C": "Sony", "98E79A": "Sony",
    "9C2A83": "Sony", "A028CD": "Sony",

    // Hikvision / Dahua (cameras)
    "00216C": "Hikvision", "183F70": "Hikvision", "28EDE0": "Hikvision",
    "347DE4": "Hikvision", "40EE15": "Hikvision", "4CBAA3": "Hikvision",
    "503956": "Hikvision", "54ADA7": "Hikvision", "5C0F56": "Hikvision",
    "604A1C": "Hikvision", "64ECDA": "Hikvision", "687DD2": "Hikvision",
    "6C5666": "Hikvision", "70F96D": "Hikvision", "7499DE": "Hikvision",
    "788A20": "Hikvision", "7C20FC": "Hikvision", "807A1F": "Dahua",
    "84683E": "Dahua", "88A25B": "Dahua", "8C9F87": "Hikvision",
    "9002A9": "Hikvision", "98BD80": "Dahua", "9C6A3B": "Dahua",
    "A02EF3": "Dahua", "A439B3": "Dahua", "A80180": "Hikvision",

    // Raspberry Pi
    "B827EB": "Raspberry Pi", "DC26DC": "Raspberry Pi", "E45F01": "Raspberry Pi",
    "B8F828": "Raspberry Pi",

    // QNAP
    "0024C3": "QNAP",

    // Ubiquiti
    "00040D": "Ubiquiti", "000DF0": "Ubiquiti", "001856": "Ubiquiti",
    "00312B": "Ubiquiti", "00728E": "Ubiquiti", "0418D6": "Ubiquiti",
    "04D4C4": "Ubiquiti", "0CA402": "Ubiquiti", "10326E": "Ubiquiti",
    "180DD8": "Ubiquiti", "1C1A68": "Ubiquiti", "28BC18": "Ubiquiti", "2C296D": "Ubiquiti",
    "3473DE": "Ubiquiti", "38EC64": "Ubiquiti", "3CEDFD": "Ubiquiti",
    "40BD9E": "Ubiquiti", "44D9E7": "Ubiquiti", "4874F6": "Ubiquiti",
    "4C2230": "Ubiquiti", "5024F5": "Ubiquiti", "542A9C": "Ubiquiti",
    "583BD3": "Ubiquiti", "5CE2EB": "Ubiquiti", "602AD1": "Ubiquiti",
    "648125": "Ubiquiti", "688A82": "Ubiquiti", "6CD68A": "Ubiquiti",
    "7061C0": "Ubiquiti", "74ACB9": "Ubiquiti", "788A86": "Ubiquiti",
    "7C305A": "Ubiquiti", "807B85": "Ubiquiti", "8408F1": "Ubiquiti",
    "8817AE": "Ubiquiti", "8C3A9D": "Ubiquiti", "900DB6": "Ubiquiti",
    "94235C": "Ubiquiti", "9847E6": "Ubiquiti", "9C7EED": "Ubiquiti",
    "A049BB": "Ubiquiti", "A45723": "Ubiquiti", "A80600": "Ubiquiti",
    "AC15A2": "Ubiquiti", "B0A86E": "Ubiquiti", "B40BD3": "Ubiquiti",
    "B8763F": "Ubiquiti", "BC1AE6": "Ubiquiti", "C06599": "Ubiquiti",
    "C4291D": "Ubiquiti", "C81EB1": "Ubiquiti", "CC1AFA": "Ubiquiti",
    "D021F9": "Ubiquiti", "D446A1": "Ubiquiti", "D85FEF": "Ubiquiti",
    "DC15DB": "Ubiquiti", "E06F98": "Ubiquiti", "E44ED8": "Ubiquiti",

    // Espressif (ESP32/ESP8266)
    "08D4C4": "Espressif", "10CEA9": "Espressif",
    "18B905": "Espressif", "1C3F27": "Espressif",
    "240ACA": "Espressif", "280D8F": "Espressif", "2CC0AF": "Espressif",
    "30AEA4": "Espressif", "34AB95": "Espressif", "389C25": "Espressif",
    "3C16CD": "Espressif", "400D10": "Espressif", "4440A9": "Espressif",
    "4851B7": "Espressif", "4CE176": "Espressif", "506583": "Espressif",
    "54EC2D": "Espressif", "5C9B71": "Espressif",
    "60A423": "Espressif", "648B82": "Espressif", "68696B": "Espressif",
    "706932": "Espressif", "74591C": "Espressif",
    "78511D": "Espressif", "7C432D": "Espressif", "803A58": "Espressif",
    "8468C6": "Espressif", "8833A3": "Espressif", "8C255D": "Espressif",
    "947C3E": "Espressif", "980D2E": "Espressif",
    "9C3E54": "Espressif", "A01C05": "Espressif", "A4C47E": "Espressif",
    "A81B6A": "Espressif", "AC67B2": "Espressif", "B05D23": "Espressif",
    "B4EB99": "Espressif", "B86B0F": "Espressif", "BC225A": "Espressif",
    "C09EA4": "Espressif", "C4D328": "Espressif", "C82E47": "Espressif",
    "CC13F3": "Espressif", "D0EF76": "Espressif", "D48AE7": "Espressif",
    "D896E0": "Espressif", "DC2F8C": "Espressif", "E06C1B": "Espressif",
    "E468A3": "Espressif", "E87719": "Espressif", "ECBE27": "Espressif",
    "F0C3C5": "Espressif", "F4A294": "Espressif", "F884B8": "Espressif",
    "FC2543": "Espressif",

    // Brothers (printers)
    "00187C": "Brother", "0030DD": "Brother", "00509D": "Brother",
    "0847ED": "Brother", "0C6E8A": "Brother", "1459C2": "Brother",
    "18C8B6": "Brother", "1C3D4B": "Brother", "2062AB": "Brother",
    "24BA30": "Brother", "28235C": "Brother", "2CE4A2": "Brother",
    "3073C6": "Brother", "34A706": "Brother", "38C16C": "Brother",
    "3CC82A": "Brother", "40A220": "Brother", "44DC91": "Brother",
    "486B2A": "Brother", "4C3122": "Brother", "506A03": "Brother",
    "54936B": "Brother", "58885C": "Brother", "5C68F5": "Brother",
    "606C66": "Brother", "6486C0": "Brother", "686B60": "Brother",
    "6CBE99": "Brother", "708901": "Brother", "741B2A": "Brother",
    "7895F5": "Brother", "7C0ED3": "Brother", "808F1D": "Brother",
    "848D84": "Brother", "88971B": "Brother", "8C05EB": "Brother",
    "90704E": "Brother",
]
