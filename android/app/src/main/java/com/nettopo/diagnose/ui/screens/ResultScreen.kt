package com.nettopo.diagnose.ui.screens

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.core.content.FileProvider
import com.nettopo.diagnose.data.engine.DiagnosticEngine
import com.nettopo.diagnose.data.models.*
import com.nettopo.diagnose.ui.theme.*
import java.io.File
import kotlin.math.PI
import kotlin.math.roundToInt

enum class ResultTab(val label: String, val emoji: String) {
    DIAGNOSIS("诊断结论", "\uD83E\uDE7A"),
    TOPOLOGY("拓扑图", "\uD83D\uDD17"),
    DEVICES("设备清单", "\uD83D\uDCCB"),
    EXPORT("导出", "\uD83D\uDCE4")
}

@Composable
fun ResultScreen(
    result: ScanResult,
    avgLatency: Double?,
    onBack: () -> Unit,
    onRescan: () -> Unit
) {
    val context = LocalContext.current
    var selectedTab by remember { mutableStateOf(ResultTab.DIAGNOSIS) }
    var selectedScenario by remember { mutableStateOf<NetworkScenario?>(null) }
    var expertMode by remember { mutableStateOf(false) }
    var selectedDevice by remember { mutableStateOf<NetworkDevice?>(null) }

    val health = remember(result, avgLatency) {
        HealthBreakdown.compute(result.devices, avgLatency)
    }
    val findings = remember(result, selectedScenario) {
        DiagnosticEngine.analyze(result.devices, selectedScenario)
    }

    val tips = remember(result, avgLatency) {
        buildList {
            if (result.offlineCount > 3)
                add("有 ${result.offlineCount} 台设备离线，检查是否正常关机")
            if (avgLatency != null && avgLatency > 20)
                add("平均延迟 ${avgLatency.roundToInt()}ms 偏高，检查信号或换信道")
            val unsafe = result.devices.filter { d ->
                d.openPorts.any { it in setOf(23, 21, 3389, 5900, 139, 445) }
            }
            if (unsafe.isNotEmpty())
                add("${unsafe.size} 台设备开放不安全端口")
            val unknown = result.devices.filter { it.deviceType == DeviceType.UNKNOWN }
            if (unknown.size > 2)
                add("${unknown.size} 台设备类型未知")
        }
    }

    if (selectedDevice != null) {
        DeviceDetailDialog(
            device = selectedDevice!!,
            onDismiss = { selectedDevice = null }
        )
    }

    Column(modifier = Modifier.fillMaxSize().background(Slate950)) {
        // ── Top Bar (compact) ────────────────────────────
        Surface(color = Slate900, modifier = Modifier.fillMaxWidth()) {
            Column {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 4.dp, bottom = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(
                        onClick = onBack,
                        colors = ButtonDefaults.buttonColors(containerColor = Cyan500),
                        shape = RoundedCornerShape(5.dp),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                        modifier = Modifier.height(28.dp)
                    ) { Text("←", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = Slate950) }

                    if (result.devices.isNotEmpty()) {
                        Spacer(modifier = Modifier.width(4.dp))
                        Row(
                            modifier = Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            val scenarios = NetworkScenario.entries.toList()
                            scenarios.forEach { scenario ->
                                val active = scenario == selectedScenario
                                FilterChip(
                                    selected = active,
                                    onClick = { selectedScenario = if (active) null else scenario },
                                    label = { Text(scenario.label, fontSize = 10.sp) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = Cyan400.copy(alpha = 0.15f),
                                        selectedLabelColor = Cyan400
                                    ),
                                    modifier = Modifier.height(26.dp)
                                )
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
                // Expert mode toggle — compact second row
                if (result.devices.isNotEmpty()) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Spacer(modifier = Modifier.weight(1f))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(Slate800)
                                .clickable { expertMode = !expertMode }
                                .padding(horizontal = 12.dp, vertical = 2.dp)
                        ) {
                            Text(
                                if (expertMode) "专家 (MAC/延迟/端口)" else "精简",
                                fontSize = 9.sp,
                                color = if (expertMode) Cyan400 else Gray400
                            )
                        }
                        Spacer(modifier = Modifier.weight(1f))

                        Surface(
                            color = health.scoreColor.copy(alpha = 0.15f),
                            shape = RoundedCornerShape(5.dp)
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(health.scoreColor))
                                Spacer(modifier = Modifier.width(3.dp))
                                Text("${health.total}", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = White)
                            }
                        }
                    }
                }
            }
        }

        // ── Tab Content ───────────────────────────────────
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            when (selectedTab) {
                ResultTab.DIAGNOSIS -> DiagnosisTab(findings, health, result, avgLatency, tips)
                ResultTab.TOPOLOGY -> TopologyTab(result.devices, result.config)
                ResultTab.DEVICES -> DevicesTab(
                    result.devices, health, tips, expertMode, onRescan,
                    onDeviceClick = { selectedDevice = it }
                )
                ResultTab.EXPORT -> ExportTab(context, result, findings, health)
            }
        }

        // ── Bottom Tab Bar ────────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth().background(Slate900),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            ResultTab.entries.forEach { tab ->
                val active = tab == selectedTab
                TextButton(
                    onClick = { selectedTab = tab },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.textButtonColors(contentColor = if (active) Cyan400 else Gray400)
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(tab.emoji, fontSize = 14.sp)
                        Text(tab.label, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}

// ─── Device Detail Dialog ───────────────────────────────────
@Composable
fun DeviceDetailDialog(device: NetworkDevice, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(16.dp), color = Slate900, modifier = Modifier.fillMaxWidth(0.92f)) {
            Column(modifier = Modifier.padding(20.dp).verticalScroll(rememberScrollState())) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        "${device.deviceType.emoji} ${device.displayName}",
                        fontSize = 18.sp, fontWeight = FontWeight.Bold, color = White,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = onDismiss) { Text("关闭", fontSize = 13.sp, color = Gray400) }
                }
                Spacer(modifier = Modifier.height(16.dp))
                DetailRow("IP 地址", device.ipAddress)
                DetailRow("MAC 地址", device.macAddress ?: "获取中...")
                DetailRow("厂商", device.vendor ?: (if (device.macAddress != null) "未知" else "--"))
                DetailRow("设备类型", "${device.deviceType.emoji} ${device.deviceType.label}")
                DetailRow("延迟", device.latencyMs?.let { "${it.roundToInt()} ms" } ?: "--")
                DetailRow("在线状态", if (device.isOnline) "\uD83D\uDFE2 在线" else "\u26AB 离线")
                if (device.openPorts.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("开放端口", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = White)
                    Text(device.openPorts.joinToString(", "), fontSize = 11.sp, color = Cyan400.copy(alpha = 0.7f))
                }
                if (device.identificationEvidence.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("识别依据", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = White)
                    device.identificationEvidence.forEach { Text("• $it", fontSize = 11.sp, color = Gray400) }
                }
                Spacer(modifier = Modifier.height(16.dp))
                Button(
                    onClick = onDismiss,
                    colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                    modifier = Modifier.fillMaxWidth()
                ) { Text("关闭", fontSize = 13.sp, color = Gray400) }
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 12.sp, color = Gray500, modifier = Modifier.width(70.dp))
        Text(value, fontSize = 13.sp, color = White)
    }
}

// ─── Diagnosis Tab ───────────────────────────────────────
@Composable
fun DiagnosisTab(
    findings: List<DiagnosticFinding>,
    health: HealthBreakdown,
    result: ScanResult,
    avgLatency: Double?,
    tips: List<String>
) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Slate900).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(80.dp)) {
                Canvas(modifier = Modifier.size(80.dp)) {
                    drawCircle(color = health.scoreColor.copy(alpha = 0.15f), style = Stroke(width = 8f))
                    drawArc(color = health.scoreColor, startAngle = -90f, sweepAngle = health.total / 100f * 360f,
                        useCenter = false, style = Stroke(width = 8f, cap = StrokeCap.Round))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${health.total}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = White)
                    Text("/100", fontSize = 9.sp, color = Gray400)
                }
            }
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(health.scoreLabel, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = White)
                Spacer(modifier = Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("\uD83D\uDFE2 ${result.onlineCount} 在线", fontSize = 11.sp, color = Green500)
                    Text("\u26AB ${result.offlineCount} 离线", fontSize = 11.sp, color = Gray400)
                    avgLatency?.let { Text("\u23F1 ${it.roundToInt()}ms", fontSize = 11.sp, color = Orange500) }
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("扫描耗时", fontSize = 10.sp, color = Gray400)
                Text("${String.format("%.1f", result.scanDuration)}秒", fontSize = 15.sp, color = White)
            }
        }

        if (findings.isNotEmpty()) {
            Text("诊断结论", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = White)
            findings.forEach { finding ->
                val sevColor = when (finding.severity) {
                    FindingSeverity.GOOD -> Green500
                    FindingSeverity.INFO -> Cyan400
                    FindingSeverity.WARNING -> Yellow500
                    FindingSeverity.CRITICAL -> Red500
                }
                Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Slate900)) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(sevColor))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("[${finding.severity.label}] ${finding.title}", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = White)
                        }
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(finding.explanation, fontSize = 12.sp, color = Gray400)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("→ ${finding.action}", fontSize = 12.sp, color = Cyan400.copy(alpha = 0.7f))
                    }
                }
            }
        }

        if (tips.isNotEmpty()) {
            Text("诊断建议", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = White, modifier = Modifier.padding(top = 8.dp))
            tips.forEach { tip ->
                Row(modifier = Modifier.padding(vertical = 4.dp)) {
                    Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(Yellow500))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(tip, fontSize = 12.sp, color = Gray400)
                }
            }
        }
    }
}
// ─── Topology Tab (tree-style with labels) ───────────────

@Composable
fun TopologyTab(devices: List<NetworkDevice>, config: ScanConfig) {
    val gateway = devices.firstOrNull { it.isGateway }
    val others = devices.filter { !it.isGateway }

    if (devices.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("暂无设备数据", fontSize = 14.sp, color = Gray400)
        }
        return
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("网络拓扑", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = White,
            modifier = Modifier.padding(bottom = 16.dp))

        // Gateway hub
        if (gateway != null) {
            TopoDeviceCard(
                device = gateway,
                isGateway = true,
                modifier = Modifier.fillMaxWidth()
            )
        }

        // Connection lines + devices
        if (others.isNotEmpty()) {
            // Visual separator
            Box(
                modifier = Modifier.fillMaxWidth().height(40.dp),
                contentAlignment = Alignment.Center
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val cx = size.width / 2
                    // Vertical lines from center to bottom
                    drawLine(
                        color = Color(0xFF475569),
                        start = Offset(cx, 0f),
                        end = Offset(cx, size.height),
                        strokeWidth = 2f
                    )
                }
            }

            // Device list in 2-column grid
            val chunks = others.chunked(2)
            chunks.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    row.forEach { device ->
                        TopoDeviceCard(
                            device = device,
                            isGateway = false,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    // Fill empty slot for odd count
                    if (row.size == 1) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
            }
        }

        Spacer(modifier = Modifier.height(12.dp))
        Text("${devices.size} 台设备 · 网关: ${gateway?.ipAddress ?: "--"}",
            fontSize = 12.sp, color = Gray400)
    }
}

@Composable
private fun TopoDeviceCard(device: NetworkDevice, isGateway: Boolean, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.padding(vertical = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isGateway) Color(0xFFFFD700).copy(alpha = 0.1f) else Slate900
        ),
        shape = RoundedCornerShape(10.dp)
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Device icon
            Box(
                modifier = Modifier.size(if (isGateway) 40.dp else 32.dp)
                    .clip(CircleShape)
                    .background(if (isGateway) Color(0xFFFFD700).copy(alpha = 0.2f) else Cyan400.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    device.deviceType.emoji,
                    fontSize = if (isGateway) 18.sp else 14.sp
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    device.displayName,
                    fontSize = 11.sp,
                    fontWeight = if (isGateway) FontWeight.Bold else FontWeight.Medium,
                    color = if (isGateway) Yellow500 else White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    device.ipAddress,
                    fontSize = 10.sp,
                    color = Gray400,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (!isGateway && device.vendor != null) {
                    Text(
                        device.vendor!!,
                        fontSize = 8.sp,
                        color = Gray500,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            // Status dot
            Box(
                modifier = Modifier.size(8.dp).clip(CircleShape)
                    .background(if (device.isOnline) Green500 else Gray500)
            )
        }
    }
}

// ─── Devices Tab ─────────────────────────────────────────
@Composable
fun DevicesTab(
    devices: List<NetworkDevice>,
    health: HealthBreakdown,
    tips: List<String>,
    expertMode: Boolean,
    onRescan: () -> Unit,
    onDeviceClick: (NetworkDevice) -> Unit = {}
) {
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Slate900).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("${health.total}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = White)
            Text("/100", fontSize = 10.sp, color = Gray400, modifier = Modifier.padding(start = 2.dp))
            Spacer(modifier = Modifier.width(12.dp))
            Text(health.scoreLabel, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = White)
            Spacer(modifier = Modifier.weight(1f))
            Text("${health.onlineCount}\uD83D\uDFE2  ${health.offlineCount}\u26AB", fontSize = 11.sp, color = Gray400)
        }

        Text("设备清单 (${devices.size}台)", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = White)

        Column(modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Slate800)) {
            Row(modifier = Modifier.background(Slate800).padding(horizontal = 10.dp, vertical = 6.dp)) {
                Text("IP", modifier = Modifier.width(100.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Gray400)
                if (expertMode) { Text("MAC", modifier = Modifier.width(110.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Gray400) }
                Text("类型", modifier = Modifier.width(80.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Gray400)
                if (expertMode) { Text("延迟", modifier = Modifier.width(50.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Gray400, textAlign = TextAlign.End) }
                Text("状态", modifier = Modifier.width(30.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Gray400)
            }
            devices.sortedBy { it.latencyMs ?: 9999.0 }.forEach { device ->
                Row(
                    modifier = Modifier
                        .background(if (device.isGateway) Color(0xFFFFD700).copy(alpha = 0.06f) else Color.Transparent)
                        .clickable { onDeviceClick(device) }
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(device.ipAddress, modifier = Modifier.width(100.dp), fontSize = 10.sp, color = if (device.isGateway) Yellow500 else White)
                    if (expertMode) { Text(device.macAddress ?: "--", modifier = Modifier.width(110.dp), fontSize = 9.sp, color = Gray400) }
                    Text("${device.deviceType.emoji}${device.deviceType.label}", modifier = Modifier.width(80.dp), fontSize = 10.sp, color = Cyan400.copy(alpha = 0.7f), maxLines = 1)
                    if (expertMode) {
                        device.latencyMs?.let {
                            val c = when { it < 5 -> Green500; it < 15 -> Cyan400; it < 50 -> Yellow500; it < 100 -> Orange500; else -> Red500 }
                            Text("${it.roundToInt()}ms", modifier = Modifier.width(50.dp), fontSize = 9.sp, color = c)
                        } ?: Text("--", modifier = Modifier.width(50.dp), fontSize = 9.sp, color = Gray400)
                    }
                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(if (device.isOnline) Green500 else Gray500))
                }
            }
        }

        if (tips.isNotEmpty()) {
            Text("诊断建议", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = White)
            tips.forEach { tip ->
                Row(modifier = Modifier.padding(vertical = 3.dp)) {
                    Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(Yellow500))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(tip, fontSize = 12.sp, color = Gray400)
                }
            }
        }
        if (health.total < 80) {
            HorizontalDivider(color = Slate800, modifier = Modifier.padding(vertical = 8.dp))
            Button(onClick = onRescan, colors = ButtonDefaults.buttonColors(containerColor = Cyan500), shape = RoundedCornerShape(8.dp)) {
                Text("\uD83D\uDD04 重新扫描", fontSize = 13.sp)
            }
        }
    }
}

// ─── Export Tab ──────────────────────────────────────────
@Composable
fun ExportTab(context: Context, result: ScanResult, findings: List<DiagnosticFinding>, health: HealthBreakdown) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("\uD83D\uDCC4", fontSize = 48.sp)
        Spacer(modifier = Modifier.height(16.dp))
        Text("导出诊断报告", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = White)
        Spacer(modifier = Modifier.height(8.dp))
        Text("报告包含设备清单、诊断结论、健康评分", fontSize = 13.sp, color = Gray400)
        Text("支持 JSON / CSV / HTML / TXT", fontSize = 11.sp, color = Gray400)
        Spacer(modifier = Modifier.height(20.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Button(
                onClick = { exportJSON(context, result, findings, health) },
                colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                shape = RoundedCornerShape(6.dp),
                modifier = Modifier.weight(1f).height(32.dp),
                contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)
            ) { Text("JSON", fontSize = 10.sp, color = White) }
            Button(
                onClick = { exportCSV(context, result) },
                colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                shape = RoundedCornerShape(6.dp),
                modifier = Modifier.weight(1f).height(32.dp),
                contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)
            ) { Text("CSV", fontSize = 10.sp, color = White) }
            Button(
                onClick = { exportHTML(context, result, findings, health) },
                colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                shape = RoundedCornerShape(6.dp),
                modifier = Modifier.weight(1f).height(32.dp),
                contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)
            ) { Text("HTML", fontSize = 10.sp, color = White) }
            Button(
                onClick = { exportTXT(context, result, findings, health) },
                colors = ButtonDefaults.buttonColors(containerColor = Slate800),
                shape = RoundedCornerShape(6.dp),
                modifier = Modifier.weight(1f).height(32.dp),
                contentPadding = PaddingValues(horizontal = 2.dp, vertical = 0.dp)
            ) { Text("TXT", fontSize = 10.sp, color = White) }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth(0.9f), colors = CardDefaults.cardColors(containerColor = Slate900)) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("报告摘要", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = White)
                Spacer(modifier = Modifier.height(8.dp))
                Text("设备总数: ${result.devices.size}", fontSize = 12.sp, color = Gray400)
                Text("在线设备: ${result.onlineCount}  |  离线: ${result.offlineCount}", fontSize = 12.sp, color = Gray400)
                Text("健康评分: ${health.total}/100 (${health.scoreLabel})", fontSize = 12.sp, color = Gray400)
                Text("诊断问题: ${findings.count { it.severity != FindingSeverity.GOOD }} 项", fontSize = 12.sp, color = Gray400)
                Text("Generated by NetDiagnose", fontSize = 10.sp, color = Gray500, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

private fun exportJSON(context: Context, result: ScanResult, findings: List<DiagnosticFinding>, health: HealthBreakdown) {
    try {
        val sb = StringBuilder()
        sb.appendLine("{")
        sb.appendLine("  \"app\": \"NetDiagnose\",")
        sb.appendLine("  \"timestamp\": ${result.timestamp},")
        sb.appendLine("  \"scanDuration\": ${result.scanDuration},")
        sb.appendLine("  \"config\": {")
        sb.appendLine("    \"subnet\": \"${result.config.subnet}.0/24\",")
        sb.appendLine("    \"gateway\": \"${result.config.gatewayIP}\"")
        sb.appendLine("  },")
        sb.appendLine("  \"health\": {")
        sb.appendLine("    \"score\": ${health.total},")
        sb.appendLine("    \"label\": \"${health.scoreLabel}\"")
        sb.appendLine("  },")
        sb.appendLine("  \"devices\": [")
        result.devices.forEachIndexed { i, d ->
            sb.appendLine("    {")
            sb.appendLine("      \"ip\": \"${d.ipAddress}\",")
            sb.appendLine("      \"mac\": \"${d.macAddress ?: ""}\",")
            sb.appendLine("      \"vendor\": \"${d.vendor ?: ""}\",")
            sb.appendLine("      \"type\": \"${d.deviceType.label}\",")
            sb.append("      \"online\": ${d.isOnline}")
            d.latencyMs?.let { sb.appendLine(","); sb.append("      \"latencyMs\": ${it.roundToInt()}") }
            if (d.openPorts.isNotEmpty()) { sb.appendLine(","); sb.append("      \"ports\": [${d.openPorts.joinToString(",")}]") }
            sb.appendLine()
            sb.append("    }")
            if (i < result.devices.size - 1) sb.append(",")
            sb.appendLine()
        }
        sb.appendLine("  ]")
        sb.appendLine("}")
        val file = File(context.cacheDir, "NetDiagnose_Report.json")
        file.writeText(sb.toString())
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "分享诊断报告"))
    } catch (e: Exception) {
        Toast.makeText(context, "导出失败: ${e.message}", Toast.LENGTH_SHORT).show()
    }
}

private fun exportCSV(context: Context, result: ScanResult) {
    try {
        val sb = StringBuilder()
        sb.appendLine("IP,MAC,厂商,类型,在线,延迟(ms),端口")
        result.devices.forEach { d ->
            sb.appendLine("${d.ipAddress},${d.macAddress ?: ""},${d.vendor ?: ""},${d.deviceType.label},${d.isOnline},${d.latencyMs?.roundToInt() ?: ""},\"${d.openPorts.joinToString(";")}\"")
        }
        val file = File(context.cacheDir, "NetDiagnose_Devices.csv")
        file.writeText(sb.toString())
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/csv"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "分享设备清单"))
    } catch (e: Exception) {
        Toast.makeText(context, "导出失败: ${e.message}", Toast.LENGTH_SHORT).show()
    }
}

private fun exportHTML(context: Context, result: ScanResult, findings: List<DiagnosticFinding>, health: HealthBreakdown) {
    try {
        val sb = StringBuilder()
        sb.appendLine("<!DOCTYPE html><html lang=\"zh\"><head><meta charset=\"utf-8\">")
        sb.appendLine("<title>NetDiagnose 报告</title>")
        sb.appendLine("<style>body{font-family:-apple-system,sans-serif;background:#0f172a;color:#e2e8f0;max-width:680px;margin:0 auto;padding:24px}")
        sb.appendLine("h1{color:#38bdf8}h2{color:#fbbf24}.score{font-size:48px;font-weight:bold;color:#38bdf8}")
        sb.appendLine(".card{background:#1e293b;border-radius:8px;padding:16px;margin:12px 0}")
        sb.appendLine("table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #334155}")
        sb.appendLine(".online{color:#22c55e}.offline{color:#64748b}</style></head><body>")
        sb.appendLine("<h1>NetDiagnose 网络诊断报告</h1>")
        sb.appendLine("<p>扫描时间: ${result.timestamp} · 耗时: ${result.scanDuration}s</p>")
        sb.appendLine("<p>子网: ${result.config.subnet}.0/24 · 网关: ${result.config.gatewayIP}</p>")
        sb.appendLine("<div class=\"card\"><h2>健康评分</h2>")
        sb.appendLine("<div class=\"score\">${health.total}%</div>")
        sb.appendLine("<p>${health.scoreLabel}</p></div>")
        if (findings.isNotEmpty()) {
            sb.appendLine("<div class=\"card\"><h2>诊断发现</h2><ul>")
            findings.forEach { sb.appendLine("<li>[${it.severity.label}] ${it.title}: ${it.explanation}</li>") }
            sb.appendLine("</ul></div>")
        }
        sb.appendLine("<div class=\"card\"><h2>设备清单 (${result.devices.size})</h2><table>")
        sb.appendLine("<tr><th>IP</th><th>MAC</th><th>厂商</th><th>类型</th><th>状态</th><th>延迟</th></tr>")
        result.devices.forEach { d ->
            val state = if (d.isOnline) "<span class=\"online\">在线</span>" else "<span class=\"offline\">离线</span>"
            sb.appendLine("<tr><td>${d.ipAddress}</td><td>${d.macAddress ?: ""}</td><td>${d.vendor ?: ""}</td><td>${d.deviceType.label}</td><td>$state</td><td>${d.latencyMs?.roundToInt() ?: ""}ms</td></tr>")
        }
        sb.appendLine("</table></div><p style=\"text-align:center;color:#475569\">Generated by NetDiagnose</p></body></html>")
        val file = File(context.cacheDir, "NetDiagnose_Report.html")
        file.writeText(sb.toString())
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/html"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "分享诊断报告"))
    } catch (e: Exception) {
        Toast.makeText(context, "导出失败: ${e.message}", Toast.LENGTH_SHORT).show()
    }
}

private fun exportTXT(context: Context, result: ScanResult, findings: List<DiagnosticFinding>, health: HealthBreakdown) {
    try {
        val sb = StringBuilder()
        sb.appendLine("══════════════════════════════════════")
        sb.appendLine("  NetDiagnose 网络诊断报告")
        sb.appendLine("══════════════════════════════════════")
        sb.appendLine("扫描时间: ${result.timestamp}")
        sb.appendLine("耗时: ${result.scanDuration}s")
        sb.appendLine("子网: ${result.config.subnet}.0/24")
        sb.appendLine("网关: ${result.config.gatewayIP}")
        sb.appendLine()
        sb.appendLine("── 健康评分 ──")
        sb.appendLine("${health.total}% — ${health.scoreLabel}")
        if (findings.isNotEmpty()) {
            sb.appendLine()
            sb.appendLine("── 诊断发现 ──")
            findings.forEach { sb.appendLine("[${it.severity.label}] ${it.title}: ${it.explanation}") }
        }
        sb.appendLine()
        sb.appendLine("── 设备清单 (${result.devices.size}台) ──")
        sb.appendLine("IP              MAC               厂商              类型      状态  延迟")
        sb.appendLine("──              ───               ──              ──      ──  ──")
        result.devices.forEach { d ->
            val ip = d.ipAddress.padEnd(16)
            val mac = (d.macAddress ?: "").padEnd(18)
            val vendor = (d.vendor ?: "").take(16).padEnd(16)
            val type = d.deviceType.label.padEnd(8)
            val state = if (d.isOnline) "在线" else "离线"
            val lat = "${d.latencyMs?.roundToInt() ?: ""}ms"
            sb.appendLine("$ip $mac $vendor $type $state  $lat")
        }
        sb.appendLine()
        sb.appendLine("Generated by NetDiagnose")
        val file = File(context.cacheDir, "NetDiagnose_Report.txt")
        file.writeText(sb.toString())
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "分享诊断报告"))
    } catch (e: Exception) {
        Toast.makeText(context, "导出失败: ${e.message}", Toast.LENGTH_SHORT).show()
    }
}
