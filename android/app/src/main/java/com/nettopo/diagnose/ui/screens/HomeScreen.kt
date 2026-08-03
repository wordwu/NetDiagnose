package com.nettopo.diagnose.ui.screens

import android.content.Context
import android.net.wifi.WifiManager
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nettopo.diagnose.data.models.*
import com.nettopo.diagnose.data.scanner.LocalNetworkInfo
import com.nettopo.diagnose.data.scanner.NetworkScanner
import com.nettopo.diagnose.ui.theme.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun HomeScreen(
    errorMsg: String? = null,
    onStartScan: (ScanConfig, ScanMode) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var detectedInfo by remember { mutableStateOf<LocalNetworkInfo?>(null) }
    var detecting by remember { mutableStateOf(true) }
    var selectedMode by remember { mutableStateOf(ScanMode.STANDARD) }
    var showManual by remember { mutableStateOf(false) }
    var manualSubnet by remember { mutableStateOf("") }
    var wifiNetworks by remember { mutableStateOf<List<NetworkScanner.WiFiNetwork>>(emptyList()) }
    var showWiFi by remember { mutableStateOf(false) }
    var wifiScanning by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        detectedInfo = withContext(Dispatchers.IO) {
            NetworkScanner.detectLocalNetwork(context)
        }
        detecting = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Slate950)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(24.dp))

        // ── App Branding ───────────────────────────────────────
        Box(
            modifier = Modifier.size(64.dp).clip(CircleShape)
                .background(Brush.linearGradient(listOf(Cyan400, Cyan600))),
            contentAlignment = Alignment.Center
        ) {
            Text("\uD83D\uDEE1\uFE0F", fontSize = 28.sp)
        }
        Spacer(modifier = Modifier.height(12.dp))
        Text("NetDiagnose", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = White)
        Text("免费网络健康诊断 · 一键扫描全屋设备", fontSize = 12.sp, color = Gray400, modifier = Modifier.padding(top = 4.dp))

        Spacer(modifier = Modifier.height(16.dp))

        // ── Network Info Card (portrait stacked) ──────────────
        if (detecting) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
                CircularProgressIndicator(modifier = Modifier.size(14.dp), color = Cyan400, strokeWidth = 2.dp)
                Spacer(modifier = Modifier.width(8.dp))
                Text("正在检测本地网络...", fontSize = 13.sp, color = Gray400)
            }
        } else if (detectedInfo != null) {
            val info = detectedInfo!!
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = Cyan400.copy(alpha = 0.06f)),
                shape = RoundedCornerShape(10.dp)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    // Interface + local IP row
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("\uD83D\uDCE1", fontSize = 13.sp)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(info.interfaceName, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Green500)
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    // IP info grid — 2 columns
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        InfoChip("本机 IP", info.localIP)
                        InfoChip("网关", info.gatewayIP)
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        InfoChip("子网", "${info.subnet}.0/24")
                        InfoChip("掩码", info.netmask)
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // ── WiFi Scan Button ───────────────────────────────────
        OutlinedButton(
            onClick = {
                scope.launch {
                    wifiScanning = true
                    showWiFi = true
                    wifiNetworks = withContext(Dispatchers.IO) {
                        NetworkScanner.scanWiFi(context)
                    }
                    wifiScanning = false
                    if (wifiNetworks.isEmpty()) {
                        Toast.makeText(context, "未扫描到 WiFi（请开启位置服务后重试）", Toast.LENGTH_SHORT).show()
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(8.dp),
            border = BorderStroke(1.dp, Cyan400.copy(alpha = 0.2f)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = White)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("\uD83D\uDCF6", fontSize = 14.sp)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    if (showWiFi && wifiNetworks.isNotEmpty())
                        "周围 WiFi (${wifiNetworks.size}个)"
                    else if (wifiScanning) "扫描中..."
                    else "扫描周围 WiFi 网络",
                    fontSize = 13.sp, color = Cyan400.copy(alpha = 0.7f)
                )
            }
        }

        // WiFi results
        AnimatedVisibility(visible = showWiFi && wifiNetworks.isNotEmpty()) {
            Card(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                colors = CardDefaults.cardColors(containerColor = Slate900),
                shape = RoundedCornerShape(8.dp)
            ) {
                Column(modifier = Modifier.padding(8.dp).heightIn(max = 280.dp).verticalScroll(rememberScrollState())) {
                    wifiNetworks.forEach { wifi ->
                        val signal = when { wifi.rssi >= -50 -> "\uD83D\uDFE2"; wifi.rssi >= -70 -> "\uD83D\uDFE1"; else -> "\uD83D\uDD34" }
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(signal, fontSize = 11.sp)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(wifi.ssid, fontSize = 12.sp, color = White, modifier = Modifier.weight(1f), maxLines = 1)
                            Text("${wifi.rssi} dBm", fontSize = 10.sp, color = Gray400)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("${wifi.frequency}MHz", fontSize = 10.sp, color = Gray500)
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // ── Scan Mode Picker (horizontal scroll for narrow screens) ──
        Text("扫描模式", fontSize = 11.sp, color = Gray400)
        Spacer(modifier = Modifier.height(6.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            ScanMode.entries.forEach { mode ->
                val selected = mode == selectedMode
                Button(
                    onClick = { selectedMode = mode },
                    modifier = Modifier.height(34.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (selected) Cyan400.copy(alpha = 0.15f) else Slate800,
                        contentColor = if (selected) Cyan400 else Gray400
                    ),
                    shape = RoundedCornerShape(8.dp),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)
                ) {
                    Text(mode.label, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
        Text(selectedMode.subtitle, fontSize = 10.sp, color = Gray500, modifier = Modifier.padding(top = 4.dp))

        Spacer(modifier = Modifier.height(16.dp))

        // ── One-Click Scan Button ──────────────────────────────
        Button(
            onClick = {
                detectedInfo?.let { info ->
                    val config = ScanConfig(
                        subnet = info.subnet,
                        gatewayIP = info.gatewayIP,
                        localIP = info.localIP,
                        netmask = info.netmask,
                        interfaceName = info.interfaceName
                    )
                    onStartScan(config, selectedMode)
                }
            },
            modifier = Modifier.fillMaxWidth().height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
            shape = RoundedCornerShape(12.dp),
            contentPadding = PaddingValues(0.dp),
            enabled = detectedInfo != null
        ) {
            Box(
                modifier = Modifier.fillMaxSize()
                    .background(Brush.linearGradient(listOf(Cyan400, Cyan600))),
                contentAlignment = Alignment.Center
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("\u25B6", fontSize = 18.sp, color = White)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("一键诊断", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = White)
                }
            }
        }

        if (errorMsg != null) {
            Text(errorMsg, fontSize = 12.sp, color = Red500, modifier = Modifier.padding(top = 8.dp))
        }

        // ── Manual Subnet ──────────────────────────────────────
        TextButton(
            onClick = { showManual = !showManual },
            modifier = Modifier.padding(top = 8.dp)
        ) {
            Text(
                if (showManual) "收起" else "\u270F\uFE0F 手动输入子网",
                fontSize = 12.sp, color = Cyan400.copy(alpha = 0.6f)
            )
        }
        AnimatedVisibility(visible = showManual) {
            Row(
                modifier = Modifier.padding(top = 6.dp).fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = manualSubnet,
                    onValueChange = { manualSubnet = it },
                    placeholder = { Text("192.168.1.0/24", fontSize = 13.sp, color = Gray500) },
                    modifier = Modifier.weight(1f).height(48.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = White,
                        unfocusedTextColor = White,
                        focusedBorderColor = Cyan400,
                        unfocusedBorderColor = Slate800,
                        cursorColor = Cyan400
                    ),
                    singleLine = true,
                    shape = RoundedCornerShape(8.dp)
                )
                Button(
                    onClick = {
                        if (manualSubnet.isNotBlank()) {
                            val parts = manualSubnet.trim().split("/")
                            val base = parts[0].substringBeforeLast(".")
                            val ip = parts[0].substringAfterLast(".")
                            val config = ScanConfig(
                                subnet = base,
                                gatewayIP = if (ip.isNotEmpty()) "$base.$ip" else "$base.1",
                                localIP = detectedInfo?.localIP ?: "$base.100",
                                netmask = "255.255.255.0",
                                interfaceName = detectedInfo?.interfaceName ?: "wlan0"
                            )
                            onStartScan(config, selectedMode)
                        }
                    },
                    enabled = manualSubnet.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = Cyan400),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text("扫描", fontSize = 13.sp, color = Slate950, fontWeight = FontWeight.Medium)
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // ── Feature Icons Footer ───────────────────────────────
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            FeatureItem("\uD83D\uDCF1", "设备识别")
            FeatureItem("\u26A1", "延迟检测")
            FeatureItem("\uD83D\uDC9A", "健康评分")
            FeatureItem("\uD83D\uDCC4", "PDF 报告")
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun InfoChip(label: String, value: String) {
    Row {
        Text("$label ", fontSize = 11.sp, color = Gray400)
        Text(value, fontSize = 12.sp, color = Cyan400, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun FeatureItem(icon: String, text: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(icon, fontSize = 20.sp)
        Spacer(modifier = Modifier.height(4.dp))
        Text(text, fontSize = 10.sp, color = Gray400)
    }
}
