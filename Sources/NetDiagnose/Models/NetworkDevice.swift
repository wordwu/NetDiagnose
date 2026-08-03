import Foundation
import Network

// MARK: - Device Type Enum

enum DeviceType: String, Codable, CaseIterable {
    case router      = "路由器/网关"
    case switch_     = "交换机"
    case computer    = "电脑"
    case phone       = "手机"
    case tablet      = "平板"
    case nas         = "NAS/存储"
    case printer     = "打印机"
    case iot         = "智能家居/IoT"
    case camera      = "摄像头"
    case tv          = "电视/盒子"
    case unknown     = "未识别"

    var icon: String {
        switch self {
        case .router:   return "antenna.radiowaves.left.and.right"
        case .switch_:  return "cable.connector"
        case .computer: return "desktopcomputer"
        case .phone:    return "iphone"
        case .tablet:   return "ipad"
        case .nas:      return "externaldrive"
        case .printer:  return "printer"
        case .iot:      return "homekit"
        case .camera:   return "video"
        case .tv:       return "tv"
        case .unknown:  return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .router:   return "amber"
        case .switch_:  return "orange"
        case .computer: return "cyan"
        case .phone:    return "cyan"
        case .tablet:   return "cyan"
        case .nas:      return "violet"
        case .printer:  return "slate"
        case .iot:      return "emerald"
        case .camera:   return "rose"
        case .tv:       return "blue"
        case .unknown:  return "slate"
        }
    }
}

// MARK: - Network Device Model

struct NetworkDevice: Identifiable, Codable, Equatable {
    let id: UUID
    var ipAddress: String
    var macAddress: String?
    var hostname: String?
    var bonjourName: String?
    var vendor: String?
    var deviceType: DeviceType
    var openPorts: [Int]
    var isOnline: Bool
    var isGateway: Bool
    var isLocalDevice: Bool
    var lastSeen: Date
    var osGuess: String?
    var services: [String]
    var latencyMs: Double?   // ★ 诊断工具新增：ping 延迟

    init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String? = nil,
        hostname: String? = nil,
        bonjourName: String? = nil,
        vendor: String? = nil,
        deviceType: DeviceType = .unknown,
        openPorts: [Int] = [],
        isOnline: Bool = true,
        isGateway: Bool = false,
        isLocalDevice: Bool = false,
        lastSeen: Date = Date(),
        osGuess: String? = nil,
        services: [String] = [],
        latencyMs: Double? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.bonjourName = bonjourName
        self.vendor = vendor
        self.deviceType = deviceType
        self.openPorts = openPorts
        self.isOnline = isOnline
        self.isGateway = isGateway
        self.isLocalDevice = isLocalDevice
        self.lastSeen = lastSeen
        self.osGuess = osGuess
        self.services = services
        self.latencyMs = latencyMs
    }

    var displayName: String {
        hostname ?? bonjourName ?? ipAddress
    }

    var shortIP: String {
        ipAddress.components(separatedBy: ".").last ?? ipAddress
    }

    /// 延迟评级
    var latencyGrade: LatencyGrade {
        guard let ms = latencyMs else { return .unknown }
        switch ms {
        case ..<5:   return .excellent
        case 5..<15: return .good
        case 15..<50: return .fair
        case 50..<100: return .slow
        default:     return .bad
        }
    }
}

enum LatencyGrade: String {
    case excellent = "极佳"
    case good = "良好"
    case fair = "一般"
    case slow = "较慢"
    case bad = "很差"
    case unknown = "未知"

    var color: String {
        switch self {
        case .excellent: return "emerald"
        case .good: return "green"
        case .fair: return "yellow"
        case .slow: return "orange"
        case .bad: return "rose"
        case .unknown: return "slate"
        }
    }
}

// MARK: - Scan Configuration

struct ScanConfig {
    var subnet: String = ""
    var gatewayIP: String = ""
    var localIP: String = ""
    var netmask: String = "255.255.255.0"
    var interfaceName: String = "en0"

    var cidrNotation: String {
        let parts = netmask.split(separator: ".")
        let binary = parts.map { String(UInt8($0) ?? 0, radix: 2) }.joined()
        let ones = binary.filter { $0 == "1" }.count
        return "\(subnet)/\(ones)"
    }
}

// MARK: - Scan Result

struct ScanResult {
    var devices: [NetworkDevice]
    var config: ScanConfig
    var scanDuration: TimeInterval
    var timestamp: Date
    var healthScore: Int = 0

    var gateway: NetworkDevice? {
        devices.first { $0.isGateway }
    }

    var deviceCountByType: [DeviceType: Int] {
        Dictionary(grouping: devices, by: { $0.deviceType })
            .mapValues { $0.count }
    }

    var onlineCount: Int {
        devices.filter(\.isOnline).count
    }
    
    var avgLatency: Double? {
        let lats = devices.compactMap(\.latencyMs)
        guard !lats.isEmpty else { return nil }
        return lats.reduce(0, +) / Double(lats.count)
    }
}
