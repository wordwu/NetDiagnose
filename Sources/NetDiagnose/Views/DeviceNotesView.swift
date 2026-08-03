import SwiftUI

struct DeviceNotesView: View {
    let device: NetworkDevice
    @State private var label: String
    @State private var memo: String
    @State private var isKnown: Bool
    @Environment(\.dismiss) private var dismiss

    private let notesService = DeviceNotesService.shared

    init(device: NetworkDevice) {
        self.device = device
        let note = DeviceNotesService.shared.get(for: device)
        _label = State(initialValue: note.label)
        _memo = State(initialValue: note.memo)
        _isKnown = State(initialValue: note.isKnown)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑备注").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button("保存") {
                    notesService.set(note: DeviceNote(ip: device.ipAddress, label: label, memo: memo, isKnown: isKnown))
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(.cyan).controlSize(.small)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Circle().fill(device.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                    Text(device.ipAddress).font(.system(size: 14, design: .monospaced)).foregroundColor(.white)
                    Text(device.vendor ?? "").font(.system(size: 12)).foregroundColor(.gray)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义名称").font(.system(size: 12)).foregroundColor(.gray)
                    TextField("如：客厅路由器", text: $label)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("备注").font(.system(size: 12)).foregroundColor(.gray)
                    TextEditor(text: $memo)
                        .font(.system(size: 13))
                        .frame(height: 80)
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .scrollContentBackground(.hidden)
                }

                Toggle(isOn: $isKnown) {
                    Text("标记为已知设备").font(.system(size: 13)).foregroundColor(.gray)
                }
                .toggleStyle(.checkbox)

                if isKnown {
                    Text("已知设备不会在陌生设备警告中出现").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 380, height: 360)
        .background(Color(hex: "#020617"))
    }
}

struct DeviceNoteTag: View {
    let ip: String
    @StateObject private var notesService = DeviceNotesService.shared

    var body: some View {
        let note = notesService.get(for: NetworkDevice.makeDummy(ip: ip))
        if note.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                if !note.label.isEmpty {
                    Text(note.label).font(.system(size: 10)).foregroundColor(.green)
                }
                if note.isKnown {
                    Image(systemName: "checkmark.shield").font(.system(size: 9)).foregroundColor(.green)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.green.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}

extension NetworkDevice {
    static func makeDummy(ip: String) -> NetworkDevice {
        NetworkDevice(ipAddress: ip, macAddress: nil, isOnline: false, isGateway: false, isLocalDevice: false)
    }
}
