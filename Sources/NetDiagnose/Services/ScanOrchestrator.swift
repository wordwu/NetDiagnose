import Foundation
import SwiftUI

@MainActor
class ScanOrchestrator: ObservableObject {
    @Published var scanResult: ScanResult? = nil
    @Published var scanProgress: String = "准备扫描..."
    @Published var progressValue: Float = 0
    @Published var isScanning: Bool = false
    @Published var errorMessage: String? = nil
    @Published var healthScore: Int = 0
    @Published var healthTips: [String] = []

    private var scanTask: Task<Void, Never>?

    func reset() {
        scanTask?.cancel()
        scanTask = nil
        scanResult = nil
        scanProgress = "准备扫描..."
        progressValue = 0
        errorMessage = nil
        isScanning = false
        healthScore = 0
        healthTips = []
    }

    func startScan() {
        guard scanTask == nil else { return }
        isScanning = true
        errorMessage = nil
        progressValue = 0
        scanResult = nil

        scanTask = Task {
            let t0 = Date()
            do {
                var subnet = "", localIP = "127.0.0.1", netmask = "255.255.255.0"
                var gateway = "192.168.1.1", iface = "en0"

                // Phase 0: Detect network
                scanProgress = "自动检测网络..."
                progressValue = 0.02
                let networkInfo = await Task.detached {
                    NetworkScanner.detectLocalNetwork()
                }.value
                if let info = networkInfo {
                    subnet = info.subnet
                    localIP = info.localIP
                    netmask = info.netmask
                    gateway = info.gatewayIP
                    iface = info.interfaceName
                    scanProgress = "检测到: \(info.interfaceName) / \(subnet).0/24"
                } else {
                    scanProgress = "未检测到网络，使用默认子网"
                }
                try Task.checkCancellation()

                // Phase 1: Ping sweep with latency
                scanProgress = "Ping 扫描 \(subnet).0/24..."
                progressValue = 0.05
                let pingResults = await Task.detached {
                    NetworkScanner.pingSweep(subnet: subnet, skipIPs: [gateway, localIP])
                }.value
                progressValue = 0.25
                try Task.checkCancellation()

                // ★ 测量每台设备的延迟
                scanProgress = "测量延迟..."
                var ipLatency = [String: Double]()
                for (idx, result) in pingResults.enumerated() {
                    if idx % 8 == 0 { try Task.checkCancellation() }
                    progressValue = 0.25 + 0.15 * Float(idx+1) / Float(max(pingResults.count, 1))
                    if let lat = await Task.detached(operation: { NetworkScanner.measureLatency(ip: result.ip) }).value {
                        ipLatency[result.ip] = lat
                    }
                }
                // Also measure gateway
                if let lat = await Task.detached(operation: { NetworkScanner.measureLatency(ip: gateway) }).value {
                    ipLatency[gateway] = lat
                }

                scanProgress = "发现 \(pingResults.count + 1) 台在线设备"
                progressValue = 0.40
                try Task.checkCancellation()

                // Phase 2: ARP table
                scanProgress = "获取 MAC 地址..."
                let arpEntries = await Task.detached { NetworkScanner.arpTable() }.value
                var ipToMac = [String: String]()
                var ipToVendor = [String: String]()
                for entry in arpEntries {
                    ipToMac[entry.ip] = entry.mac
                    if let vendor = NetworkScanner.lookupVendor(mac: entry.mac) {
                        ipToVendor[entry.ip] = vendor
                    }
                }
                progressValue = 0.50
                try Task.checkCancellation()

                // Phase 3: mDNS
                scanProgress = "扫描 mDNS 服务..."
                let bonjour = await Task.detached { NetworkScanner.bonjourScan(interface: iface) }.value
                var ipToBonjour = [String: [String]]()
                for svc in bonjour {
                    if !svc.ip.isEmpty {
                        ipToBonjour[svc.ip, default: []].append(svc.type)
                    }
                }
                progressValue = 0.60
                try Task.checkCancellation()

                // Phase 4: Port scan + build devices
                var allIPs = [gateway] + pingResults.map { $0.ip }
                // Merge ARP-discovered non-ping devices
                for entry in arpEntries where entry.mac != "(incomplete)" {
                    let entryIP = entry.ip
                    if !allIPs.contains(entryIP) && entryIP != localIP {
                        allIPs.append(entryIP)
                    }
                }

                var devices = [NetworkDevice]()
                let total = allIPs.count

                for (idx, ip) in allIPs.enumerated() {
                    if idx % 3 == 0 { try Task.checkCancellation() }
                    let isOffline = ip != gateway && !pingResults.contains(where: { $0.ip == ip })
                    scanProgress = "端口扫描 \(idx+1)/\(total) - \(ip)"
                    progressValue = 0.60 + 0.30 * Float(idx+1) / Float(total)

                    let mac = ipToMac[ip]
                    let vendor = ipToVendor[ip]
                    let ports: [Int] = isOffline ? [] : await Task.detached { NetworkScanner.checkPorts(ip: ip) }.value
                    let bonjourTypes = ipToBonjour[ip] ?? []

                    let hostname: String? = ip == gateway ? "网关"
                        : pingResults.first(where: { $0.ip == ip })?.hostname

                    let type = NetworkScanner.guessDevice(
                        ip: ip, mac: mac, vendor: vendor,
                        hostname: hostname, ports: ports, bonjourServices: bonjourTypes
                    )

                    devices.append(NetworkDevice(
                        id: UUID(), ipAddress: ip, macAddress: mac, hostname: hostname,
                        vendor: vendor, deviceType: ip == gateway ? .router : type,
                        openPorts: ports, isOnline: !isOffline, isGateway: ip == gateway,
                        isLocalDevice: ip == localIP,
                        latencyMs: ipLatency[ip]
                    ))
                }

                // ★ Health score
                let score = computeHealthScore(devices: devices, gateway: gateway, localIP: localIP)
                healthScore = score.0
                healthTips = score.1

                let config = ScanConfig(subnet: subnet, gatewayIP: gateway, localIP: localIP,
                                        netmask: netmask, interfaceName: iface)
                let duration = Date().timeIntervalSince(t0)
                scanResult = ScanResult(devices: devices, config: config, scanDuration: duration,
                                       timestamp: Date(), healthScore: healthScore)
                scanProgress = "扫描完成：\(devices.count) 台设备 · 评分 \(healthScore)/100"
                progressValue = 1
                isScanning = false
                scanTask = nil
            } catch is CancellationError {
                scanProgress = "扫描已停止"
                isScanning = false
                scanTask = nil
            } catch {
                errorMessage = error.localizedDescription
                isScanning = false
                scanTask = nil
            }
        }
    }

    // MARK: - Health Score

    private func computeHealthScore(devices: [NetworkDevice], gateway: String, localIP: String) -> (Int, [String]) {
        var score = 100
        var tips = [String]()

        let onlineDevices = devices.filter(\.isOnline)
        let offlineDevices = devices.filter { !$0.isOnline }
        let latencies = devices.compactMap(\.latencyMs)

        // Gateway latency
        if let gwLat = devices.first(where: { $0.isGateway })?.latencyMs {
            if gwLat > 50 { score -= 15; tips.append("⚠️ 网关延迟偏高 (\(String(format: "%.0f", gwLat))ms)，建议重启路由器") }
            else if gwLat > 20 { score -= 5; tips.append("网关延迟 \(String(format: "%.0f", gwLat))ms，尚可接受") }
        } else {
            score -= 20; tips.append("⚠️ 未检测到网关设备")
        }

        // Average latency
        if !latencies.isEmpty {
            let avg = latencies.reduce(0, +) / Double(latencies.count)
            if avg > 100 { score -= 20; tips.append("⚠️ 平均延迟过高 (\(String(format: "%.0f", avg))ms)，网络可能拥塞") }
            else if avg > 50 { score -= 10; tips.append("平均延迟 \(String(format: "%.0f", avg))ms，网络负载较重") }
        }

        // Offline devices (ARP-only)
        if offlineDevices.count > 0 {
            score -= min(offlineDevices.count * 3, 15)
            tips.append("\(offlineDevices.count) 台设备离线（\(offlineDevices.prefix(3).map(\.ipAddress).joined(separator: "、"))…）")
        }

        // Open risky ports
        let riskyDevices = devices.filter { d in
            d.openPorts.contains(where: { [23, 21, 3389].contains($0) })
        }
        if !riskyDevices.isEmpty {
            score -= min(riskyDevices.count * 5, 15)
            tips.append("⚠️ \(riskyDevices.count) 台设备开放了不安全端口（Telnet/FTP/RDP），建议关闭")
        }

        // Too many unknown devices
        let unknownCount = devices.filter { $0.deviceType == .unknown }.count
        if unknownCount > devices.count / 2 {
            score -= 5
            tips.append("\(unknownCount) 台设备类型未识别，建议更新设备清单")
        }

        // Device count is reasonable
        if onlineDevices.count > 50 {
            score -= 5
            tips.append("在线设备数 (\(onlineDevices.count)) 较多，建议考虑网络分段")
        }

        return (max(score, 0), tips)
    }
}
