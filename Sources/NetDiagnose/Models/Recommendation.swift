import Foundation

// MARK: - Equipment Recommendation

struct EquipmentRecommendation: Identifiable {
    let id = UUID()
    let category: EquipmentCategory
    let priority: Priority
    let title: String
    let reason: String
    let options: [EquipmentOption]
}

enum EquipmentCategory: String, CaseIterable {
    case router     = "路由器"
    case switch_    = "交换机"
    case ap         = "无线AP"
    case gateway    = "安全网关"
    case controller = "控制器"

    var icon: String {
        switch self {
        case .router:     return "antenna.radiowaves.left.and.right"
        case .switch_:    return "cable.connector"
        case .ap:         return "wifi"
        case .gateway:    return "shield"
        case .controller: return "server.rack"
        }
    }
}

enum Priority: String, CaseIterable {
    case critical = "紧急"
    case high     = "高"
    case medium   = "中"
    case low      = "低"
}

struct EquipmentOption: Identifiable {
    let id = UUID()
    let brand: String
    let model: String
    let tier: Tier
    let priceRange: String
    let specs: String
    let pros: [String]
    let cons: [String]
    let purchaseURL: String?
}

enum Tier: String, CaseIterable {
    case enterprise  = "企业级"
    case prosumer    = "专业级"
    case enthusiast  = "发烧友"

    var badge: String {
        switch self {
        case .enterprise: return "🏢"
        case .prosumer:   return "🏠"
        case .enthusiast: return "🔧"
        }
    }
}

// MARK: - Recommendation Engine

struct RecommendationEngine {

    static func analyze(devices: [NetworkDevice], gatewayIP: String, subnet: String) -> [EquipmentRecommendation] {
        var recommendations: [EquipmentRecommendation] = []

        let totalDevices = devices.count
        let iotDevices = devices.filter { $0.deviceType == .iot || $0.deviceType == .camera }
        let nasDevices = devices.filter { $0.deviceType == .nas }
        let hasNAS = !nasDevices.isEmpty

        // ── 路由器建议 ──
        if totalDevices > 10 {
            recommendations.append(EquipmentRecommendation(
                category: .router,
                priority: .critical,
                title: "设备数量超标，建议升级主路由",
                reason: "当前网络有 \(totalDevices) 台设备。普通家用路由器通常只能稳定支持 10-15 台设备同时在线，超出后可能出现 DHCP 耗尽、NAT 表溢出、WiFi 断连等问题。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "UniFi Cloud Gateway Ultra (UCG-Ultra)", tier: .prosumer, priceRange: "¥800-1,200", specs: "1Gbps 路由吞吐 · 30+ UniFi 设备管理 · UniFi Network 内置", pros: ["一体化路由+控制器", "App 远程管理", "颜值高"], cons: ["需要额外 AP", "无 PoE"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "MikroTik", model: "RB5009UG+S+IN", tier: .prosumer, priceRange: "¥1,200-1,600", specs: "RouterOS · 9口(1×2.5G+8×1G) · SFP+ 万兆 · PoE-out", pros: ["RouterOS 功能逆天", "万兆上联", "功耗极低 15W"], cons: ["配置复杂", "无内置 WiFi"], purchaseURL: "https://mikrotik.com"),
                    EquipmentOption(brand: "Cisco", model: "Meraki MX75", tier: .enterprise, priceRange: "¥6,000-8,000", specs: "1Gbps · 高级安全 · SD-WAN · 云端管理", pros: ["企业级安全 IPS/IDS", "Auto VPN", "7×24 云管理"], cons: ["贵", "需年付 License"], purchaseURL: "https://meraki.cisco.com"),
                ]
            ))
        } else if totalDevices > 5 {
            recommendations.append(EquipmentRecommendation(
                category: .router,
                priority: .high,
                title: "建议评估路由器承载能力",
                reason: "当前 \(totalDevices) 台设备在线，大多数家用路由器可正常工作。但若频繁遇到断流或延迟，考虑升级到专业级路由。",
                options: [
                    EquipmentOption(brand: "TP-Link", model: "ER7206", tier: .prosumer, priceRange: "¥500-800", specs: "多WAN · VPN · Omada SDN", pros: ["性价比高", "SDN 支持"], cons: ["无WiFi", "需配合AP"], purchaseURL: "https://www.tp-link.com"),
                    EquipmentOption(brand: "Ubiquiti", model: "UniFi Express", tier: .prosumer, priceRange: "¥1,000-1,500", specs: "双频 WiFi6 · 内置 UniFi Network", pros: ["小巧全能", "即插即用"], cons: ["带机量有限"], purchaseURL: "https://store.ui.com"),
                ]
            ))
        }

        // ── IoT 隔离建议 ──
        if !iotDevices.isEmpty {
            recommendations.append(EquipmentRecommendation(
                category: .switch_,
                priority: .high,
                title: "为 IoT 设备划分独立 VLAN",
                reason: "检测到 \(iotDevices.count) 台智能家居/IoT 设备。这些设备通常安全防护较弱，建议划分到独立 VLAN 中，限制其访问主网络，防止隐私泄露或被劫持后作为攻击跳板。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "USW-Lite-8-PoE", tier: .prosumer, priceRange: "¥600-900", specs: "8口千兆 · 4口PoE · VLAN · 客户端隔离", pros: ["小巧", "PoE支持", "管理方便"], cons: ["无万兆", "需配合路由"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "TP-Link", model: "TL-SG2008P", tier: .prosumer, priceRange: "¥300-500", specs: "8口千兆 · PoE · VLAN · Omada", pros: ["性价比高", "Omada管理"], cons: ["塑料壳"], purchaseURL: "https://www.tp-link.com"),
                ]
            ))
        }

        // ── NAS 网络优化 ──
        if hasNAS {
            recommendations.append(EquipmentRecommendation(
                category: .switch_,
                priority: .medium,
                title: "为 NAS 独立组网优化存储性能",
                reason: "检测到 NAS 设备。建议为 NAS 配置独立千兆/2.5G 交换机，并启用链路聚合(802.3ad)以提升多用户并发访问速度。避免经路由器 NAT 转发影响性能。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "USW-Flex-XG", tier: .prosumer, priceRange: "¥2,000-2,800", specs: "4口万兆 · PoE-in · 户外可用", pros: ["万兆速度", "小巧", "PoE供电"], cons: ["贵", "无网管"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "TP-Link", model: "TL-SG108-M2", tier: .prosumer, priceRange: "¥500-800", specs: "8口2.5G · 即插即用", pros: ["2.5G实惠", "8口"], cons: ["无网管", "无PoE"], purchaseURL: "https://www.tp-link.com"),
                ]
            ))
        }

        // ── 无线覆盖建议 ──
        recommendations.append(EquipmentRecommendation(
            category: .ap,
            priority: .medium,
            title: "考虑部署独立无线 AP 提升覆盖",
            reason: "如果当前 WiFi 存在盲区或速度不达标，建议在主路由之外部署专用 AP，实现全屋无缝漫游。",
            options: [
                EquipmentOption(brand: "Ubiquiti", model: "UniFi U6 Pro", tier: .prosumer, priceRange: "¥1,000-1,400", specs: "WiFi6 · 4×4 MU-MIMO · OFDMA · PoE", pros: ["信号强劲", "无缝漫游", "颜值高"], cons: ["需PoE交换机", "价格不低"], purchaseURL: "https://store.ui.com"),
                EquipmentOption(brand: "TP-Link", model: "EAP670", tier: .prosumer, priceRange: "¥500-800", specs: "WiFi6 · AX5400 · 2.5G上联 · PoE", pros: ["性价比极高", "2.5G口"], cons: ["App体验一般"], purchaseURL: "https://www.tp-link.com"),
            ]
        ))

        // ── 统一管理平台 ──
        if totalDevices > 8 {
            recommendations.append(EquipmentRecommendation(
                category: .controller,
                priority: .medium,
                title: "建议采用统一管理平台",
                reason: "检测到你的网络复杂度适合采用统一管理平台。UniFi 或 Omada 生态可以一站式管理路由、交换、AP，通过一个 App 看全网拓扑和流量。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "UniFi 全家桶: UCG-Ultra + USW-Lite-8-PoE + U6 Pro", tier: .prosumer, priceRange: "¥2,500-3,500", specs: "路由+交换+AP 三件套 · 统一管理 · App 远程", pros: ["一个 App 管全部", "拓扑图自动生成", "颜值天花板"], cons: ["全家桶锁定生态", "总价不低"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "TP-Link", model: "Omada 全家桶: ER7206 + TL-SG2210P + EAP670", tier: .prosumer, priceRange: "¥1,800-2,500", specs: "路由+PoE交换+WiFi6 AP · SDN 控制", pros: ["性价比碾压", "功能齐全", "免费控制器"], cons: ["App 体验不如 UniFi", "颜值一般"], purchaseURL: "https://www.tp-link.com"),
                    EquipmentOption(brand: "Cisco Meraki", model: "Meraki 全家桶: MX75 + MS120-8FP + MR36", tier: .enterprise, priceRange: "¥15,000-25,000", specs: "云端管理 · 7×24 支持 · 高级安全 · 自动优化", pros: ["真·企业级", "零接触部署", "Dashboard 逆天"], cons: ["死贵+年费", "中小企业用不起"], purchaseURL: "https://meraki.cisco.com"),
                ]
            ))
        }

        return recommendations
    }

    /// Generate replacement recommendations for a specific device
    static func deviceSpecificRecommendation(for device: NetworkDevice) -> [EquipmentRecommendation] {
        var recs: [EquipmentRecommendation] = []

        switch device.deviceType {
        case .router, .switch_:
            recs.append(EquipmentRecommendation(
                category: .router,
                priority: .high,
                title: "考虑企业级路由/交换机",
                reason: "家用路由器通常缺乏 VLAN 隔离、QoS、流量监控等功能，无法有效管理多设备网络。企业级设备可提供更好的稳定性和安全性。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "UniFi Cloud Gateway Ultra", tier: .prosumer, priceRange: "¥800-1,200", specs: "1Gbps · UniFi 管理 · App 远程", pros: ["一体化", "App 管理"], cons: ["需 AP"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "MikroTik", model: "RB5009UG+S+IN", tier: .prosumer, priceRange: "¥1,200-1,600", specs: "RouterOS · 万兆 · 9口", pros: ["功能强", "功耗低"], cons: ["复杂"], purchaseURL: "https://mikrotik.com"),
                    EquipmentOption(brand: "TP-Link", model: "ER7206", tier: .prosumer, priceRange: "¥500-800", specs: "多WAN · VPN · Omada SDN", pros: ["性价比高", "SDN"], cons: ["无WiFi"], purchaseURL: "https://www.tp-link.com"),
                ]
            ))
            if device.deviceType == .router && device.osGuess?.contains("AsusWRT") == true {
                recs.append(EquipmentRecommendation(
                    category: .ap,
                    priority: .medium,
                    title: "华硕固件升级/换第三方固件",
                    reason: "AsusWRT 380.70 版本较老，建议升级到最新官方固件或刷入 Asuswrt-Merlin 获得 VLAN、温度监控等高级功能。",
                    options: [
                        EquipmentOption(brand: "Asuswrt-Merlin", model: "最新 Merlin 固件", tier: .enthusiast, priceRange: "免费", specs: "VLAN · 温度监控 · JFFS · 自定义脚本", pros: ["免费升级", "功能大增"], cons: ["刷机风险"], purchaseURL: "https://www.asuswrt-merlin.net"),
                    ]
                ))
            }
        case .nas:
            recs.append(EquipmentRecommendation(
                category: .switch_,
                priority: .medium,
                title: "为 NAS 配置交换机/链路聚合",
                reason: "NAS 设备建议直连千兆交换机并进行链路聚合(802.3ad)，避免经过路由器 NAT 影响性能。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "USW-Lite-8-PoE", tier: .prosumer, priceRange: "¥600-900", specs: "8口 · 4口PoE · 千兆", pros: ["小巧", "PoE"], cons: ["无万兆"], purchaseURL: "https://store.ui.com"),
                    EquipmentOption(brand: "TP-Link", model: "TL-SG108E", tier: .enthusiast, priceRange: "¥200-300", specs: "8口千兆 · 简单网管 · VLAN", pros: ["便宜", "网管"], cons: ["塑料壳"], purchaseURL: "https://www.tp-link.com"),
                ]
            ))
        case .iot:
            recs.append(EquipmentRecommendation(
                category: .switch_,
                priority: .high,
                title: "IoT 设备隔离到独立 VLAN",
                reason: "智能家居设备安全风险较高，建议划分独立 IoT VLAN 并限制其访问主网络，防止隐私泄露或成为攻击跳板。",
                options: [
                    EquipmentOption(brand: "Ubiquiti", model: "USW-Lite-8-PoE + UniFi AP", tier: .prosumer, priceRange: "¥1,200-1,800", specs: "VLAN 划分 · 客户端隔离 · Guest 网络", pros: ["隔离彻底", "管理方便"], cons: ["需VLAN路由支持"], purchaseURL: "https://store.ui.com"),
                ]
            ))
        default:
            break
        }

        return recs
    }
}
