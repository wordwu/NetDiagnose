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
    let hostname: String?
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

// ---- SSDP / UPnP Discovery ----
struct SSDPResponse {
    let ip: String
    let location: String        // URL to XML device description
    let server: String          // Server header (often reveals OS/device type)
    let st: String              // Search Target (urn:schemas-upnp-org:device:...)
    let usn: String             // Unique Service Name
}

struct DeviceIdentification {
    let type: DeviceType
    let confidence: IdentificationConfidence
    let evidence: [String]
    let services: [String]
    let osGuess: String?
}

struct DeviceRisk {
    let level: RiskLevel
    let notes: [String]
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

            // Hostname: use ARP name if it's not "?" or equals the IP
            let arpName = hostname == "?" || hostname == ip ? nil : hostname

            // Sanitize MAC
            let mac = macStr  // Keep raw for vendor lookup
            entries.append(ArpEntry(ip: ip, mac: mac, interface: iface, permanent: permanent, hostname: arpName))
        }
        return entries
    }

    // MARK: - MAC Vendor Lookup

    /// Lookup vendor from MAC OUI prefix (delegates to OUIDatabase)
    static func lookupVendor(mac: String) -> String? {
        return OUIDatabase.lookup(mac: mac)
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

    // MARK: - SSDP / UPnP Discovery

    /// Discover UPnP devices via SSDP M-SEARCH using native Darwin sockets.
    /// No Python3 dependency — pure C socket multicast.
    static func ssdpScan(timeout: TimeInterval = 2.0) -> [SSDPResponse] {
        var responses = [SSDPResponse]()

        // Create UDP socket
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return responses }
        defer { close(sock) }

        // Reuse address
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Multicast TTL
        var ttl: UInt8 = 2
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        // Bind to any port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        // Multicast group address
        var mreq = ip_mreq()
        inet_pton(AF_INET, "239.255.255.250", &mreq.imr_multiaddr)
        mreq.imr_interface.s_addr = INADDR_ANY
        setsockopt(sock, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))

        // Dest address
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

        // SSDP search targets
        let targets = [
            "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:device:MediaServer:1",
            "urn:schemas-upnp-org:service:WANIPConnection:1",
            "ssdp:all",
        ]

        // Build M-SEARCH message template
        func msearch(st: String) -> String {
            return "M-SEARCH * HTTP/1.1\r\n" +
                   "HOST: 239.255.255.250:1900\r\n" +
                   "MAN: \"ssdp:discover\"\r\n" +
                   "MX: 2\r\n" +
                   "ST: \(st)\r\n" +
                   "\r\n"
        }

        // Send M-SEARCH for each target
        for st in targets {
            let msg = msearch(st: st)
            let data = msg.data(using: .utf8)!
            _ = data.withUnsafeBytes { buf in
                withUnsafePointer(to: &dest) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                        sendto(sock, buf.baseAddress, data.count, 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Receive responses
        var seenUSNs = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var fromAddr = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let deadline = Date().timeIntervalSince1970 + timeout
        while Date().timeIntervalSince1970 < deadline {
            let recvd = withUnsafeMutablePointer(to: &fromAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    recvfrom(sock, &buffer, buffer.count, 0, ptr, &fromLen)
                }
            }
            guard recvd > 0 else { break }  // timeout or error

            let resp = String(bytes: buffer[0..<Int(recvd)], encoding: .utf8) ?? ""
            var headers = [String: String]()
            for line in resp.components(separatedBy: "\r\n") {
                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces).uppercased()
                    let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }

            let ip = String(cString: inet_ntoa(fromAddr.sin_addr))
            let usn = headers["USN"] ?? ""
            guard !usn.isEmpty, !seenUSNs.contains(usn) else { continue }
            seenUSNs.insert(usn)

            responses.append(SSDPResponse(
                ip: ip,
                location: headers["LOCATION"] ?? "",
                server: headers["SERVER"] ?? "",
                st: headers["ST"] ?? "",
                usn: usn
            ))
        }

        return responses
    }

    /// Classify SSDP response into device type
    static func classifySSDP(_ resp: SSDPResponse) -> DeviceType? {
        let st = resp.st.lowercased()
        let server = resp.server.lowercased()

        // UPnP device types → our device types
        if st.contains("internetgatewaydevice") || st.contains("wanipconnection") ||
           st.contains("wandevice") || st.contains("wancommoninterfaceconfig") {
            return .router
        }
        if st.contains("mediarenderer") || st.contains("mediaserver") {
            return .tv  // Usually smart TV, media player
        }
        if st.contains("printer") || st.contains("printbasic") {
            return .printer
        }
        if st.contains("networkstorage") || st.contains("nas") {
            return .nas
        }
        if st.contains("camera") || st.contains("digitalsecuritycamera") {
            return .camera
        }

        // Server string clues
        if server.contains("router") || server.contains("gateway") ||
           server.contains("dd-wrt") || server.contains("openwrt") ||
           server.contains("tomato") || server.contains("asuswrt") {
            return .router
        }
        if server.contains("synology") || server.contains("qnap") ||
           server.contains("freenas") || server.contains("truenas") {
            return .nas
        }
        if server.contains("tv") || server.contains("samsung") ||
           server.contains("lg") || server.contains("roku") ||
           server.contains("plex") {
            return .tv
        }
        if server.contains("printer") || server.contains("brother") ||
           server.contains("canon") || server.contains("epson") || server.contains("hp ") {
            return .printer
        }

        return nil
    }

    // MARK: - Ping Sweep

    /// Ping sweep a /24 subnet
    static func pingSweep(subnet: String, skipIPs: Set<String> = [], maxConcurrent: Int = 32) -> [PingResult] {
        var results = [PingResult]()
        let queue = DispatchQueue(label: "nettopo.ping", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        let throttle = DispatchSemaphore(value: max(1, maxConcurrent))

        for i in 1...254 {
            let ip = "\(subnet).\(i)"
            if skipIPs.contains(ip) { continue }
            group.enter()
            queue.async {
                throttle.wait()
                defer {
                    throttle.signal()
                    group.leave()
                }
                if Task.isCancelled { return }
                if ping(ip: ip) {
                    let hostname = resolveHostname(ip: ip)
                    lock.lock()
                    results.append(PingResult(ip: ip, hostname: hostname, latency: nil))
                    lock.unlock()
                }
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

    /// Measure latency to a single IP. Returns avg round-trip in ms, or nil if unreachable.
    /// Uses /sbin/ping with 3 packets, parses "avg" from the summary line.
    static func measureLatency(ip: String) -> Double? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "3", "-t", "1", "-W", "3000", ip]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            if let range = output.range(of: " = "),
               let endRange = output[range.upperBound...].range(of: " ms") {
                let stats = String(output[range.upperBound..<endRange.lowerBound])
                let parts = stats.split(separator: "/")
                if parts.count >= 4, let avg = Double(parts[1]) { return avg }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Port Scan

    /// Quick port scan for ARP-only devices — only check ports that help identify device type
    static func checkKeyPorts(ip: String) -> [Int] {
        scanPorts(ip: ip, ports: [
            (80, 0.3), (443, 0.3),        // Web — likely computer/NAS
            (445, 0.3), (548, 0.3),       // SMB/AFP — NAS
            (5000, 0.3), (5001, 0.3),     // Synology/QNAP
            (8080, 0.2), (8443, 0.2),     // Alt web
            (22, 0.2),                     // SSH — server
            (1883, 0.2),                   // MQTT — IoT
        ])
    }

    /// Extended port scan with mode-dependent concurrency and timeout
    static func checkPorts(ip: String, mode: ScanMode = .standard) -> [Int] {
        let t = mode.portTimeout
        var ports: [(Int, TimeInterval)] = [
            // Web
            (80, t), (443, t), (8080, t*0.8), (3000, t*0.8), (8443, t*0.8),
            // Network / mgmt
            (22, t*0.8), (23, t*0.6), (161, t*0.6),
            // NAS / file sharing
            (445, t*0.8), (548, t*0.8), (5000, t*0.8), (5001, t*0.8),
            // Printing
            (515, t*0.6), (631, t*0.6), (9100, t*0.6),
            // Media / IoT
            (554, t*0.8), (5543, t*0.6), (1883, t*0.8), (8883, t*0.6),
            // Apple
            (62078, t*0.6), (7000, t*0.6),
            // UPnP / DLNA
            (1900, t*0.6), (8200, t*0.6),
            // mDNS
            (5353, t*0.8)
        ]

        switch mode {
        case .quick:
            ports = [(80, t), (443, t), (445, t), (22, t*0.8), (515, t*0.6), (9100, t*0.6)]
        case .standard:
            break
        case .deep:
            ports += [
                (53, t*0.6), (67, t*0.6), (88, t*0.6), (135, t*0.6), (137, t*0.6),
                (389, t*0.6), (500, t*0.6), (873, t*0.6), (1433, t*0.6), (3306, t*0.6),
                (5432, t*0.6), (5672, t*0.6), (6379, t*0.6), (8008, t*0.6), (9000, t*0.6),
                (9090, t*0.6), (32400, t*0.6)
            ]
        }
        return scanPorts(ip: ip, ports: ports, maxConcurrent: mode.portConcurrency)
    }

    private static func scanPorts(ip: String, ports: [(Int, TimeInterval)], maxConcurrent: Int = 16) -> [Int] {
        var open = [Int]()
        let group = DispatchGroup()
        let lock = NSLock()
        let throttle = DispatchSemaphore(value: max(1, maxConcurrent))
        let totalTimeout = ports.map { $0.1 }.reduce(0, +) / Double(maxConcurrent) + 1.0

        for (port, timeout) in ports {
            group.enter()
            DispatchQueue.global().async {
                throttle.wait()
                defer { throttle.signal() }
                if tcpConnect(ip: ip, port: port, timeout: timeout) {
                    lock.lock()
                    open.append(port)
                    lock.unlock()
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + totalTimeout)
        return open.sorted()
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
            // 超时后主动取消连接，避免连接资源堆积
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
        let phoneWords = ["iphone", "ipad", "android", "pixel", "samsung", "oneplus", "huawei", "xiaomi", "redmi"]
        let appleWords = ["apple", "macbook", "imac", "macpro", "macmini", "iphone", "ipad", "ipod", "homepod"]
        let iotWords = ["yeelight", "xiaomi", "mi-", "philips-hue", "tplink", "kasa", "wemo", "shelly",
                        "sonoff", "tasmota", "esphome", "esp-", "sensor", "thermometer", "hvac",
                        "purifier", "humidifier", "water", "plug", "switch", "light", "bulb", "outlet",
                        "viomi", "chuangmi", "aqara", "lumi", "motion", "contact", "leak", "smoke",
                        "curtain", "lock", "door"]

        for word in nasWords { if hname.contains(word) || vend.contains(word) { return .nas } }
        for word in camWords { if hname.contains(word) { return .camera } }
        for word in printerWords { if hname.contains(word) || vend.contains(word) { return .printer } }
        for word in phoneWords { if hname.contains(word) { return .phone } }
        for word in appleWords { if hname.contains(word) || vend.contains("apple") { return .phone } }
        for word in iotWords { if hname.contains(word) || vend.contains(word) { return .iot } }

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
