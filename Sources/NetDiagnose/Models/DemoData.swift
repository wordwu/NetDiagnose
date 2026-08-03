import Foundation

/// Pre-loaded demo data from the user's real network scan
enum DemoData {
    static func makeDevices() -> [NetworkDevice] {
        let now = Date()
        return [
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.1",
                macAddress: "b0:6e:bf",
                hostname: "RT-AC1900P",
                bonjourName: "华硕路由器",
                vendor: "ASUS",
                deviceType: .router,
                openPorts: [80, 443, 8200],
                isOnline: true,
                isGateway: true,
                lastSeen: now,
                osGuess: "AsusWRT 380.70",
                services: ["HTTP管理", "HTTPS管理", "MiniDLNA", "UPnP"]
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.126",
                macAddress: nil,
                hostname: "Hermes-Mac",
                bonjourName: "本机 (征的Mac)",
                vendor: "Apple",
                deviceType: .computer,
                openPorts: [22, 5900],
                isOnline: true,
                isLocalDevice: true,
                lastSeen: now,
                services: ["SSH", "VNC"]
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.192",
                macAddress: nil,
                hostname: "viomi-waterheater-e44",
                bonjourName: "云米热水器",
                vendor: "云米 (Xiaomi)",
                deviceType: .iot,
                isOnline: true,
                lastSeen: now,
                services: []
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.193",
                macAddress: nil,
                hostname: "xiaomi-15",
                bonjourName: "小米15",
                vendor: "Xiaomi",
                deviceType: .phone,
                isOnline: true,
                lastSeen: now,
                services: []
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.238",
                macAddress: nil,
                hostname: "susumukara2",
                bonjourName: "susumukara2 (疑似NAS)",
                vendor: "未知",
                deviceType: .nas,
                isOnline: false,
                lastSeen: now,
                services: []
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.250",
                macAddress: nil,
                hostname: "yeelink-light-lamp22",
                bonjourName: "Yeelight 灯泡",
                vendor: "Yeelight (Xiaomi)",
                deviceType: .iot,
                openPorts: [55443],
                isOnline: true,
                lastSeen: now,
                services: ["Yeelight API"]
            ),
            NetworkDevice(
                id: UUID(),
                ipAddress: "192.168.50.87",
                macAddress: "e4:fe:43",
                hostname: nil,
                bonjourName: "未知设备",
                vendor: "Intel Corporate",
                deviceType: .unknown,
                isOnline: true,
                lastSeen: now,
                services: []
            ),
        ]
    }
}
