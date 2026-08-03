import Foundation

class DeviceNotesService: ObservableObject {
    static let shared = DeviceNotesService()

    private var notes: [String: DeviceNote] = [:]
    private let fileManager = FileManager.default

    private var storageURL: URL {
        let dir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NetDiagnose")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device_notes.json")
    }

    init() {
        load()
    }

    func get(for device: NetworkDevice) -> DeviceNote {
        notes[device.ipAddress] ?? DeviceNote(ip: device.ipAddress)
    }

    func get(ip: String) -> DeviceNote {
        notes[ip] ?? DeviceNote(ip: ip)
    }

    func set(note: DeviceNote) {
        notes[note.ip] = note
        save()
    }

    func allNotes() -> [DeviceNote] {
        Array(notes.values).sorted { $0.ip < $1.ip }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        notes = (try? JSONDecoder().decode([String: DeviceNote].self, from: data)) ?? [:]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: storageURL)
        }
    }
}

struct DeviceNote: Codable, Identifiable, Equatable {
    var id: String { ip }
    var ip: String
    var label: String
    var memo: String
    var isKnown: Bool
    var learnedType: DeviceType? = nil   // 用户手动指定的设备类型，识别时优先采用
    var updatedAt: Date

    init(ip: String, label: String = "", memo: String = "", isKnown: Bool = false, learnedType: DeviceType? = nil, updatedAt: Date = Date()) {
        self.ip = ip
        self.label = label
        self.memo = memo
        self.isKnown = isKnown
        self.learnedType = learnedType
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool {
        label.isEmpty && memo.isEmpty && !isKnown && learnedType == nil
    }
}
