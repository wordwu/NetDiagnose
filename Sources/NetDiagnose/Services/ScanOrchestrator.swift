import Foundation
import SwiftUI

@MainActor
class ScanOrchestrator: ObservableObject {
    @Published var scanResult: ScanResult? = nil
    @Published var scanProgress: String = "准备扫描..."
    @Published var progressValue: Float = 0
    @Published var isScanning: Bool = false
    @Published var scanMode: ScanMode = .standard
    @Published var errorMessage: String? = nil
    @Published var selectedScenario: NetworkScenario? = nil
    private var scanTask: Task<Void, Never>?

    var previousSnapshot: ScanSnapshot? {
        ScanHistoryService.shared.latest()
    }

    var diagnosticFindings: [DiagnosticFinding] {
        guard let result = scanResult else { return [] }
        return DiagnosticEngine.analyze(
            devices: result.devices,
            previous: previousSnapshot,
            scenario: selectedScenario,
            notes: DeviceNotesService.shared
        )
    }

    var healthScore: Int {
        healthBreakdown.total
    }

    /// Detailed score breakdown for transparency
    struct HealthBreakdown {
        let total: Int
        let baseScore: Int
        let offlinePenalty: Int
        let latencyPenalty: Int
        let portPenalty: Int
        let unknownPenalty: Int
        let offlineCount: Int
        let avgLatency: Double?
        let dangerousPortCount: Int
        let unknownCount: Int
    }

    private var avgLatencyValue: Double? {
        guard let result = scanResult else { return nil }
        let latencies = result.devices.filter { $0.isOnline && $0.latencyMs != nil }.compactMap { $0.latencyMs }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var healthBreakdown: HealthBreakdown {
        guard let result = scanResult else {
            return HealthBreakdown(total: 0, baseScore: 100, offlinePenalty: 0,
                                   latencyPenalty: 0, portPenalty: 0, unknownPenalty: 0,
                                   offlineCount: 0, avgLatency: nil, dangerousPortCount: 0, unknownCount: 0)
        }
        let online = result.devices.filter { $0.isOnline }
        if online.isEmpty {
            return HealthBreakdown(total: 0, baseScore: 100, offlinePenalty: 0,
                                   latencyPenalty: 0, portPenalty: 0, unknownPenalty: 0,
                                   offlineCount: result.devices.count, avgLatency: nil, dangerousPortCount: 0, unknownCount: 0)
        }

        // Offline penalty
        let offline = result.devices.count - online.count
        let offlinePenalty = min(offline * 2, 15)

        // Latency penalty
        let computedLatencyPenalty: Int = {
            let a = online.compactMap({ $0.latencyMs })
            if a.isEmpty { return 0 }
            let avgVal = a.reduce(0, +) / Double(a.count)
            if avgVal > 100 { return 25 }
            else if avgVal > 50 { return 15 }
            else if avgVal > 20 { return 8 }
            else if avgVal > 10 { return 3 }
            return 0
        }()

        // Port penalty
        let dangerousPorts: Set<Int> = [23, 3389, 5900, 139]
        var portPenalty = 0
        var dangerousPortCount = 0
        for d in online {
            let hits = d.openPorts.filter { dangerousPorts.contains($0) }.count
            portPenalty += hits * 3
            dangerousPortCount += hits
        }
        portPenalty = min(portPenalty, 15)

        // Unknown penalty
        let unknown = online.filter { $0.deviceType == .unknown }.count
        let unknownPenalty = min(unknown, 5)

        let total = max(0, min(100, 100 - offlinePenalty - computedLatencyPenalty - portPenalty - unknownPenalty))

        return HealthBreakdown(
            total: total,
            baseScore: 100,
            offlinePenalty: offlinePenalty,
            latencyPenalty: computedLatencyPenalty,
            portPenalty: portPenalty,
            unknownPenalty: unknownPenalty,
            offlineCount: offline,
            avgLatency: avgLatencyValue,
            dangerousPortCount: dangerousPortCount,
            unknownCount: unknown
        )
    }

    var avgLatency: Double? {
        guard let result = scanResult else { return nil }
        let online = result.devices.filter { $0.isOnline && $0.latencyMs != nil }
        if online.isEmpty { return nil }
        return online.compactMap { $0.latencyMs }.reduce(0, +) / Double(online.count)
    }

    var healthTips: [String] {
        var tips: [String] = []
        guard let result = scanResult else { return tips }
        let online = result.devices.filter { $0.isOnline }

        if result.devices.count - online.count > 3 {
            tips.append("有 \(result.devices.count - online.count) 台设备离线，检查是否正常关机或断开连接")
        }
        if let avg = avgLatency, avg > 20 {
            tips.append("平均延迟 \(String(format: "%.0f", avg))ms 偏高，检查 WiFi 信号强度或更换信道")
        }
        let unsafe = online.filter { d in
            let unsafePorts: Set<Int> = [23, 21, 3389, 5900, 139, 445]
            return !d.openPorts.filter { unsafePorts.contains($0) }.isEmpty
        }
        if !unsafe.isEmpty {
            tips.append("\(unsafe.count) 台设备开放了不安全端口（Telnet/FTP/RDP/VNC），建议关闭或限 ACL")
        }
        let unknown = online.filter { $0.deviceType == .unknown }
        if unknown.count > 2 {
            tips.append("\(unknown.count) 台设备类型未知，可能是新设备或 IoT")
        }

        return tips
    }

    func loadDemoData() {
        scanResult = ScanResult(
            devices: DemoData.makeDevices(),
            config: ScanConfig(subnet: "192.168.50", gatewayIP: "192.168.50.1",
                              localIP: "192.168.50.126", netmask: "255.255.255.0",
                              interfaceName: "en0"),
            scanDuration: 0,
            timestamp: Date()
        )
        progressValue = 1
        errorMessage = nil
    }

    func reset() {
        scanTask?.cancel()
        scanTask = nil
        scanResult = nil
        scanProgress = "准备扫描..."
        progressValue = 0
        errorMessage = nil
        isScanning = false
        selectedScenario = nil
    }

    func startScan(subnet: String? = nil, mode: ScanMode = .standard) {
        isScanning = true
        errorMessage = nil
        progressValue = 0
        self.scanMode = mode
        let startedAt = Date()
        let maxPingConcurrency = mode.pingConcurrency
        let doBonjour = mode.includesBonjour
        let doSSDP = mode.includesSSDP
        let doLatency = mode.measuresLatency

        scanTask = Task {
                var resolvedSubnet = subnet
                var localIP: String? = nil
                var netmask: String? = nil
                var gateway: String? = nil
                var iface = "en1"

                // Phase 0: Auto-detect gateway/localIP always
                scanProgress = "自动检测网络..."
                progressValue = 0.02
                if let info = NetworkScanner.detectLocalNetwork() {
                    gateway = info.gatewayIP
                    localIP = info.localIP
                    netmask = info.netmask
                    iface = info.interfaceName
                    if resolvedSubnet == nil || resolvedSubnet!.isEmpty {
                        resolvedSubnet = info.subnet
                    }
                    scanProgress = "检测到: \(info.interfaceName) / \(resolvedSubnet ?? info.subnet).0/24"
                } else {
                    if resolvedSubnet == nil { resolvedSubnet = "192.168.50" }
                    scanProgress = "未检测到网络，使用默认子网"
                }

                guard !Task.isCancelled else { return }

                let subnet = resolvedSubnet!.replacingOccurrences(of: "/24", with: "").replacingOccurrences(of: "/16", with: "")
                if gateway == nil { gateway = "\(subnet).1" }
                if localIP == nil { localIP = "\(subnet).126" }
                if netmask == nil { netmask = "255.255.255.0" }

                // Phase 1: Ping sweep
                scanProgress = "Ping 扫描 \(subnet).0/24..."
                progressValue = 0.05

                let pingResults = await Task.detached {
                    NetworkScanner.pingSweep(subnet: subnet, skipIPs: [gateway!, localIP!], maxConcurrent: maxPingConcurrency)
                }.value

                guard !Task.isCancelled else { return }

                scanProgress = "发现 \(pingResults.count + 1) 台在线设备"
                progressValue = 0.25

                // Phase 2: ARP table (MAC addresses)
                scanProgress = "获取 MAC 地址..."
                progressValue = 0.30
                let arpEntries = await Task.detached { NetworkScanner.arpTable() }.value

                guard !Task.isCancelled else { return }

                // Create a map: IP -> (mac, vendor, hostname)
                var ipToMac = [String: String]()
                var ipToVendor = [String: String]()
                var ipToHostname = [String: String]()
                for entry in arpEntries {
                    ipToMac[entry.ip] = entry.mac
                    if let vendor = NetworkScanner.lookupVendor(mac: entry.mac) {
                        ipToVendor[entry.ip] = vendor
                    }
                    if let host = entry.hostname {
                        ipToHostname[entry.ip] = host
                    }
                }
                progressValue = 0.35

                var ipToBonjour = [String: [String]]()
                var ipToSSDPType = [String: DeviceType]()
                var ipToSSDPServer = [String: String]()

                // Phase 3: mDNS/Bonjour
                if doBonjour {
                    scanProgress = "扫描 mDNS 服务..."
                    progressValue = 0.40
                    let bonjour = await Task.detached { NetworkScanner.bonjourScan(interface: iface) }.value

                    guard !Task.isCancelled else { return }

                    for svc in bonjour {
                        if !svc.ip.isEmpty {
                            ipToBonjour[svc.ip, default: []].append(svc.type)
                        }
                    }
                }
                progressValue = 0.50

                // Phase 3.5: SSDP / UPnP discovery
                if doSSDP {
                    scanProgress = "SSDP 设备发现..."
                    progressValue = 0.52
                    let ssdpResponses = await Task.detached { NetworkScanner.ssdpScan() }.value

                    guard !Task.isCancelled else { return }

                    for resp in ssdpResponses {
                        if let type = NetworkScanner.classifySSDP(resp) {
                            ipToSSDPType[resp.ip] = type
                        }
                        if !resp.server.isEmpty {
                            ipToSSDPServer[resp.ip] = resp.server
                        }
                    }
                }

                // Phase 4: Port scan + build devices
                let allIPs = [gateway!] + pingResults.map { $0.ip }.filter { $0 != gateway! }

                // Merge ARP-discovered devices that didn't respond to ping
                var arpOnlyIPs = [String]()
                for entry in arpEntries where entry.mac != "(incomplete)" {
                    let entryIP = entry.ip
                    if !allIPs.contains(entryIP) && entryIP != localIP! {
                        arpOnlyIPs.append(entryIP)
                    }
                }
                // Add ARP-only IPs, will mark them as possibly offline
                let allIPsWithARP = allIPs + arpOnlyIPs
                var devices = [NetworkDevice]()
                let total = allIPsWithARP.count

                for (idx, ip) in allIPsWithARP.enumerated() {
                    guard !Task.isCancelled else { return }

                    let isARPOnly = arpOnlyIPs.contains(ip)
                    scanProgress = "端口扫描 \(idx+1)/\(total) - \(ip)"
                    progressValue = 0.50 + 0.45 * Float(idx+1) / Float(total)

                    let mac = ipToMac[ip]
                    let vendor = ipToVendor[ip]
                    let ports: [Int]
                    if isARPOnly {
                        ports = await Task.detached { NetworkScanner.checkKeyPorts(ip: ip) }.value
                    } else {
                        ports = await Task.detached { NetworkScanner.checkPorts(ip: ip, mode: mode) }.value
                    }
                    let bonjourTypes = ipToBonjour[ip] ?? []
                    let hostname: String? = ip == gateway! ? "网关"
                        : pingResults.first(where: { $0.ip == ip })?.hostname
                        ?? ipToHostname[ip]

                    let guessedType = NetworkScanner.guessDevice(
                        ip: ip, mac: mac, vendor: vendor,
                        hostname: hostname, ports: ports, bonjourServices: bonjourTypes
                    )
                    let type: DeviceType
                    if guessedType == .unknown, let ssdpType = ipToSSDPType[ip] {
                        type = ssdpType
                    } else {
                        type = guessedType
                    }
                    let finalType = ip == gateway! ? .router : type

                    // ── Discovery sources ──
                    var sources: [DiscoverySource] = []
                    if ip == gateway! { sources.append(.gateway) }
                    if ip == localIP! { sources.append(.localDevice) }
                    if let _ = ipToMac[ip] { sources.append(.arp) }
                    if pingResults.contains(where: { $0.ip == ip }) { sources.append(.ping) }
                    if !bonjourTypes.isEmpty { sources.append(.bonjour) }
                    if let _ = ipToSSDPType[ip] { sources.append(.ssdp) }
                    if !ports.isEmpty { sources.append(.portScan) }
                    if let _ = mac { sources.append(.oui) }
                    if hostname != nil && hostname != "网关" { sources.append(.reverseDNS) }

                    // ── Identification evidence ──
                    var evidence: [String] = []
                    if let v = vendor { evidence.append("OUI 识别: \(v)") }
                    if !bonjourTypes.isEmpty { evidence.append("Bonjour: \(bonjourTypes.joined(separator: ", "))") }
                    if let ssdpType = ipToSSDPType[ip] { evidence.append("SSDP 自报: \(ssdpType.rawValue)") }
                    if let hn = hostname, hn != "网关" { evidence.append("主机名: \(hn)") }
                    if !ports.isEmpty { evidence.append("开放端口: \(ports.map(String.init).joined(separator: ", "))") }
                    if guessedType != finalType {
                        evidence.append("类型修正: \(guessedType.rawValue) → \(finalType.rawValue)")
                    }

                    // ── Confidence ──
                    let confidence: IdentificationConfidence
                    if finalType == .unknown || finalType == .iot {
                        // Unknown / IoT needs multiple sources to be trusted
                        confidence = sources.count >= 3 ? .medium : .low
                    } else if finalType == .router {
                        confidence = .high  // Gateway is definitive
                    } else if let _ = ipToSSDPType[ip] {
                        confidence = .high  // SSDP self-report is definitive
                    } else if sources.count >= 4 {
                        confidence = .high
                    } else if sources.count >= 2 {
                        confidence = .medium
                    } else {
                        confidence = .low
                    }

                    // ── Risk level ──
                    let dangerousPorts = ports.filter { [23, 3389, 5900, 5985, 5986, 22].contains($0) }
                    let riskLevel: RiskLevel
                    let riskNotes: [String]
                    if !dangerousPorts.isEmpty {
                        riskLevel = .high
                        riskNotes = dangerousPorts.map { "高风险端口 \($0) 开放" }
                    } else if ports.contains(where: { [445, 139, 135, 548].contains($0) }) {
                        riskLevel = .medium
                        riskNotes = ["文件共享端口开放"]
                    } else {
                        riskLevel = .low
                        riskNotes = []
                    }

                    devices.append(NetworkDevice(
                        id: UUID(), ipAddress: ip, macAddress: mac, hostname: hostname,
                        vendor: vendor, deviceType: finalType, openPorts: ports,
                        isOnline: !isARPOnly, isGateway: ip == gateway!,
                        isLocalDevice: ip == localIP!,
                        discoverySources: sources,
                        identificationConfidence: confidence,
                        identificationEvidence: evidence,
                        riskLevel: riskLevel,
                        riskNotes: riskNotes
                    ))
                }

                guard !Task.isCancelled else { return }

                let config = ScanConfig(subnet: subnet, gatewayIP: gateway!, localIP: localIP!,
                                        netmask: netmask!, interfaceName: iface)
                scanResult = ScanResult(devices: devices, config: config, scanDuration: Date().timeIntervalSince(startedAt), timestamp: Date())

                // Phase 5: Measure latency for online devices
                var updated = devices
                if doLatency {
                    scanProgress = "测量延迟..."
                    progressValue = 0.96
                    let onlineCount = updated.filter { $0.isOnline }.count
                    for i in updated.indices where updated[i].isOnline {
                        guard !Task.isCancelled else { return }
                        progressValue = 0.96 + 0.04 * Float(i + 1) / Float(max(onlineCount, 1))
                        scanProgress = "延迟测试 \(i+1)/\(onlineCount) - \(updated[i].ipAddress)"
                        updated[i].latencyMs = await Task.detached(operation: { NetworkScanner.measureLatency(ip: updated[i].ipAddress) }).value
                    }
                    guard !Task.isCancelled else { return }
                }
                scanResult = ScanResult(devices: updated, config: config, scanDuration: Date().timeIntervalSince(startedAt), timestamp: Date())

                scanProgress = "扫描完成：\(devices.count) 台设备"
                progressValue = 1
                isScanning = false

                // Save to history for comparison next time
                if let result = scanResult {
                    ScanHistoryService.shared.save(result)
                }
        }
    }
}
