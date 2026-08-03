package com.nettopo.diagnose.data.models

import java.util.*
import androidx.compose.ui.graphics.Color
import kotlin.math.min

// ─── Device Type ───────────────────────────────────────────────
enum class DeviceType(val label: String, val emoji: String) {
    ROUTER("路由器/网关", "📡"),
    SWITCH("交换机", "🔌"),
    COMPUTER("电脑", "💻"),
    PHONE("手机", "📱"),
    TABLET("平板", "📋"),
    NAS("NAS/存储", "🗄️"),
    PRINTER("打印机", "🖨️"),
    IOT("智能家居/IoT", "🏠"),
    CAMERA("摄像头", "📷"),
    TV("电视/盒子", "📺"),
    UNKNOWN("未识别", "❓");

    fun icon(): String = when (this) {
        ROUTER -> "📡"
        SWITCH -> "🔌"
        COMPUTER -> "💻"
        PHONE -> "📱"
        TABLET -> "📋"
        NAS -> "🗄️"
        PRINTER -> "🖨️"
        IOT -> "🏠"
        CAMERA -> "📷"
        TV -> "📺"
        UNKNOWN -> "❓"
    }
}

// ─── Scan Mode ─────────────────────────────────────────────────
enum class ScanMode(val label: String) {
    QUICK("快速"),
    STANDARD("标准"),
    DEEP("深度");

    val subtitle: String get() = when (this) {
        QUICK -> "ARP + Ping，速度优先"
        STANDARD -> "常用服务 + 关键端口"
        DEEP -> "更多端口，识别更细"
    }
    val pingConcurrency: Int get() = when (this) { QUICK -> 48; STANDARD -> 32; DEEP -> 24 }
    val portConcurrency: Int get() = when (this) { QUICK -> 24; STANDARD -> 16; DEEP -> 8 }
    val portTimeout: Long get() = when (this) { QUICK -> 120; STANDARD -> 180; DEEP -> 350 }
    val includesMdns: Boolean get() = this != QUICK
    val includesLatency: Boolean get() = this != QUICK
}

// ─── Identification ────────────────────────────────────────────
enum class IdentificationConfidence(val label: String, val score: Int) {
    HIGH("高", 90),
    MEDIUM("中", 65),
    LOW("低", 35)
}

enum class DiscoverySource(val label: String) {
    GATEWAY("网关"), LOCAL("本机"), ARP("ARP"), PING("Ping"),
    REVERSE_DNS("反向DNS"), MDNS("mDNS"), SSDP("SSDP/UPnP"),
    PORT_SCAN("端口"), OUI("OUI厂商"), USER_HINT("规则")
}

enum class RiskLevel(val label: String, val rank: Int) {
    LOW("低", 0), MEDIUM("中", 1), HIGH("高", 2)
}

// ─── Network Scenario ──────────────────────────────────────────
enum class NetworkScenario(val label: String) {
    HOME("家庭"),
    OFFICE("小办公室"),
    EVENT("公司"),
    HOTEL("酒店/工程");

    val focus: String get() = when (this) {
        HOME -> "陌生设备、智能家居、弱风险端口"
        OFFICE -> "NAS、打印机、共享端口、远程桌面"
        EVENT -> "网关、DNS、延迟、异常蹭网设备、VPN暴露"
        HOTEL -> "网关、摄像头、打印机、内网暴露服务"
    }
}

// ─── Scan Config ───────────────────────────────────────────────
data class ScanConfig(
    val subnet: String = "",
    val gatewayIP: String = "",
    val localIP: String = "",
    val netmask: String = "255.255.255.0",
    val interfaceName: String = "wlan0"
) {
    val cidrNotation: String get() {
        val ones = netmask.split(".").sumOf { Integer.bitCount(it.toInt()) }
        return "$subnet/$ones"
    }
}

// ─── Network Device ────────────────────────────────────────────
data class NetworkDevice(
    val id: String = UUID.randomUUID().toString(),
    val ipAddress: String,
    val macAddress: String? = null,
    val hostname: String? = null,
    val vendor: String? = null,
    val deviceType: DeviceType = DeviceType.UNKNOWN,
    val openPorts: List<Int> = emptyList(),
    val isOnline: Boolean = true,
    val isGateway: Boolean = false,
    val isLocalDevice: Boolean = false,
    val lastSeen: Long = System.currentTimeMillis(),
    val latencyMs: Double? = null,
    val discoverySources: List<DiscoverySource> = emptyList(),
    val identificationConfidence: IdentificationConfidence = IdentificationConfidence.LOW,
    val identificationEvidence: List<String> = emptyList(),
    val riskLevel: RiskLevel = RiskLevel.LOW,
    val riskNotes: List<String> = emptyList()
) {
    val displayName: String get() = hostname ?: ipAddress
    val shortIP: String get() = ipAddress.split(".").lastOrNull() ?: ipAddress
}

// ─── Scan Result ───────────────────────────────────────────────
data class ScanResult(
    val devices: List<NetworkDevice>,
    val config: ScanConfig,
    val scanDuration: Double,
    val timestamp: Long = System.currentTimeMillis()
) {
    val gateway: NetworkDevice? get() = devices.firstOrNull { it.isGateway }
    val deviceCountByType: Map<DeviceType, Int> get() = devices.groupBy { it.deviceType }.mapValues { it.value.size }
    val onlineCount: Int get() = devices.count { it.isOnline }
    val offlineCount: Int get() = devices.count { !it.isOnline }
}

// ─── Diagnostic Finding ────────────────────────────────────────
data class DiagnosticFinding(
    val id: String = UUID.randomUUID().toString(),
    val severity: FindingSeverity,
    val title: String,
    val explanation: String,
    val action: String,
    val affectedIPs: List<String> = emptyList()
)

enum class FindingSeverity(val label: String) {
    GOOD("正常"), INFO("提示"), WARNING("注意"), CRITICAL("高风险")
}

// ─── Health Breakdown ──────────────────────────────────────────
data class HealthBreakdown(
    val total: Int = 0,
    val baseScore: Int = 100,
    val offlinePenalty: Int = 0,
    val latencyPenalty: Int = 0,
    val portPenalty: Int = 0,
    val unknownPenalty: Int = 0,
    val onlineCount: Int = 0,
    val offlineCount: Int = 0,
    val avgLatency: Double? = null,
    val dangerousPortCount: Int = 0,
    val unknownCount: Int = 0
) {
    val scoreLabel: String get() = when {
        total >= 90 -> "网络健康"
        total >= 70 -> "网络基本正常"
        total >= 50 -> "网络需要关注"
        else -> "网络状况不佳"
    }
    val scoreColor: Color get() = when {
        total >= 80 -> Color(0xFF22C55E)
        total >= 60 -> Color(0xFFEAB308)
        total >= 40 -> Color(0xFFF97316)
        else -> Color(0xFFEF4444)
    }

    companion object {
        fun compute(
            devices: List<NetworkDevice>,
            avgLatency: Double?
        ): HealthBreakdown {
            val online = devices.filter { it.isOnline }
            if (online.isEmpty()) {
                return HealthBreakdown(
                    total = 0, offlineCount = devices.size, onlineCount = 0
                )
            }

            val offline = devices.size - online.size
            val offlinePenalty = min(offline * 2, 15)

            val latencyPenalty = avgLatency?.let {
                when { it > 100 -> 25; it > 50 -> 15; it > 20 -> 8; it > 10 -> 3; else -> 0 }
            } ?: 0

            val dangerousPorts = setOf(23, 3389, 5900, 139)
            var portPenalty = 0
            var dangerousPortCount = 0
            for (d in online) {
                val hits = d.openPorts.count { it in dangerousPorts }
                portPenalty += hits * 3
                dangerousPortCount += hits
            }
            portPenalty = min(portPenalty, 15)

            val unknownCount = online.count { it.deviceType == DeviceType.UNKNOWN }
            val unknownPenalty = min(unknownCount, 5)

            val total = maxOf(0, minOf(100, (100 - offlinePenalty - latencyPenalty - portPenalty - unknownPenalty)))

            return HealthBreakdown(
                total = total, offlinePenalty = offlinePenalty,
                latencyPenalty = latencyPenalty, portPenalty = portPenalty,
                unknownPenalty = unknownPenalty, onlineCount = online.size,
                offlineCount = offline, avgLatency = avgLatency,
                dangerousPortCount = dangerousPortCount, unknownCount = unknownCount
            )
        }
    }
}
