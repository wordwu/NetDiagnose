import SwiftUI

// MARK: - WiFi Scan Sheet

struct WiFiScanSheet: View {
    let networks: [WiFiScanner.WiFiNetwork]
    let congestion: [WiFiScanner.ChannelCongestion]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WiFi 扫描").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("\(networks.count) 个网络").font(.system(size: 12)).foregroundColor(.gray)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            if networks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundColor(.gray)
                    Text("未发现 WiFi 网络").foregroundColor(.gray)
                    Text("请确认 WiFi 已开启").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Congestion analysis
                        if !congestion.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("信道拥塞分析", systemImage: "chart.bar.fill")
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                ForEach(congestion.prefix(6)) { c in
                                    HStack {
                                        Text("\(c.band) CH\(c.channel)")
                                            .font(.system(size: 12, design: .monospaced)).foregroundColor(.cyan)
                                        Text("\(c.networkCount) 个网络").font(.system(size: 12)).foregroundColor(.gray)
                                        Spacer()
                                        Text(c.recommendation)
                                            .font(.system(size: 11))
                                            .foregroundColor(c.networkCount > 4 ? .orange : .green)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(.horizontal)
                            Divider().padding(.horizontal)
                        }

                        // Network list
                        Label("附近网络", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal)

                        ForEach(networks.sorted(by: { $0.rssi > $1.rssi })) { net in
                            HStack(spacing: 10) {
                                // Signal strength
                                VStack(spacing: 2) {
                                    Image(systemName: rssiIcon(net.rssi))
                                        .font(.system(size: 14))
                                        .foregroundColor(rssiColor(net.rssi))
                                    Text("\(net.rssi) dBm")
                                        .font(.system(size: 9)).foregroundColor(.gray)
                                }
                                .frame(width: 45)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(net.ssid.isEmpty ? "(隐藏)" : net.ssid)
                                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                    HStack(spacing: 8) {
                                        Text("信道 \(net.channel) · \(net.band)")
                                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.cyan)
                                        Text(net.security).font(.system(size: 10)).foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Text(net.bssid.suffix(8))
                                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .background(Color(hex: "#020617"))
    }

    func rssiIcon(_ rssi: Int) -> String {
        if rssi > -50 { return "wifi" }
        if rssi > -65 { return "wifi" }
        if rssi > -75 { return "wifi" }
        return "wifi"
    }

    func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 { return .green }
        if rssi > -70 { return .yellow }
        return .orange
    }
}

// MARK: - Device Timeline Sheet

struct DeviceTimelineSheet: View {
    let device: NetworkDevice
    let snapshots: [ScanSnapshot]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(device.hostname ?? device.ipAddress) 时间线")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider()

            DeviceTimelineView(device: device, snapshots: snapshots)
        }
        .background(Color(hex: "#020617"))
    }
}
