package com.nettopo.diagnose

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import com.nettopo.diagnose.data.engine.DiagnosticEngine
import com.nettopo.diagnose.data.models.*
import com.nettopo.diagnose.data.scanner.NetworkScanner
import com.nettopo.diagnose.ui.screens.*
import com.nettopo.diagnose.ui.theme.NetDiagnoseTheme
import kotlinx.coroutines.*
import java.util.*

// ─── Screen State ─────────────────────────────────────────────

sealed class ScreenState {
    object Home : ScreenState()
    data class Scanning(val progress: String, val value: Float) : ScreenState()
    data class Result(
        val scanResult: com.nettopo.diagnose.data.models.ScanResult,
        val avgLatency: Double?
    ) : ScreenState()
}

// ─── Main Activity ────────────────────────────────────────────

class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            NetDiagnoseTheme {
                var screenState by remember { mutableStateOf<ScreenState>(ScreenState.Home) }
                var errorMsg by remember { mutableStateOf<String?>(null) }
                val scope = rememberCoroutineScope()

                when (val state = screenState) {
                    is ScreenState.Home -> {
                        HomeScreen(
                            errorMsg = errorMsg,
                            onStartScan = { config, mode ->
                                scope.launch {
                                    screenState = ScreenState.Scanning("正在启动扫描...", 0.01f)
                                    errorMsg = null

                                    try {
                                        val (result, avgLat) = runScan(
                                            this@MainActivity, config, mode
                                        ) { progress, value ->
                                            screenState = ScreenState.Scanning(progress, value)
                                        }

                                        screenState = ScreenState.Result(result, avgLat)
                                    } catch (e: CancellationException) {
                                        screenState = ScreenState.Home
                                    } catch (e: Exception) {
                                        errorMsg = "扫描失败: ${e.message}"
                                        screenState = ScreenState.Home
                                    }
                                }
                            }
                        )
                    }

                    is ScreenState.Scanning -> {
                        ScanScreen(
                            progress = state.progress,
                            value = state.value,
                            onCancel = {
                                screenState = ScreenState.Home
                            }
                        )
                    }

                    is ScreenState.Result -> {
                        ResultScreen(
                            result = state.scanResult,
                            avgLatency = state.avgLatency,
                            onBack = { screenState = ScreenState.Home },
                            onRescan = {
                                scope.launch {
                                    screenState = ScreenState.Scanning("重新扫描...", 0.01f)
                                    try {
                                        val (result, avgLat) = runScan(
                                            this@MainActivity, state.scanResult.config, ScanMode.STANDARD
                                        ) { progress, value ->
                                            screenState = ScreenState.Scanning(progress, value)
                                        }
                                        screenState = ScreenState.Result(result, avgLat)
                                    } catch (_: CancellationException) {
                                        screenState = ScreenState.Home
                                    } catch (e: Exception) {
                                        errorMsg = "扫描失败: ${e.message}"
                                        screenState = ScreenState.Home
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// ─── Scan Runner ──────────────────────────────────────────────

private suspend fun runScan(
    context: android.content.Context,
    config: ScanConfig,
    mode: ScanMode,
    onProgress: suspend (String, Float) -> Unit
): Pair<com.nettopo.diagnose.data.models.ScanResult, Double?> {

    val startedAt = System.currentTimeMillis()
    val subnet = config.subnet

    // Phase 0: Detect network (re-confirm)
    onProgress("自动检测网络...", 0.02f)
    val detected = withContext(Dispatchers.IO) {
        NetworkScanner.detectLocalNetwork(context)
    } ?: com.nettopo.diagnose.data.scanner.LocalNetworkInfo(
        subnet, config.gatewayIP, config.localIP, config.netmask, config.interfaceName
    )

    val gw = detected.gatewayIP
    val localIP = detected.localIP
    val iface = detected.interfaceName
    val nm = detected.netmask
    val sub = detected.subnet

    // Phase 1: Ping sweep
    onProgress("Ping 扫描 ${sub}.0/24...", 0.05f)
    val skipIPs = listOf(gw, localIP)
    val pingResults = withContext(Dispatchers.IO) {
        NetworkScanner.pingSweep(sub, skipIPs, mode.pingConcurrency)
    }
    yield()
    onProgress("发现 ${pingResults.size + 1} 台在线设备", 0.25f)

    // Phase 1.5: Service discovery (SSDP + mDNS)
    onProgress("SSDP/mDNS 发现...", 0.27f)
    val (ssdpIps, mdnsIps) = withContext(Dispatchers.IO) {
        val ssdpDeferred = async { NetworkScanner.discoverSSDP() }
        val mdnsDeferred = async { NetworkScanner.discoverMDNS() }
        Pair(ssdpDeferred.await(), mdnsDeferred.await())
    }
    // Merge discovered IPs not already in ping results
    val pingIPs = pingResults.map { it.ip }.toSet()
    val discoveredIPs = (ssdpIps + mdnsIps).filter { it !in pingIPs && it != gw && it != localIP }
    yield()
    onProgress("发现 ${pingResults.size + 1 + discoveredIPs.size} 台设备", 0.28f)

    // Phase 2: ARP table
    onProgress("获取 MAC 地址...", 0.30f)
    val arpEntries = withContext(Dispatchers.IO) {
        NetworkScanner.readArpTable()
    }
    yield()

    // Build lookup maps
    val ipToMac = mutableMapOf<String, String>()
    val localMac = withContext(Dispatchers.IO) { NetworkScanner.getLocalMac(iface) }
    if (localMac != null) ipToMac[localIP] = localMac
    val ipToVendor = mutableMapOf<String, String>()
    for (entry in arpEntries) {
        ipToMac[entry.ip] = entry.mac
        ipToVendor[entry.ip] = NetworkScanner.lookupVendor(entry.mac) ?: ""
    }
    onProgress("解析 MAC/OUI...", 0.35f)

    // Phase 3: Port scan all discovered IPs
    val allIPs = (listOf(gw) + pingResults.map { it.ip }.filter { it != gw } + discoveredIPs).distinct()
    // Add ARP-only devices
    val arpOnlyIPs = arpEntries.filter { it.mac != "(incomplete)" && it.ip !in allIPs && it.ip != localIP }
        .map { it.ip }.distinct()
    val allIPsWithARP = allIPs + arpOnlyIPs
    val total = allIPsWithARP.size
    val devices = mutableListOf<NetworkDevice>()

    for ((idx, ip) in allIPsWithARP.withIndex()) {
        yield()
        val progress = 0.40f + 0.55f * (idx + 1) / total
        val isARPOnly = ip in arpOnlyIPs
        onProgress("端口扫描 ${idx + 1}/$total - $ip${if (isARPOnly) " (ARP)" else ""}", progress)

        val mac = ipToMac[ip]
        val vendor = ipToVendor[ip]

        val ports = withContext(Dispatchers.IO) {
            if (isARPOnly) NetworkScanner.checkPorts(ip, ScanMode.QUICK)
            else NetworkScanner.checkPorts(ip, mode)
        }

        val hostname = when {
            ip == gw -> "网关"
            else -> pingResults.firstOrNull { it.ip == ip }?.hostname
        }

        val deviceType = NetworkScanner.guessDevice(ip, mac, vendor, hostname, ports)
        val finalType = if (ip == gw) DeviceType.ROUTER else deviceType

        // Discovery sources
        val sources = mutableListOf<DiscoverySource>()
        if (ip == gw) sources.add(DiscoverySource.GATEWAY)
        if (ip == localIP) sources.add(DiscoverySource.LOCAL)
        if (mac != null) { sources.add(DiscoverySource.ARP); sources.add(DiscoverySource.OUI) }
        if (pingResults.any { it.ip == ip }) sources.add(DiscoverySource.PING)
        if (ssdpIps.contains(ip)) sources.add(DiscoverySource.SSDP)
        if (mdnsIps.contains(ip)) sources.add(DiscoverySource.MDNS)
        if (ports.isNotEmpty()) sources.add(DiscoverySource.PORT_SCAN)
        if (hostname != null && hostname != "网关") sources.add(DiscoverySource.REVERSE_DNS)

        // Confidence
        val confidence = when {
            finalType == DeviceType.UNKNOWN || finalType == DeviceType.IOT ->
                if (sources.size >= 3) IdentificationConfidence.MEDIUM else IdentificationConfidence.LOW
            finalType == DeviceType.ROUTER -> IdentificationConfidence.HIGH
            sources.size >= 4 -> IdentificationConfidence.HIGH
            sources.size >= 2 -> IdentificationConfidence.MEDIUM
            else -> IdentificationConfidence.LOW
        }

        // Risk level
        val dangerous = ports.filter { it in setOf(23, 3389, 5900, 5985, 5986, 22) }
        val riskLevel: RiskLevel
        val riskNotes: List<String>
        if (dangerous.isNotEmpty()) {
            riskLevel = RiskLevel.HIGH
            riskNotes = dangerous.map { "高风险端口 $it 开放" }
        } else if (ports.any { it in setOf(445, 139, 135, 548) }) {
            riskLevel = RiskLevel.MEDIUM
            riskNotes = listOf("文件共享端口开放")
        } else {
            riskLevel = RiskLevel.LOW
            riskNotes = emptyList()
        }

        // Evidence
        val evidence = mutableListOf<String>()
        if (vendor != null) evidence.add("OUI识别: $vendor")
        if (hostname != null && hostname != "网关") evidence.add("主机名: $hostname")
        if (ports.isNotEmpty()) evidence.add("开放端口: ${ports.joinToString(",")}")
        if (finalType != deviceType && finalType == DeviceType.ROUTER)
            evidence.add("类型修正: ${deviceType.label} → 路由器/网关")

        devices.add(NetworkDevice(
            ipAddress = ip, macAddress = mac, hostname = hostname,
            vendor = vendor, deviceType = finalType, openPorts = ports,
            isOnline = true, isGateway = ip == gw,
            isLocalDevice = ip == localIP,
            discoverySources = sources,
            identificationConfidence = confidence,
            identificationEvidence = evidence,
            riskLevel = riskLevel,
            riskNotes = riskNotes
        ))
    }

    onProgress("扫描完成：${devices.size} 台设备", 0.96f)

    // Phase 5: Latency measurement (if mode supports it)
    var avgLatency: Double? = null
    if (mode.includesLatency) {
        val onlineDevices = devices.filter { it.isOnline }
        val mutDevices = devices.toMutableList()
        for ((i, device) in onlineDevices.withIndex()) {
            yield()
            onProgress("延迟测试 ${i + 1}/${onlineDevices.size} - ${device.ipAddress}",
                0.96f + 0.04f * (i + 1) / onlineDevices.size)
            val lat = withContext(Dispatchers.IO) {
                NetworkScanner.measureLatency(device.ipAddress)
            }
            val idx = mutDevices.indexOfFirst { it.ipAddress == device.ipAddress }
            if (idx >= 0) mutDevices[idx] = mutDevices[idx].copy(latencyMs = lat)
        }
        devices.clear()
        devices.addAll(mutDevices)
        avgLatency = devices.mapNotNull { it.latencyMs }.let {
            if (it.isEmpty()) null else it.average()
        }
    }

    onProgress("扫描完成：${devices.size} 台设备", 1.0f)

    val finalConfig = ScanConfig(sub, gw, localIP, nm, iface)
    val scanResult = com.nettopo.diagnose.data.models.ScanResult(
        devices = devices,
        config = finalConfig,
        scanDuration = (System.currentTimeMillis() - startedAt) / 1000.0
    )

    return Pair(scanResult, avgLatency)
}
