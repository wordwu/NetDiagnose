import Foundation

struct DiagnosticFinding: Identifiable, Codable, Equatable {
    enum Severity: String, Codable, CaseIterable {
        case good = "正常"
        case info = "提示"
        case warning = "注意"
        case critical = "高风险"
    }

    let id: UUID
    var severity: Severity
    var title: String
    var explanation: String
    var action: String
    var affectedIPs: [String]

    init(id: UUID = UUID(), severity: Severity, title: String, explanation: String, action: String, affectedIPs: [String] = []) {
        self.id = id
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.action = action
        self.affectedIPs = affectedIPs
    }
}

enum NetworkScenario: String, Codable, CaseIterable, Identifiable {
    case home = "家庭"
    case office = "小办公室"
    case event = "公司"
    case hotel = "酒店/工程"

    var id: String { rawValue }

    var focus: String {
        switch self {
        case .home: return "陌生设备、智能家居、弱风险端口"
        case .office: return "NAS、打印机、共享端口、远程桌面"
        case .event: return "网关、DNS、延迟、异常蹭网设备、VPN 暴露"
        case .hotel: return "网关、摄像头、打印机、内网暴露服务"
        }
    }
}

struct DeviceSnapshot: Codable, Equatable, Identifiable {
    var id: String { ipAddress }
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    var vendor: String?
    var deviceType: DeviceType
    var openPorts: [Int]
    var isGateway: Bool
    var isLocalDevice: Bool
    var isStealth: Bool = false
    var riskLevel: RiskLevel
    var latencyMs: Double?

    init(device: NetworkDevice) {
        ipAddress = device.ipAddress
        macAddress = device.macAddress
        hostname = device.hostname
        vendor = device.vendor
        deviceType = device.deviceType
        openPorts = device.openPorts
        isGateway = device.isGateway
        isLocalDevice = device.isLocalDevice
        isStealth = device.isStealth
        riskLevel = device.riskLevel
        latencyMs = device.latencyMs
    }

    enum CodingKeys: String, CodingKey {
        case ipAddress, macAddress, hostname, vendor, deviceType, openPorts
        case isGateway, isLocalDevice, isStealth, riskLevel, latencyMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ipAddress = try c.decode(String.self, forKey: .ipAddress)
        macAddress = try c.decodeIfPresent(String.self, forKey: .macAddress)
        hostname = try c.decodeIfPresent(String.self, forKey: .hostname)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor)
        deviceType = try c.decode(DeviceType.self, forKey: .deviceType)
        openPorts = try c.decode([Int].self, forKey: .openPorts)
        isGateway = try c.decode(Bool.self, forKey: .isGateway)
        isLocalDevice = try c.decode(Bool.self, forKey: .isLocalDevice)
        isStealth = try c.decodeIfPresent(Bool.self, forKey: .isStealth) ?? false
        riskLevel = try c.decode(RiskLevel.self, forKey: .riskLevel)
        latencyMs = try c.decodeIfPresent(Double.self, forKey: .latencyMs)
    }
}

struct ScanSnapshot: Codable {
    var timestamp: Date
    var subnet: String
    var devices: [DeviceSnapshot]
}

struct ScanDiff {
    var newDevices: [NetworkDevice]
    var missingDevices: [DeviceSnapshot]
    var changedDevices: [(device: NetworkDevice, previousPorts: [Int], currentPorts: [Int])]

    var hasChanges: Bool {
        !newDevices.isEmpty || !missingDevices.isEmpty || !changedDevices.isEmpty
    }
}
