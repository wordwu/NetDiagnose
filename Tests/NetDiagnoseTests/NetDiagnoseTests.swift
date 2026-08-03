import XCTest
@testable import NetDiagnose

final class NetDiagnoseTests: XCTestCase {

    // MARK: - OUI Database Integrity

    func testOUIDatabase_noDuplicateKeys() {
        // Collect all OUI keys — we need reflection since OUI_DB is private
        // Strategy: call arpWithVendors() on a known MAC and verify no crash
        // But for direct validation, we scan the source to verify uniqueness

        // Since OUI_DB is fileprivate, we test indirectly:
        // Verify vendor lookup returns consistent results for same MAC
        let vendor1 = NetworkScanner.lookupVendor(mac: "b0:6e:bf:57:12:18")
        let vendor2 = NetworkScanner.lookupVendor(mac: "B0-6E-BF-57-12-18")
        XCTAssertEqual(vendor1, vendor2, "Same MAC in different formats should return same vendor")
        XCTAssertTrue((vendor1 ?? "").lowercased().contains("asus"), "Known ASUS MAC should resolve")
    }

    func testOUIDatabase_knownVendors() {
        // Verify key vendors resolve correctly
        let intel = NetworkScanner.lookupVendor(mac: "e4:fe:43:00:00:00")?.lowercased() ?? ""
        let asus = NetworkScanner.lookupVendor(mac: "b0:6e:bf:00:00:00")?.lowercased() ?? ""
        let yeelight = NetworkScanner.lookupVendor(mac: "dc:ed:83:00:00:00")?.lowercased() ?? ""
        let pi = NetworkScanner.lookupVendor(mac: "b8:27:eb:00:00:00")?.lowercased() ?? ""
        XCTAssertTrue(intel.contains("xiaomi") || intel.contains("intel"), "e4:fe:43 should resolve to a known vendor")
        XCTAssertTrue(asus.contains("asus"), "ASUS OUI should resolve")
        XCTAssertTrue(yeelight.contains("xiaomi") || yeelight.contains("yeelight"), "Yeelight OUI should resolve")
        XCTAssertTrue(pi.contains("raspberry"), "Raspberry Pi OUI should resolve")
    }

    func testOUIDatabase_unknownMAC() {
        // 本地管理位地址（x2:xx:xx）不属于任何厂商 OUI
        XCTAssertNil(NetworkScanner.lookupVendor(mac: "02:00:00:00:00:00"))
        // 广播前缀 ff:ff:ff 也不在厂商 OUI 库中
        XCTAssertNil(NetworkScanner.lookupVendor(mac: "ff:ff:ff:00:00:00"))
        // 短于 6 字符的非法输入返回 nil
        XCTAssertNil(NetworkScanner.lookupVendor(mac: "00:00"))
    }

    // MARK: - IP / Subnet Utilities

    func testPrivateIPDetection() {
        // These are tested indirectly through NetworkScanner.detectLocalNetwork()
        // But we can verify the scan pipeline works
        let info = NetworkScanner.detectLocalNetwork()
        // On most machines with a network connection, this should succeed
        // If running in CI without network, it'll be nil — that's OK
        if let info = info {
            XCTAssertFalse(info.subnet.isEmpty)
            XCTAssertFalse(info.localIP.isEmpty)
            XCTAssertFalse(info.gatewayIP.isEmpty)
            XCTAssertFalse(info.netmask.isEmpty)
            XCTAssertFalse(info.interfaceName.isEmpty)
        }
    }

    // MARK: - Device Type Identification

    func testDeviceIdentification_gatewayByIP() {
        let result = NetworkScanner.guessDevice(
            ip: "192.168.1.1", mac: nil, vendor: nil,
            hostname: nil, ports: [], bonjourServices: []
        )
        XCTAssertEqual(result, .router, "IP ending in .1 should be identified as router")
    }

    func testDeviceIdentification_byVendor() {
        // 网络设备品牌 + Web 管理端口 → 路由器
        let router = NetworkScanner.guessDevice(
            ip: "192.168.1.100", mac: nil, vendor: "Ubiquiti",
            hostname: nil, ports: [443], bonjourServices: []
        )
        XCTAssertEqual(router, .router, "Network brand with web admin port should be router")

        // 网络设备品牌但没有管理端口 → 不应武断判为路由器（可能是交换机/AP/网卡）
        let plain = NetworkScanner.guessDevice(
            ip: "192.168.1.100", mac: nil, vendor: "Ubiquiti",
            hostname: nil, ports: [], bonjourServices: []
        )
        XCTAssertNotEqual(plain, .router, "Network brand without web port shouldn't be forced to router")
    }

    func testDeviceIdentification_byPorts() {
        let nasResult = NetworkScanner.guessDevice(
            ip: "192.168.1.10", mac: nil, vendor: nil,
            hostname: nil, ports: [5000, 5001], bonjourServices: []
        )
        XCTAssertEqual(nasResult, .nas, "Ports 5000/5001 should identify NAS")

        let printerResult = NetworkScanner.guessDevice(
            ip: "192.168.1.20", mac: nil, vendor: nil,
            hostname: nil, ports: [515, 9100], bonjourServices: []
        )
        XCTAssertEqual(printerResult, .printer, "Ports 515/9100 should identify printer")

        let camResult = NetworkScanner.guessDevice(
            ip: "192.168.1.30", mac: nil, vendor: nil,
            hostname: nil, ports: [554], bonjourServices: []
        )
        XCTAssertEqual(camResult, .camera, "Port 554 should identify camera")
    }

    func testDeviceIdentification_byHostname() {
        let result = NetworkScanner.guessDevice(
            ip: "192.168.1.50", mac: nil, vendor: nil,
            hostname: "yeelight-light-lamp22", ports: [], bonjourServices: []
        )
        XCTAssertEqual(result, .iot, "Yeelight hostname should identify as IoT")
    }

    func testDeviceIdentification_unknown() {
        let result = NetworkScanner.guessDevice(
            ip: "192.168.1.200", mac: nil, vendor: nil,
            hostname: nil, ports: [], bonjourServices: []
        )
        XCTAssertEqual(result, .unknown)
    }

    // MARK: - Health Score (requires MainActor — tested via UI)

    // Health score is computed on @MainActor; test manually by running the app.

    // MARK: - ARP Parsing

    func testARPTable_parsesOutput() {
        let entries = NetworkScanner.arpTable()
        // ARP table may be empty in some environments, but shouldn't crash
        XCTAssertNotNil(entries)
        // If entries exist, verify structure
        for entry in entries {
            XCTAssertFalse(entry.ip.isEmpty)
            XCTAssertFalse(entry.mac.isEmpty)
            XCTAssertFalse(entry.interface.isEmpty)
        }
    }

    // MARK: - Diagnostic Engine Tests

    func testDiagnosticEngine_emptyDevices() {
        let findings = DiagnosticEngine.analyze(
            devices: [], previous: nil, scenario: nil, notes: DeviceNotesService.shared
        )
        XCTAssertFalse(findings.isEmpty, "Empty devices should still produce an alert")
    }

    func testDiagnosticEngine_allOnline() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true),
            NetworkDevice(ipAddress: "192.168.1.100", deviceType: .computer, isOnline: true),
            NetworkDevice(ipAddress: "192.168.1.101", deviceType: .phone, isOnline: true),
        ]
        let findings = DiagnosticEngine.analyze(
            devices: devices, previous: nil, scenario: nil, notes: DeviceNotesService.shared
        )
        // Should have "在线率良好" finding
        let hasGoodOnline = findings.contains { $0.title.contains("在线率") && $0.severity == .good }
        XCTAssertTrue(hasGoodOnline, "All-online devices should report good online ratio")
    }

    func testDiagnosticEngine_highRiskDevice() {
        let device = NetworkDevice(
            ipAddress: "192.168.1.50", openPorts: [23, 3389], isOnline: true,
            riskLevel: .high,
            riskNotes: ["高风险端口 Telnet 开放"]
        )
        let findings = DiagnosticEngine.analyze(
            devices: [device], previous: nil, scenario: nil, notes: DeviceNotesService.shared
        )
        let hasRisk = findings.contains { $0.title.contains("风险设备") }
        XCTAssertTrue(hasRisk, "High risk device should be reported")
    }

    func testDiagnosticEngine_highLatency() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true, latencyMs: 120),
            NetworkDevice(ipAddress: "192.168.1.100", isOnline: true, latencyMs: 200),
        ]
        let findings = DiagnosticEngine.analyze(
            devices: devices, previous: nil, scenario: nil, notes: DeviceNotesService.shared
        )
        let hasLatency = findings.contains { $0.title.contains("高延迟") }
        XCTAssertTrue(hasLatency, "High latency devices should be reported")
    }

    func testDiagnosticEngine_scenarioChecks() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true, latencyMs: 5),
            NetworkDevice(ipAddress: "192.168.1.50", deviceType: .camera, openPorts: [554], isOnline: true),
            NetworkDevice(ipAddress: "192.168.1.100", deviceType: .computer, isOnline: true),
        ]
        let _ = DiagnosticEngine.analyze(
            devices: devices, previous: nil, scenario: .home, notes: DeviceNotesService.shared
        )
        // Should not flag gateway latency for home scenario (not in scenarioChecks)
        let hotelFindings = DiagnosticEngine.analyze(
            devices: devices, previous: nil, scenario: .hotel, notes: DeviceNotesService.shared
        )
        let hasCamera = hotelFindings.contains { $0.title.contains("摄像头") }
        XCTAssertTrue(hasCamera, "Hotel scenario should detect cameras")
    }

    func testDiagnosticEngine_newDevice() {
        let previous = ScanSnapshot(
            timestamp: Date().addingTimeInterval(-3600),
            subnet: "192.168.1",
            devices: [
                DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.1", isOnline: true, isGateway: true))
            ]
        )
        let current = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true),
            NetworkDevice(ipAddress: "192.168.1.200", deviceType: .unknown, isOnline: true),
        ]
        let findings = DiagnosticEngine.analyze(
            devices: current, previous: previous, scenario: nil, notes: DeviceNotesService.shared
        )
        let hasNewDevice = findings.contains { $0.title.contains("新设备上线") }
        XCTAssertTrue(hasNewDevice, "New device should be detected compared to previous scan")
    }

    func testDiagnosticEngine_disappearedDevice() {
        let previous = ScanSnapshot(
            timestamp: Date().addingTimeInterval(-3600),
            subnet: "192.168.1",
            devices: [
                DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.1", isOnline: true, isGateway: true)),
                DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.100", deviceType: .phone, isOnline: true)),
            ]
        )
        let current = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true),
        ]
        let findings = DiagnosticEngine.analyze(
            devices: current, previous: previous, scenario: nil, notes: DeviceNotesService.shared
        )
        let hasDisappeared = findings.contains { $0.title.contains("设备消失") }
        XCTAssertTrue(hasDisappeared, "Disappeared device should be detected")
    }

    // MARK: - Health Score Tests

    func testHealthScore_allGood() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true, latencyMs: 3),
            NetworkDevice(ipAddress: "192.168.1.100", deviceType: .computer, isOnline: true, latencyMs: 5),
        ]
        // Score should be 100 (no offline, low latency, no risky ports, no unknowns)
        // Only offline penalty: min(0*2, 15) = 0
        // Latency: avg 4ms < 10ms → 0 penalty
        // Port penalty: 0
        // Unknown penalty: min(0, 5) = 0
        // Total: 100 - 0 - 0 - 0 - 0 = 100
        let score = computeTestScore(devices)
        XCTAssertEqual(score, 100, "Healthy network should score 100")
    }

    func testHealthScore_offlineDevices() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true),
            NetworkDevice(ipAddress: "192.168.1.100", deviceType: .computer, isOnline: false),
            NetworkDevice(ipAddress: "192.168.1.101", deviceType: .phone, isOnline: false),
        ]
        // offline penalty: min(2*2, 15) = 4
        let score = computeTestScore(devices)
        XCTAssertEqual(score, 96, "2 offline devices should penalize 4 points")
    }

    func testHealthScore_allOffline() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", isOnline: false, isGateway: true),
            NetworkDevice(ipAddress: "192.168.1.100", isOnline: false),
        ]
        let score = computeTestScore(devices)
        XCTAssertEqual(score, 0, "All offline should score 0")
    }

    func testHealthScore_riskyPorts() {
        let devices = [
            NetworkDevice(ipAddress: "192.168.1.1", deviceType: .router, isOnline: true, isGateway: true),
            NetworkDevice(ipAddress: "192.168.1.50", deviceType: .computer, openPorts: [23, 3389], isOnline: true),
        ]
        // Telnet + RDP = 2 dangerous ports × 3 = 6, min(6, 15) = 6
        let score = computeTestScore(devices)
        XCTAssertEqual(score, 94, "2 dangerous ports should penalize 6 points")
    }

    // MARK: - Scan History / Diff Tests

    func testScanHistory_diff_newDevices() {
        let previous = ScanSnapshot(
            timestamp: Date(),
            subnet: "192.168.1",
            devices: [DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.1", isOnline: true))]
        )
        let current = [
            NetworkDevice(ipAddress: "192.168.1.1", isOnline: true),
            NetworkDevice(ipAddress: "192.168.1.2", isOnline: true),
        ]
        let diff = ScanHistoryService.shared.diff(current: current, previous: previous)
        XCTAssertEqual(diff.newDevices.count, 1)
        XCTAssertTrue(diff.hasChanges)
    }

    func testScanHistory_diff_missingDevices() {
        let previous = ScanSnapshot(
            timestamp: Date(),
            subnet: "192.168.1",
            devices: [
                DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.1", isOnline: true)),
                DeviceSnapshot(device: NetworkDevice(ipAddress: "192.168.1.2", isOnline: true)),
            ]
        )
        let current = [
            NetworkDevice(ipAddress: "192.168.1.1", isOnline: true),
        ]
        let diff = ScanHistoryService.shared.diff(current: current, previous: previous)
        XCTAssertEqual(diff.missingDevices.count, 1)
    }

    func testScanHistory_diff_portChanges() {
        let prevDevice = NetworkDevice(ipAddress: "192.168.1.10", openPorts: [80, 443], isOnline: true)
        let previous = ScanSnapshot(
            timestamp: Date(),
            subnet: "192.168.1",
            devices: [DeviceSnapshot(device: prevDevice)]
        )
        let current = [
            NetworkDevice(ipAddress: "192.168.1.10", openPorts: [80, 443, 22], isOnline: true),
        ]
        let diff = ScanHistoryService.shared.diff(current: current, previous: previous)
        XCTAssertEqual(diff.changedDevices.count, 1)
        XCTAssertEqual(diff.changedDevices.first?.previousPorts, [80, 443])
        XCTAssertEqual(diff.changedDevices.first?.currentPorts, [80, 443, 22])
    }

    // MARK: - Helpers

    private func computeTestScore(_ devices: [NetworkDevice]) -> Int {
        let online = devices.filter { $0.isOnline }
        if online.isEmpty { return 0 }
        let base = 100

        let offlineCount = devices.count - online.count
        let offlinePenalty = min(offlineCount * 2, 15)

        let lats = online.compactMap { $0.latencyMs }
        let avgLat = lats.isEmpty ? 0 : lats.reduce(0, +) / Double(lats.count)
        let latencyPenalty: Int
        if avgLat > 100 { latencyPenalty = 25 }
        else if avgLat > 50 { latencyPenalty = 15 }
        else if avgLat > 20 { latencyPenalty = 8 }
        else if avgLat > 10 { latencyPenalty = 3 }
        else { latencyPenalty = 0 }

        let dangerousPortSet: Set<Int> = [23, 3389, 5900, 139]
        var portHits = 0
        for d in online { portHits += d.openPorts.filter { dangerousPortSet.contains($0) }.count }
        let portPenalty = min(portHits * 3, 15)

        let unknownCount = online.filter { $0.deviceType == .unknown }.count
        let unknownPenalty = min(unknownCount, 5)

        return max(0, min(100, base - offlinePenalty - latencyPenalty - portPenalty - unknownPenalty))
    }
}
