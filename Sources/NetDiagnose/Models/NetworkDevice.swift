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

// MARK: - Scan Mode

enum ScanMode: String, Codable, CaseIterable, Identifiable {
    case quick = "快速"
    case standard = "标准"
    case deep = "深度"

    var id: String { rawValue }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .quick: return "ARP + Ping，速度优先"
        case .standard: return "常用服务 + 关键端口"
        case .deep: return "更多端口，识别更细"
        }
    }

    var pingConcurrency: Int {
        switch self {
        case .quick: return 48
        case .standard: return 32
        case .deep: return 24
        }
    }

    /// Max concurrent TCP port probes
    var portConcurrency: Int {
        switch self {
        case .quick: return 24
        case .standard: return 16
        case .deep: return 8
        }
    }

    /// Per-port TCP connect timeout
    var portTimeout: TimeInterval {
        switch self {
        case .quick: return 0.12
        case .standard: return 0.18
        case .deep: return 0.35
        }
    }

    var includesBonjour: Bool { self != .quick }
    var includesSSDP: Bool { self != .quick }
    var measuresLatency: Bool { self != .quick }
}

// MARK: - Identification

enum IdentificationConfidence: String, Codable, CaseIterable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var score: Int {
        switch self {
        case .high: return 90
        case .medium: return 65
        case .low: return 35
        }
    }
}

enum DiscoverySource: String, Codable, CaseIterable {
    case gateway = "网关"
    case localDevice = "本机"
    case arp = "ARP"
    case ping = "Ping"
    case reverseDNS = "反向 DNS"
    case bonjour = "Bonjour"
    case ssdp = "SSDP/UPnP"
    case portScan = "端口"
    case oui = "OUI 厂商"
    case userHint = "规则"
}

enum RiskLevel: String, Codable, CaseIterable {
    case low = "低"
    case medium = "中"
    case high = "高"

    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
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
    var latencyMs: Double?
    var discoverySources: [DiscoverySource]
    var identificationConfidence: IdentificationConfidence
    var identificationEvidence: [String]
    var riskLevel: RiskLevel
    var riskNotes: [String]

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
        latencyMs: Double? = nil,
        discoverySources: [DiscoverySource] = [],
        identificationConfidence: IdentificationConfidence = .low,
        identificationEvidence: [String] = [],
        riskLevel: RiskLevel = .low,
        riskNotes: [String] = []
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
        self.discoverySources = discoverySources
        self.identificationConfidence = identificationConfidence
        self.identificationEvidence = identificationEvidence
        self.riskLevel = riskLevel
        self.riskNotes = riskNotes
    }

    var displayName: String {
        hostname ?? bonjourName ?? ipAddress
    }

    var shortIP: String {
        ipAddress.components(separatedBy: ".").last ?? ipAddress
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

    var gateway: NetworkDevice? {
        devices.first { $0.isGateway }
    }

    var deviceCountByType: [DeviceType: Int] {
        Dictionary(grouping: devices, by: { $0.deviceType })
            .mapValues { $0.count }
    }
}
