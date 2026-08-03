import Foundation
import UserNotifications

/// Periodically scans ARP table for new/unknown MAC addresses and sends macOS notifications.
class BackgroundMonitorService: ObservableObject {
    static let shared = BackgroundMonitorService()

    @Published var isMonitoring = false
    @Published var lastCheck: Date?
    @Published var knownMACs: Set<String> = []

    private var timer: Timer?
    private let storageKey = "bg_monitor_known_macs"
    private let scanInterval: TimeInterval = 300 // 5 minutes

    private init() {
        knownMACs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        requestNotificationPermission()
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
        timer?.tolerance = 30
        RunLoop.main.add(timer!, forMode: .common)
        performCheck() // immediate first check
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    private func performCheck() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let entries = NetworkScanner.arpTable()
            let currentMACs = Set(entries.map { $0.mac })

            // Find new MACs we haven't seen before
            let newMACs = currentMACs.subtracting(self.knownMACs)

            if !newMACs.isEmpty {
                // Find corresponding IPs
                var newDevices: [String] = []
                for entry in entries where newMACs.contains(entry.mac) {
                    let vendor = NetworkScanner.lookupVendor(mac: entry.mac)
                    let label = vendor.map { "\($0)(\(entry.ip))" } ?? entry.ip
                    newDevices.append(label)
                }

                let count = newDevices.count
                DispatchQueue.main.async {
                    // @Published 必须在主线程更新
                    self.knownMACs = self.knownMACs.union(newMACs)
                    self.saveKnownMACs()
                    self.sendNotification(
                        title: "发现 \(count) 台新设备",
                        body: newDevices.prefix(5).joined(separator: "、") + (count > 5 ? " 等" : ""),
                        identifier: "new-device-\(UUID().uuidString.prefix(8))"
                    )
                }
            }

            DispatchQueue.main.async {
                self.lastCheck = Date()
            }
        }
    }

    private func saveKnownMACs() {
        UserDefaults.standard.set(Array(knownMACs), forKey: storageKey)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
