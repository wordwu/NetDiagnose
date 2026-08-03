import SwiftUI

/// Shows a device's history timeline: first seen, port changes, online/offline transitions.
struct DeviceTimelineView: View {
    let device: NetworkDevice
    let snapshots: [ScanSnapshot]

    struct TimelineEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let title: String
        let detail: String
        let icon: String
        let color: Color
    }

    var entries: [TimelineEntry] {
        var result = [TimelineEntry]()

        // First seen
        if let first = snapshots.first(where: { $0.devices.contains(where: { $0.ipAddress == device.ipAddress }) }) {
            result.append(TimelineEntry(
                timestamp: first.timestamp,
                title: "首次发现",
                detail: "MAC: \(device.macAddress ?? "未知") · 厂商: \(device.vendor ?? "未知")",
                icon: "plus.circle.fill",
                color: .green
            ))
        }

        // Port changes
        var prevPorts: [Int] = []
        for snap in snapshots {
            guard let snapDevice = snap.devices.first(where: { $0.ipAddress == device.ipAddress }) else { continue }
            if !prevPorts.isEmpty && Set(prevPorts) != Set(snapDevice.openPorts) {
                let added = Set(snapDevice.openPorts).subtracting(prevPorts)
                let removed = Set(prevPorts).subtracting(snapDevice.openPorts)
                var detail = ""
                if !added.isEmpty {
                    detail += "新增: \(added.sorted().map { portName($0) }.joined(separator: "、"))"
                }
                if !removed.isEmpty {
                    if !detail.isEmpty { detail += "；" }
                    detail += "关闭: \(removed.sorted().map { portName($0) }.joined(separator: "、"))"
                }
                result.append(TimelineEntry(
                    timestamp: snap.timestamp,
                    title: "端口变化",
                    detail: detail,
                    icon: "arrow.triangle.swap",
                    color: .orange
                ))
            }
            prevPorts = snapDevice.openPorts
        }

        // Latest scan
        result.append(TimelineEntry(
            timestamp: Date(),
            title: device.isOnline ? "当前在线" : "当前离线",
            detail: "延迟: \(device.latencyMs.map { String(format: "%.1fms", $0) } ?? "--") · 开放端口: \(device.openPorts.isEmpty ? "无" : device.openPorts.sorted().map { portName($0) }.joined(separator: "、"))",
            icon: device.isOnline ? "wifi" : "wifi.slash",
            color: device.isOnline ? .green : .gray
        ))

        return result.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark").font(.system(size: 40)).foregroundColor(.gray)
                    Text("暂无历史记录").foregroundColor(.gray)
                    Text("多次扫描后将生成设备时间线").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            // Timeline dot + line
                            VStack(spacing: 0) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(entry.color)
                                    .frame(width: 28, height: 28)
                                    .background(entry.color.opacity(0.12))
                                    .clipShape(Circle())
                                if entry.id != entries.last?.id {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(entry.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 12)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(hex: "#020617"))
    }

    private func portName(_ port: Int) -> String {
        let map: [Int: String] = [
            23:"Telnet", 21:"FTP", 22:"SSH", 80:"HTTP", 443:"HTTPS", 445:"SMB",
            631:"IPP", 3389:"RDP", 5900:"VNC", 8080:"HTTP-Proxy", 554:"RTSP",
            1900:"UPnP", 5353:"mDNS", 9100:"RAW打印", 5000:"Synology", 5001:"QNAP"
        ]
        return map[port] ?? "端口\(port)"
    }
}

struct DeviceTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceTimelineView(device: NetworkDevice(ipAddress: "192.168.1.100"), snapshots: [])
    }
}
