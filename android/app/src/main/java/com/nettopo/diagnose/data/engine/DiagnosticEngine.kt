package com.nettopo.diagnose.data.engine

import com.nettopo.diagnose.data.models.*

object DiagnosticEngine {

    fun analyze(
        devices: List<NetworkDevice>,
        scenario: NetworkScenario? = null
    ): List<DiagnosticFinding> {
        val findings = mutableListOf<DiagnosticFinding>()
        val online = devices.filter { it.isOnline }
        val offline = devices.filter { !it.isOnline }

        // ── Always-check items ─────────────────────────────────

        // 1. Gateway presence
        val gateway = devices.firstOrNull { it.isGateway }
        if (gateway == null) {
            findings.add(DiagnosticFinding(
                severity = FindingSeverity.CRITICAL,
                title = "未发现网关",
                explanation = "扫描未识别到网关设备（.1 或 .254），可能路由器未响应或不在标准子网位置",
                action = "手动检查路由器 IP 地址，确认子网范围是否正确"
            ))
        } else if (!gateway.isOnline) {
            findings.add(DiagnosticFinding(
                severity = FindingSeverity.CRITICAL,
                title = "网关离线",
                explanation = "网关 ${gateway.ipAddress} 未响应，网络可能不可用",
                action = "检查路由器电源和线路连接", affectedIPs = listOf(gateway.ipAddress)
            ))
        }

        // 2. Offline devices
        if (offline.size > 3) {
            findings.add(DiagnosticFinding(
                severity = FindingSeverity.WARNING,
                title = "${offline.size} 台设备离线",
                explanation = "大量设备离线，可能是断电或批量断网",
                action = "检查交换机/AP 供电状态，查看离线设备是否正常关机",
                affectedIPs = offline.map { it.ipAddress }.take(5)
            ))
        }

        // 3. High latency
        val avgLatency = online.mapNotNull { it.latencyMs }.let {
            if (it.isEmpty()) null else it.average()
        }
        if (avgLatency != null && avgLatency > 50) {
            findings.add(DiagnosticFinding(
                severity = if (avgLatency > 100) FindingSeverity.CRITICAL else FindingSeverity.WARNING,
                title = "平均延迟 ${String.format("%.0f", avgLatency)}ms 偏高",
                explanation = "网络响应慢，可能影响视频通话、在线游戏等实时应用",
                action = "检查 WiFi 信号强度，尝试更换信道或靠近路由器"
            ))
        }

        // 4. Dangerous ports
        val dangerousPorts = setOf(23, 3389, 5900, 139, 445, 21, 5985, 5986)
        val riskyDevices = online.filter { d ->
            d.openPorts.any { it in dangerousPorts }
        }
        if (riskyDevices.isNotEmpty()) {
            val ips = riskyDevices.map { it.ipAddress }
            findings.add(DiagnosticFinding(
                severity = if (riskyDevices.any { 3389 in it.openPorts || 5900 in it.openPorts })
                    FindingSeverity.CRITICAL else FindingSeverity.WARNING,
                title = "${riskyDevices.size} 台设备开放不安全端口",
                explanation = "以下设备开放了 Telnet/RDP/VNC/SMB 等高风险端口：${ips.joinToString(", ")}",
                action = "在设备上关闭不必要的远程服务，或在路由器设置 ACL 限制访问",
                affectedIPs = ips
            ))
        }

        // 5. Unknown devices
        val unknown = online.filter { it.deviceType == DeviceType.UNKNOWN }
        if (unknown.size > 2) {
            findings.add(DiagnosticFinding(
                severity = FindingSeverity.WARNING,
                title = "${unknown.size} 台设备类型未识别",
                explanation = "无法识别设备类型，可能是新型 IoT 设备或陌生设备",
                action = "核对 MAC 地址厂商信息，确认是否为授权设备",
                affectedIPs = unknown.map { it.ipAddress }
            ))
        }

        // 6. All good
        if (findings.isEmpty() || findings.all { it.severity == FindingSeverity.WARNING && it.title.contains("离线") }) {
            findings.add(DiagnosticFinding(
                severity = FindingSeverity.GOOD,
                title = "网络状态良好",
                explanation = "未发现明显安全问题或性能瓶颈，网络运行正常",
                action = "继续保持，建议定期扫描"
            ))
        }

        // ── Scenario-specific checks ───────────────────────────

        when (scenario) {
            NetworkScenario.HOME -> {
                val iotDevices = online.filter { it.deviceType == DeviceType.IOT }
                if (iotDevices.size > 5) {
                    findings.add(DiagnosticFinding(
                        severity = FindingSeverity.INFO,
                        title = "智能家居设备较多 (${iotDevices.size}台)",
                        explanation = "大量 IoT 设备可能占用 2.4GHz 频段带宽",
                        action = "考虑启用 5GHz WiFi 或将 IoT 设备隔离到独立 VLAN"
                    ))
                }
            }
            NetworkScenario.OFFICE -> {
                val nas = online.filter { it.deviceType == DeviceType.NAS }
                if (nas.isEmpty()) {
                    findings.add(DiagnosticFinding(
                        severity = FindingSeverity.INFO,
                        title = "未检测到 NAS/共享存储",
                        explanation = "办公室未发现 NAS 设备，文件共享可能依赖个人电脑",
                        action = "考虑部署 NAS 集中管理文件，提升备份效率"
                    ))
                }
            }
            NetworkScenario.EVENT -> {
                if (avgLatency != null && avgLatency > 20) {
                    findings.add(DiagnosticFinding(
                        severity = FindingSeverity.WARNING,
                        title = "公司网络延迟偏高 (${String.format("%.0f", avgLatency)}ms)",
                        explanation = "内网延迟应低于 10ms，当前延迟可能影响内部服务访问",
                        action = "检查交换机端口速率、网线质量，排查广播风暴"
                    ))
                }
            }
            NetworkScenario.HOTEL -> {
                val cameras = online.filter { it.deviceType == DeviceType.CAMERA }
                val printers = online.filter { it.deviceType == DeviceType.PRINTER }
                findings.add(DiagnosticFinding(
                    severity = FindingSeverity.INFO,
                    title = "工程场景设备概况",
                    explanation = "摄像头: ${cameras.size}台 | 打印机: ${printers.size}台 | 总计: ${online.size}台在线",
                    action = "检查所有摄像头 NVR 录像是否正常，打印机耗材状态"
                ))
            }
            null -> {}
        }

        return findings.sortedByDescending { it.severity.ordinal }
    }
}
