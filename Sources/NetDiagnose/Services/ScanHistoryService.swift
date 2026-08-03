import Foundation

class ScanHistoryService {
    static let shared = ScanHistoryService()

    private let fileManager = FileManager.default
    private let maxSnapshots = 5

    private var storageDir: URL {
        let dir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NetDiagnose/History")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func save(_ result: ScanResult) {
        let snapshots = loadAll()
        var updated = Array(snapshots.suffix(maxSnapshots - 1))
        updated.append(ScanSnapshot(
            timestamp: result.timestamp,
            subnet: result.config.subnet,
            devices: result.devices.map(DeviceSnapshot.init)
        ))
        persist(updated)
    }

    func latest(for subnet: String? = nil) -> ScanSnapshot? {
        let all = loadAll()
        if let subnet = subnet {
            return all.last { $0.subnet == subnet }
        }
        return all.last
    }


    /// Load all snapshots for display (e.g. device timeline)
    func loadAllForDisplay() -> [ScanSnapshot] {
        loadAll()
    }

    func diff(current: [NetworkDevice], previous: ScanSnapshot) -> ScanDiff {
        let prevMap = Dictionary(uniqueKeysWithValues: previous.devices.map { ($0.ipAddress, $0) })
        let currMap = Dictionary(uniqueKeysWithValues: current.map { ($0.ipAddress, $0) })

        let prevIPs = Set(prevMap.keys)
        let currIPs = Set(currMap.keys)

        let newDevices = currIPs.subtracting(prevIPs).compactMap { currMap[$0] }
        let missingDevices = prevIPs.subtracting(currIPs).compactMap { prevMap[$0] }

        var changedDevices: [(NetworkDevice, [Int], [Int])] = []
        for ip in prevIPs.intersection(currIPs) {
            guard let past = prevMap[ip], let curr = currMap[ip] else { continue }
            if Set(past.openPorts) != Set(curr.openPorts) {
                changedDevices.append((curr, past.openPorts, curr.openPorts))
            }
        }

        return ScanDiff(newDevices: newDevices, missingDevices: missingDevices, changedDevices: changedDevices)
    }

    private func loadAll() -> [ScanSnapshot] {
        guard let files = try? fileManager.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ScanSnapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func persist(_ snapshots: [ScanSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        // Clear old
        for file in (try? fileManager.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil)) ?? [] {
            try? fileManager.removeItem(at: file)
        }
        // Write new
        for (i, snap) in snapshots.enumerated() {
            let url = storageDir.appendingPathComponent("snapshot_\(i).json")
            if let data = try? encoder.encode(snap) {
                try? data.write(to: url)
            }
        }
    }
}
