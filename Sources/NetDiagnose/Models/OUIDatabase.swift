import Foundation

// MARK: - OUI Database (IEEE 全量 MAC 厂商库)
// 数据源: IEEE OUI (MA-L) 公开数据，约 39800 条，存于 Resources/oui.json

enum OUIDatabase {
    /// 从 MAC 前缀（OUI）查厂商
    static func lookup(mac: String) -> String? {
        let sanitized = mac.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard sanitized.count >= 6 else { return nil }
        let oui = String(sanitized.prefix(6))
        return entries[oui]
    }

    /// 全量厂商表（首次访问时从资源文件加载并缓存）
    static let entries: [String: String] = {
        guard let url = Bundle.module.url(forResource: "oui", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }()
}
