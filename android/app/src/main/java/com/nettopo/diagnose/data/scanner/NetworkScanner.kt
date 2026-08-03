package com.nettopo.diagnose.data.scanner

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import com.nettopo.diagnose.data.models.*
import kotlinx.coroutines.*
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.io.InputStreamReader
import java.net.*

// ─── Local Network Info ────────────────────────────────────────
data class LocalNetworkInfo(
    val subnet: String,
    val gatewayIP: String,
    val localIP: String,
    val netmask: String = "255.255.255.0",
    val interfaceName: String = "wlan0",
    val ssid: String? = null
)

data class PingResult(val ip: String, val hostname: String?)

// ─── Scanner Object ────────────────────────────────────────────

object NetworkScanner {

    /** Detect local network — subnet, gateway, local IP */
    fun detectLocalNetwork(context: Context): LocalNetworkInfo? {
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = cm.activeNetwork ?: return fallback()
            val caps = cm.getNetworkCapabilities(network) ?: return fallback()

            var localIP: String? = null
            var gatewayIP: String? = null
            var ifaceName = "wlan0"

            // Try WifiManager for detailed info
            try {
                val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val conn = wm.connectionInfo
                if (conn != null) {
                    val ip = conn.ipAddress
                    if (ip != 0) {
                        localIP = String.format(
                            "%d.%d.%d.%d",
                            ip and 0xff,
                            ip shr 8 and 0xff,
                            ip shr 16 and 0xff,
                            ip shr 24 and 0xff
                        )
                    }
                    val dhcp = wm.dhcpInfo
                    if (dhcp != null && dhcp.gateway != 0) {
                        gatewayIP = String.format(
                            "%d.%d.%d.%d",
                            dhcp.gateway and 0xff,
                            dhcp.gateway shr 8 and 0xff,
                            dhcp.gateway shr 16 and 0xff,
                            dhcp.gateway shr 24 and 0xff
                        )
                    }
                    ifaceName = "wlan0"
                }
            } catch (_: Exception) {}

            // Fallback via NetworkInterface
            if (localIP == null) {
                val ifaces = NetworkInterface.getNetworkInterfaces()
                while (ifaces.hasMoreElements()) {
                    val iface = ifaces.nextElement()
                    if (iface.isLoopback || !iface.isUp) continue
                    val name = iface.name.lowercase()
                    if (name.startsWith("wlan") || name.startsWith("eth")) {
                        ifaceName = iface.name
                        val addrs = iface.inetAddresses
                        while (addrs.hasMoreElements()) {
                            val addr = addrs.nextElement()
                            if (addr is Inet4Address && addr.isSiteLocalAddress) {
                                localIP = addr.hostAddress ?: continue
                                break
                            }
                        }
                        if (localIP != null) break
                    }
                }
            }

            val ip = localIP ?: return fallback()
            val parts = ip.split(".")
            if (parts.size != 4) return fallback()
            val subnet = "${parts[0]}.${parts[1]}.${parts[2]}"
            val gw = gatewayIP ?: "$subnet.1"

            return LocalNetworkInfo(subnet, gw, ip, "255.255.255.0", ifaceName)
        } catch (_: Exception) {
            return fallback()
        }
    }

    private fun fallback() = LocalNetworkInfo("192.168.1", "192.168.1.1", "192.168.1.100")

    // ─── Ping Sweep ────────────────────────────────────────────

    /** Fast ping using /system/bin/ping — much more reliable than InetAddress.isReachable on Android */
    suspend fun pingSweep(
        subnet: String,
        skipIPs: List<String> = emptyList(),
        maxConcurrent: Int = 24,
        timeoutMs: Int = 2000
    ): List<PingResult> = withContext(Dispatchers.IO) {
        val ips = (1..254).map { "$subnet.$it" }.filter { it !in skipIPs }
        val results = mutableListOf<PingResult>()

        val semaphore = java.util.concurrent.Semaphore(maxConcurrent)
        val jobs = ips.map { ip ->
            CoroutineScope(Dispatchers.IO).async {
                semaphore.acquire()
                try {
                    val proc = Runtime.getRuntime().exec(
                        arrayOf("ping", "-c", "1", "-W", "2", ip)
                    )
                    proc.waitFor()
                    val output = proc.inputStream.bufferedReader().readText()
                    if (output.contains("1 received") || output.contains("ttl=")) {
                        synchronized(results) {
                            results.add(PingResult(ip, null))
                        }
                    }
                    Unit // suppress expression warning
                } catch (_: Exception) {
                    // Fallback: try TCP port 80/443
                    try {
                        val s = java.net.Socket()
                        s.connect(java.net.InetSocketAddress(ip, 80), 1000)
                        s.close()
                        synchronized(results) {
                            results.add(PingResult(ip, null))
                        }
                    } catch (_: Exception) {
                        try {
                            val s = java.net.Socket()
                            s.connect(java.net.InetSocketAddress(ip, 443), 1000)
                            s.close()
                            synchronized(results) {
                                results.add(PingResult(ip, null))
                            }
                        } catch (_: Exception) {
                            try {
                                val s = java.net.Socket()
                                s.connect(java.net.InetSocketAddress(ip, 8080), 1000)
                                s.close()
                                synchronized(results) {
                                    results.add(PingResult(ip, null))
                                }
                            } catch (_: Exception) {}
                        }
                    }
                } finally {
                    semaphore.release()
                }
            }
        }
        jobs.awaitAll()
        results
    }

    // ─── ARP Table ─────────────────────────────────────────────

    fun getLocalMac(ifaceName: String?): String? {
        try {
            val ifaces = NetworkInterface.getNetworkInterfaces()
            while (ifaces.hasMoreElements()) {
                val iface = ifaces.nextElement()
                if (ifaceName != null && iface.name != ifaceName) continue
                if (iface.isLoopback) continue
                val hw = iface.hardwareAddress
                if (hw != null && hw.size == 6) {
                    return hw.joinToString(":") { String.format("%02x", it) }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    data class ArpEntry(val ip: String, val mac: String, val vendor: String?)

    fun readArpTable(): List<ArpEntry> {
        val entries = mutableListOf<ArpEntry>()

        // Method 1: /proc/net/arp
        try {
            val file = File("/proc/net/arp")
            if (file.canRead()) {
                val reader = BufferedReader(FileReader(file))
                reader.useLines { lines ->
                    lines.drop(1).forEach { line ->
                        val parts = line.trim().split("\\s+".toRegex())
                        if (parts.size >= 4) {
                            val ip = parts[0]
                            val mac = parts[3]
                            if (mac != "00:00:00:00:00:00" && mac != "(incomplete)") {
                                entries.add(ArpEntry(ip, mac, null))
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // Method 2: ip neigh (try multiple paths)
        try {
            val ipPaths = arrayOf("/system/bin/ip", "/system/xbin/ip", "/sbin/ip", "/vendor/bin/ip")
            for (ipPath in ipPaths) {
                try {
                    val proc = Runtime.getRuntime().exec(arrayOf(ipPath, "neigh"))
                    proc.waitFor()
                    if (proc.exitValue() == 0) {
                        proc.inputStream.bufferedReader().readText().lines().forEach { line ->
                            val parts = line.trim().split("\\s+".toRegex())
                            val lladdrIdx = parts.indexOf("lladdr")
                            if (lladdrIdx >= 0 && lladdrIdx + 1 < parts.size) {
                                val ip = parts[0]
                                val mac = parts[lladdrIdx + 1]
                                if (ip.contains(".") && mac.matches(Regex("[0-9a-fA-F:]+"))
                                    && mac != "00:00:00:00:00:00"
                                    && entries.none { it.ip == ip }) {
                                    entries.add(ArpEntry(ip, mac, null))
                                }
                            }
                        }
                        if (entries.isNotEmpty()) break
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}

        // Method 3: arp command
        try {
            val proc = Runtime.getRuntime().exec(arrayOf("arp", "-a"))
            proc.waitFor()
            if (proc.exitValue() == 0) {
                proc.inputStream.bufferedReader().readText().lines().forEach { line ->
                    // e.g.: "? (192.168.1.5) at aa:bb:cc:dd:ee:ff [ether] on wlan0"
                    val ipMatch = Regex("\\(([\\d.]+)\\)").find(line) ?: return@forEach
                    val macMatch = Regex("([0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2})").find(line) ?: return@forEach
                    val ip = ipMatch.groupValues[1]
                    val mac = macMatch.value
                    if (mac != "00:00:00:00:00:00" && entries.none { it.ip == ip }) {
                        entries.add(ArpEntry(ip, mac, null))
                    }
                }
            }
        } catch (_: Exception) {}

        // Method 4: fallback via shell
        if (entries.isEmpty()) {
            try {
                val cmds = arrayOf("cat /proc/net/arp 2>/dev/null", "ip neigh 2>/dev/null", "arp -a 2>/dev/null", "busybox arp -a 2>/dev/null")
                for (cmd in cmds) {
                    val proc = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                    proc.waitFor()
                    if (proc.exitValue() == 0) {
                        proc.inputStream.bufferedReader().readText().lines().forEach { line ->
                            val macMatch = Regex("([0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2}:[0-9a-fA-F]{1,2})").find(line)
                            val ipMatch = Regex("([\\d]+\\.[\\d]+\\.[\\d]+\\.[\\d]+)").find(line)
                            if (macMatch != null && ipMatch != null) {
                                val ip = ipMatch.value
                                val mac = macMatch.value
                                if (mac != "00:00:00:00:00:00" && entries.none { it.ip == ip }) {
                                    entries.add(ArpEntry(ip, mac, null))
                                }
                            }
                        }
                        if (entries.isNotEmpty()) break
                    }
                }
            } catch (_: Exception) {}
        }

        return entries
    }

    // ─── Port Scan ─────────────────────────────────────────────

    suspend fun checkPorts(ip: String, mode: ScanMode): List<Int> = withContext(Dispatchers.IO) {
        val portList = when (mode) {
            ScanMode.QUICK -> intArrayOf(80, 443, 22, 53)
            ScanMode.STANDARD -> intArrayOf(80, 443, 22, 53, 8080, 8443, 5000, 3000, 554, 1900, 5353, 9100)
            ScanMode.DEEP -> intArrayOf(80, 443, 22, 21, 23, 25, 53, 110, 139, 143, 445, 548, 587, 993, 995, 1723, 3306, 3389, 5000, 5432, 5900, 6379, 8000, 8080, 8443, 9090, 9100, 27017)
        }
        val open = mutableListOf<Int>()
        val semaphore = java.util.concurrent.Semaphore(mode.portConcurrency)
        val timeout = mode.portTimeout.toInt()
        val jobs = portList.map { port ->
            CoroutineScope(Dispatchers.IO).async {
                semaphore.acquire()
                try {
                    val sock = Socket()
                    sock.soTimeout = timeout
                    sock.connect(InetSocketAddress(ip, port), timeout)
                    sock.close()
                    synchronized(open) { open.add(port) }
                } catch (_: Exception) {} finally {
                    semaphore.release()
                }
            }
        }
        jobs.awaitAll()
        open.sorted()
    }

    // ─── Service Discovery ──────────────────────────────────────

    /** SSDP (UPnP) discovery — finds smart TVs, printers, NAS, routers etc. */
    suspend fun discoverSSDP(timeoutMs: Int = 3000): List<String> = withContext(Dispatchers.IO) {
        val ips = mutableSetOf<String>()
        try {
            val socket = DatagramSocket()
            socket.soTimeout = timeoutMs
            val group = InetAddress.getByName("239.255.255.250")
            val query = "M-SEARCH * HTTP/1.1\r\nHost: 239.255.255.250:1900\r\nMan: \"ssdp:discover\"\r\n"
            val queryBytes = query.toByteArray()
            socket.send(DatagramPacket(queryBytes, queryBytes.size, group, 1900))

            val buf = ByteArray(4096)
            val start = System.currentTimeMillis()
            while (System.currentTimeMillis() - start < timeoutMs) {
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    socket.receive(packet)
                    val resp = String(packet.data, 0, packet.length)
                    // Extract IP from packet sender
                    if (packet.address.isSiteLocalAddress) {
                        ips.add(packet.address.hostAddress)
                    }
                } catch (_: java.net.SocketTimeoutException) { break
                } catch (_: Exception) {}
            }
            socket.close()
        } catch (_: Exception) {}
        ips.toList()
    }

    /** mDNS discovery — finds Bonjour/Avahi devices (Apple, printers, IoT) */
    suspend fun discoverMDNS(timeoutMs: Int = 3000): List<String> = withContext(Dispatchers.IO) {
        val ips = mutableSetOf<String>()
        try {
            val socket = MulticastSocket(5353)
            socket.soTimeout = timeoutMs
            val group = InetAddress.getByName("224.0.0.251")
            socket.joinGroup(group)
            // Simple mDNS query for any service
            val query = byteArrayOf(
                0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
                '_'.code.toByte(), 's'.code.toByte(), 'e'.code.toByte(), 'r'.code.toByte(),
                'v'.code.toByte(), 'i'.code.toByte(), 'c'.code.toByte(), 'e'.code.toByte(),
                's'.code.toByte(), '_'.code.toByte(), 'u'.code.toByte(), 'd'.code.toByte(),
                'p'.code.toByte(), '_'.code.toByte(), 'l'.code.toByte(), 'o'.code.toByte(),
                'c'.code.toByte(), 'a'.code.toByte(), 'l'.code.toByte(),
                0, 0, 0x0c.toByte(), 0, 0, 1
            )
            socket.send(DatagramPacket(query, query.size, group, 5353))

            val buf = ByteArray(4096)
            val start = System.currentTimeMillis()
            while (System.currentTimeMillis() - start < timeoutMs) {
                try {
                    val packet = DatagramPacket(buf, buf.size)
                    socket.receive(packet)
                    if (packet.address.isSiteLocalAddress) {
                        ips.add(packet.address.hostAddress)
                    }
                } catch (_: java.net.SocketTimeoutException) { break
                } catch (_: Exception) {}
            }
            socket.leaveGroup(group)
            socket.close()
        } catch (_: Exception) {}
        ips.toList()
    }

    // ─── Latency ───────────────────────────────────────────────

    suspend fun measureLatency(ip: String, samples: Int = 3): Double? = withContext(Dispatchers.IO) {
        val times = mutableListOf<Long>()
        repeat(samples) {
            val t0 = System.nanoTime()
            try {
                val addr = InetAddress.getByName(ip)
                addr.isReachable(500)
                times.add((System.nanoTime() - t0) / 1_000_000)
            } catch (_: Exception) {}
        }
        if (times.isEmpty()) null else times.average()
    }

    // ─── Device Guessing ───────────────────────────────────────

    fun guessDevice(
        ip: String, mac: String?, vendor: String?, hostname: String?,
        ports: List<Int>, services: List<String> = emptyList(), gatewayIP: String? = null
    ): DeviceType {
        val hn = hostname?.lowercase() ?: ""
        val vd = vendor?.lowercase() ?: ""
        val portSet = ports.toSet()
        val svcSet = services.toSet()

        // 1) 网关：实际网关 IP 优先，其次 .1 兜底
        if (ip == gatewayIP || (gatewayIP == null && ip.endsWith(".1"))) return DeviceType.ROUTER

        // 2) mDNS/Bonjour 自报（设备自己报的类型最可靠）
        if (svcSet.any { it.contains("printer") || it.contains("pdl-datastream") || it.contains("ipp") }) return DeviceType.PRINTER
        if (svcSet.any { it.contains("smb") || it.contains("afpovertcp") }) return DeviceType.NAS
        if (svcSet.any { it.contains("airplay") || it.contains("googlecast") || it.contains("spotify") || it.contains("raop") }) return DeviceType.TV
        if (svcSet.any { it.contains("hap") || it.contains("homekit") || it.contains("miio") }) return DeviceType.IOT

        // 3) 主机名具体设备词（先于品牌词，避免"小米插座"被认成手机）
        val nasWords = listOf("nas", "diskstation", "synology", "qnap", "wdmycloud", "freenas", "truenas", "nvr", "storage")
        val camWords = listOf("camera", "cam-", "cam_", "ipc", "hikvision", "dahua", "reolink", "doorbell", "cctv")
        val printerWords = listOf("printer", "brother", "canon-", "epson", "xerox", "laserjet", "deskjet")
        val iotWords = listOf("plug", "socket", "sensor", "light", "bulb", "switch", "outlet", "curtain", "lock", "door",
            "smoke", "leak", "motion", "contact", "thermometer", "humidifier", "purifier", "water", "heater",
            "yeelight", "philips-hue", "shelly", "sonoff", "tasmota", "esphome", "tuya", "aqara", "lumi", "viomi",
            "chuangmi", "vacuum", "speaker", "soundbar", "settop", "tv-box", "dongle")
        val phoneWords = listOf("iphone", "ipad", "android", "pixel", "oneplus", "redmi", "honor",
            "galaxy", "samsung-sm", "huawei-p", "huawei-mate", "huawei-nova")

        for (w in nasWords) if (hn.contains(w) || vd.contains(w)) return DeviceType.NAS
        for (w in camWords) if (hn.contains(w)) return DeviceType.CAMERA
        for (w in printerWords) if (hn.contains(w) || vd.contains(w)) return DeviceType.PRINTER
        for (w in iotWords) if (hn.contains(w) || vd.contains(w)) return DeviceType.IOT
        for (w in phoneWords) if (hn.contains(w)) return DeviceType.PHONE

        // 4) 端口签名（组合比单端口可靠）
        if (portSet.containsAll(setOf(5000, 5001))) return DeviceType.NAS
        if (portSet.containsAll(setOf(445, 548))) return DeviceType.NAS
        if (portSet.containsAll(setOf(515, 631))) return DeviceType.PRINTER
        if (portSet.contains(554) || portSet.contains(5543)) return DeviceType.CAMERA
        if (portSet.contains(1883) || portSet.contains(8883)) return DeviceType.IOT
        if (portSet.contains(5000) || portSet.contains(5001)) return DeviceType.NAS
        if (portSet.contains(515) || portSet.contains(631) || portSet.contains(9100)) return DeviceType.PRINTER

        // 5) 手机品牌厂商：无服务端口（或只有 AirDrop/mDNS）→ 手机
        val phoneVendors = listOf("apple", "samsung", "xiaomi", "huawei", "honor", "oppo", "vivo",
            "oneplus", "google", "motorola", "nokia", "meizu", "realme", "zte")
        if (phoneVendors.any { vd.contains(it) } &&
            (portSet.isEmpty() || portSet.all { it == 62078 || it == 5353 || it == 5000 })) {
            return DeviceType.PHONE
        }

        // 6) 网络设备品牌：开 Web 管理端口 → 路由器；否则交换机/AP
        val networkBrands = listOf("asus", "tp-link", "tplink", "netgear", "ubiquiti", "mikrotik", "cisco",
            "d-link", "dlink", "tenda", "mercury", "huawei", "zte", "linksys", "arris", "juniper", "arista")
        if (networkBrands.any { vd.contains(it) || hn.contains(it) }) {
            if (portSet.any { it == 80 || it == 443 || it == 8080 || it == 8443 }) return DeviceType.ROUTER
            return DeviceType.SWITCH
        }

        // 7) 厂商兜底
        if (vd.contains("intel") || vd.contains("dell") || vd.contains("hp") || vd.contains("lenovo") ||
            vd.contains("msi") || vd.contains("acer") || vd.contains("raspberry") || vd.contains("microsoft")) return DeviceType.COMPUTER
        if (vd.contains("sony") || vd.contains("lg")) return DeviceType.TV
        if (vd.contains("nest") || vd.contains("ring") || vd.contains("arlo") || vd.contains("axis")) return DeviceType.CAMERA
        if (vd.contains("synology") || vd.contains("qnap") || vd.contains("seagate") || vd.contains("western")) return DeviceType.NAS

        // 8) 端口兜底
        if (portSet.any { it == 80 || it == 443 || it == 8080 || it == 22 || it == 8443 }) return DeviceType.COMPUTER
        if (portSet.contains(3389) || portSet.contains(5900)) return DeviceType.COMPUTER

        return DeviceType.UNKNOWN
    }

    // ─── OUI Lookup ────────────────────────────────────────────

    fun lookupVendor(mac: String): String? {
        return try {
            OUIDatabase.lookup(mac)
        } catch (_: Exception) { null }
    }

    // ─── WiFi Scan ─────────────────────────────────────────────

    data class WiFiNetwork(
        val ssid: String,
        val bssid: String,
        val rssi: Int,
        val frequency: Int,
        val capabilities: String
    )

    fun scanWiFi(context: Context): List<WiFiNetwork> {
        val results = mutableListOf<WiFiNetwork>()

        // Method 1: WifiManager — needs location ON + permission
        try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wm.scanResults?.forEach { sr ->
                results.add(WiFiNetwork(
                    ssid = sr.SSID.ifEmpty { "<隐藏>" },
                    bssid = sr.BSSID,
                    rssi = sr.level,
                    frequency = sr.frequency,
                    capabilities = sr.capabilities
                ))
            }
        } catch (_: Exception) {}

        // Method 2: cmd wifi list-scan-results
        if (results.isEmpty()) {
            try {
                val proc = Runtime.getRuntime().exec(arrayOf("cmd", "wifi", "list-scan-results"))
                proc.waitFor()
                proc.inputStream.bufferedReader().readText().lines().drop(1).forEach { line ->
                    val parts = line.trim().split("\\s+".toRegex())
                    if (parts.size >= 5 && parts[0].matches(Regex("[0-9a-fA-F:]+"))) {
                        results.add(WiFiNetwork(
                            bssid = parts[0],
                            frequency = parts[1].toIntOrNull() ?: 0,
                            rssi = parts[2].toIntOrNull() ?: 0,
                            ssid = parts.drop(4).joinToString(" ").ifEmpty { "<隐藏>" },
                            capabilities = ""
                        ))
                    }
                }
            } catch (_: Exception) {}
        }

        // Method 3: dumpsys wifi
        if (results.isEmpty()) {
            try {
                val proc = Runtime.getRuntime().exec(arrayOf("dumpsys", "wifi"))
                proc.waitFor()
                val out = proc.inputStream.bufferedReader().readText()
                Regex("SSID: (.+)").findAll(out).forEach { ssidMatch ->
                    val ssid = ssidMatch.groupValues[1].trim('"')
                    // Find BSSID near this SSID
                    val pos = ssidMatch.range.first
                    val nearby = out.substring(maxOf(0, pos - 200), minOf(out.length, pos + 200))
                    val bssidMatch = Regex("([0-9a-fA-F:]{17})").find(nearby)
                    if (bssidMatch != null && results.none { it.bssid == bssidMatch.value }) {
                        results.add(WiFiNetwork(ssid, bssidMatch.value, -99, 0, ""))
                    }
                }
            } catch (_: Exception) {}
        }

        return results.sortedByDescending { it.rssi }
    }
}
