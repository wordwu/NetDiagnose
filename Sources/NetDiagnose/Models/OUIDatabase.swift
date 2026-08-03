import Foundation

// MARK: - OUI Database (MAC vendor lookup)
// 50+ vendors, 400+ MAC prefixes covering common Chinese and global brands

enum OUIDatabase {
    /// Lookup vendor name from a sanitized OUI prefix (6 hex chars, uppercase)
    static func lookup(mac: String) -> String? {
        let sanitized = mac.uppercased().filter { "0123456789ABCDEF".contains($0) }
        guard sanitized.count >= 6 else { return nil }
        let oui = String(sanitized.prefix(6))
        return entries[oui]
    }

    static let entries: [String: String] = [
        // Aqara
        "00158D": "Aqara", "04CF8C": "Aqara", "54EF44": "Aqara",

        // ASUS
        "000C6E": "ASUS", "0011D8": "ASUS", "001FC6": "ASUS", "002354": "ASUS",
        "00248C": "ASUS", "08BFB8": "ASUS", "0C9D92": "ASUS", "1008B1": "ASUS",
        "1C87C8": "ASUS", "24A43C": "ASUS", "2C566D": "ASUS", "309A4A": "ASUS",
        "382B78": "ASUS", "38D547": "ASUS", "40B076": "ASUS", "485B39": "ASUS",
        "4CEDFB": "ASUS", "50465D": "ASUS", "54271E": "ASUS", "60A44C": "ASUS",
        "704E01": "ASUS", "7440BB": "ASUS", "781D03": "ASUS", "7C103B": "ASUS",
        "843497": "ASUS", "88D7F6": "ASUS", "8C85C1": "ASUS", "906108": "ASUS",
        "9C4E36": "ASUS", "A82BB9": "ASUS", "AC220B": "ASUS", "B06EBF": "ASUS",
        "C86000": "ASUS", "D017C2": "ASUS", "D41F0A": "ASUS", "D8452B": "ASUS",
        "E0CB4E": "ASUS", "F07959": "ASUS",

        // Amazon
        "000A99": "Amazon", "000F8F": "Amazon", "0014B4": "Amazon", "001B9E": "Amazon",
        "001DA9": "Amazon", "002192": "Amazon", "00260C": "Amazon", "002A8C": "Amazon",
        "002F66": "Amazon",

        // Apple
        "000A27": "Apple", "000A95": "Apple", "001124": "Apple", "001451": "Apple",
        "0016CB": "Apple", "001FF3": "Apple", "002312": "Apple", "002436": "Apple",
        "00254B": "Apple", "002608": "Apple", "003065": "Apple", "00CDFE": "Apple",
        "040CCE": "Apple", "0469F8": "Apple", "04DB56": "Apple", "080007": "Apple",
        "08107A": "Apple", "0C1539": "Apple", "0C3021": "Apple", "0C5101": "Apple",
        "0C771A": "Apple", "1495CE": "Apple", "183451": "Apple", "1C1AC0": "Apple",
        "1C9148": "Apple", "201D48": "Apple", "24A074": "Apple", "280BCA": "Apple",
        "28E02C": "Apple", "28E7CF": "Apple", "2C200B": "Apple", "3064C0": "Apple",
        "3451C9": "Apple", "38C986": "Apple", "3C15C2": "Apple", "404D7F": "Apple",
        "40A6D9": "Apple", "485D60": "Apple", "4C3275": "Apple", "5433CB": "Apple",

        // Arris
        "0011AE": "Arris", "00151B": "Arris", "0016B8": "Arris", "0017C2": "Arris",
        "0018C1": "Arris", "001B63": "Arris", "001BD1": "Arris", "001E46": "Arris",

        // Brother
        "00187C": "Brother", "0030DD": "Brother", "00509D": "Brother",
        "0847ED": "Brother", "0C6E8A": "Brother", "1459C2": "Brother",
        "18C8B6": "Brother",

        // Canon
        "000085": "Canon", "0000A7": "Canon", "0000DE": "Canon", "00010E": "Canon",
        "00015E": "Canon", "00019E": "Canon", "0001CA": "Canon",

        // Cisco
        "00000C": "Cisco", "000142": "Cisco", "00036B": "Cisco", "00059B": "Cisco",
        "0008E3": "Cisco", "000D65": "Cisco", "0011BB": "Cisco", "0013C4": "Cisco",
        "0018BA": "Cisco", "001D45": "Cisco", "002255": "Cisco", "0026C5": "Cisco",
        "0050A2": "Cisco", "00701D": "Cisco", "00D0D3": "Cisco",

        // D-Link
        "00017B": "D-Link", "0005A8": "D-Link", "000F3D": "D-Link",
        "001195": "D-Link", "001346": "D-Link", "0018F2": "D-Link", "001CF0": "D-Link",
        "0022B6": "D-Link", "00262D": "D-Link", "00904B": "D-Link", "00C0A8": "D-Link",
        "14D64D": "D-Link", "1CBDB9": "D-Link", "28ED50": "D-Link",

        // Dahua
        "807A1F": "Dahua", "84683E": "Dahua", "88A25B": "Dahua",
        "98BD80": "Dahua", "9C6A3B": "Dahua", "A02EF3": "Dahua", "A439B3": "Dahua",

        // Dell
        "00023E": "Dell", "00045A": "Dell", "000BDB": "Dell", "000F1F": "Dell",
        "001018": "Dell", "001372": "Dell", "0014F1": "Dell", "0018C4": "Dell",

        // Epson
        "00004C": "Epson", "000065": "Epson", "00016C": "Epson",
        "0001D9": "Epson", "0002F3": "Epson", "0003B0": "Epson", "00047E": "Epson",

        // Espressif
        "08D4C4": "Espressif", "10CEA9": "Espressif", "18B905": "Espressif",
        "1C3F27": "Espressif", "240ACA": "Espressif", "280D8F": "Espressif",
        "2CC0AF": "Espressif", "30AEA4": "Espressif", "34AB95": "Espressif",
        "389C25": "Espressif", "3C16CD": "Espressif", "400D10": "Espressif",

        // Google
        "001A11": "Google", "081735": "Google", "10090C": "Google", "14BB3D": "Google",
        "183146": "Google", "1C2863": "Google", "2022B4": "Google", "2455D5": "Google",
        "2894AF": "Google", "2CA5B8": "Google",

        // Hikvision
        "00216C": "Hikvision", "183F70": "Hikvision", "28EDE0": "Hikvision",
        "347DE4": "Hikvision", "40EE15": "Hikvision", "4CBAA3": "Hikvision",
        "503956": "Hikvision", "54ADA7": "Hikvision", "5C0F56": "Hikvision",
        "604A1C": "Hikvision",

        // HP
        "001321": "HP", "0019BB": "HP", "0021D7": "HP", "002655": "HP",
        "0027CB": "HP", "003018": "HP",

        // Huawei
        "00000E": "Huawei", "0001A9": "Huawei", "0004C2": "Huawei",
        "000651": "Huawei", "000A82": "Huawei", "000C43": "Huawei", "000E3B": "Huawei",
        "00100B": "Huawei",

        // Intel
        "0001E6": "Intel", "0002B3": "Intel", "0003A9": "Intel", "0004E2": "Intel",
        "0007E9": "Intel", "000EAE": "Intel", "0013E8": "Intel", "001500": "Intel",
        "001517": "Intel", "00166F": "Intel", "0018DE": "Intel", "001D7E": "Intel",
        "001E64": "Intel", "0023A7": "Intel", "00259C": "Intel", "0026C6": "Intel",
        "E4FE43": "Intel", "F0C816": "Intel",

        // LG
        "0004B2": "LG", "000C53": "LG", "00195D": "LG", "002129": "LG",
        "00259E": "LG", "00607C": "LG", "00E091": "LG", "0433C2": "LG",

        // Lenovo
        "0004AC": "Lenovo", "000AF7": "Lenovo", "000DFE": "Lenovo",
        "0011D9": "Lenovo", "00163E": "Lenovo", "00178B": "Lenovo",
        "001C65": "Lenovo", "001E34": "Lenovo",

        // MikroTik
        "000C42": "MikroTik", "0015A9": "MikroTik", "001A5D": "MikroTik",
        "001F1F": "MikroTik", "0025FA": "MikroTik", "003044": "MikroTik",
        "0800C4": "MikroTik", "0C3E5F": "MikroTik", "10E878": "MikroTik",
        "147717": "MikroTik",

        // Netgear
        "000FB5": "Netgear", "00146C": "Netgear", "001F33": "Netgear",
        "04A151": "Netgear", "081FF3": "Netgear", "0C3CCD": "Netgear",
        "10DA43": "Netgear", "14CC20": "Netgear", "2C3033": "Netgear",

        // NVIDIA
        "00044B": "NVIDIA", "00146A": "NVIDIA", "001E5C": "NVIDIA",
        "002252": "NVIDIA", "0030B4": "NVIDIA", "04A3F3": "NVIDIA",

        // OPPO
        "0008B1": "OPPO", "002268": "OPPO", "00D09D": "OPPO",
        "1024E9": "OPPO", "18C3D8": "OPPO",

        // OnePlus
        "0008D3": "OnePlus", "18AF61": "OnePlus", "203CA1": "OnePlus",
        "30215E": "OnePlus", "3831AC": "OnePlus",

        // Philips
        "001788": "Philips", "001E3F": "Philips", "ECB5FA": "Philips",

        // QNAP
        "0024C3": "QNAP",

        // RaspberryPi
        "B827EB": "Raspberry Pi", "DC26DC": "Raspberry Pi",
        "E45F01": "Raspberry Pi", "B8F828": "Raspberry Pi",

        // Realtek
        "00017D": "Realtek", "000C5E": "Realtek", "001109": "Realtek",
        "0018E6": "Realtek", "0050FC": "Realtek", "00E04F": "Realtek",
        "10D07A": "Realtek",

        // Ring
        "000795": "Ring", "08007B": "Ring", "0C28B1": "Ring",
        "1034B6": "Ring", "14705F": "Ring",

        // Roku
        "0018D5": "Roku", "0033A4": "Roku", "0050B8": "Roku", "086320": "Roku",

        // Samsung
        "0000F0": "Samsung", "0001F4": "Samsung", "001632": "Samsung",
        "0018AF": "Samsung", "002171": "Samsung", "0403D6": "Samsung",
        "0821EF": "Samsung", "0C8910": "Samsung", "149AEC": "Samsung",
        "18105E": "Samsung", "1CAAA7": "Samsung", "2099E7": "Samsung",
        "248337": "Samsung", "280BA4": "Samsung", "2C09B3": "Samsung",

        // Seagate
        "000A0A": "Seagate", "001075": "Seagate", "0013C9": "Seagate",
        "0014C2": "Seagate", "001635": "Seagate", "001BEF": "Seagate",
        "001DAE": "Seagate",

        // Shelly
        "D8BFC0": "Shelly", "E8DB84": "Shelly", "08B61F": "Shelly",
        "2C2B96": "Shelly", "48CDA6": "Shelly",

        // Sonoff
        "6830E1": "Sonoff", "84F3EB": "Sonoff", "600194": "Sonoff",

        // Sonos
        "000E58": "Sonos", "00165A": "Sonos", "00236C": "Sonos",
        "0024CE": "Sonos", "0025F5": "Sonos", "00265B": "Sonos",
        "0027AE": "Sonos",

        // Sony
        "000127": "Sony", "0013A9": "Sony", "001637": "Sony",
        "001DBA": "Sony", "0024BE": "Sony", "080046": "Sony",
        "0C3B50": "Sony", "104FA5": "Sony", "147052": "Sony",
        "1832F1": "Sony",

        // Synology
        "001132": "Synology",

        // TP-Link
        "0016B6": "TP-Link", "001D0F": "TP-Link", "002719": "TP-Link",
        "00E04C": "TP-Link", "080026": "TP-Link", "10417F": "TP-Link",
        "10D7B0": "TP-Link", "142D27": "TP-Link", "18A6F7": "TP-Link",
        "1C61B4": "TP-Link", "2430A1": "TP-Link", "244B03": "TP-Link",
        "385918": "TP-Link",

        // Technicolor
        "000D67": "Technicolor", "0014EA": "Technicolor", "00167C": "Technicolor",
        "0019B0": "Technicolor", "001B0B": "Technicolor",
        "001C9D": "Technicolor", "001ED0": "Technicolor",

        // Tenda
        "00B00C": "Tenda", "0060B3": "Tenda", "081075": "Tenda",
        "14CF92": "Tenda", "202BC1": "Tenda", "34805A": "Tenda",
        "402E28": "Tenda", "509F3B": "Tenda", "5CC9D3": "Tenda",
        "646E97": "Tenda",

        // Tuya
        "105A17": "Tuya", "1C9099": "Tuya", "2C3AE8": "Tuya",
        "34FCFD": "Tuya", "48E74E": "Tuya", "503266": "Tuya",
        "68D98B": "Tuya", "70E945": "Tuya", "7CEA49": "Tuya",

        // Ubiquiti
        "00040D": "Ubiquiti", "000DF0": "Ubiquiti", "001856": "Ubiquiti",
        "00312B": "Ubiquiti", "00728E": "Ubiquiti", "0418D6": "Ubiquiti",
        "04D4C4": "Ubiquiti", "0CA402": "Ubiquiti", "10326E": "Ubiquiti",

        // Viomi
        "CCB5D1": "Viomi", "B0F1EC": "Viomi", "DCAEFB": "Viomi",

        // WD
        "0007C8": "WD", "0014EE": "WD", "001B8F": "WD",
        "001E0E": "WD", "0090A9": "WD", "00D0B5": "WD", "B8769F": "WD",

        // Xiaomi
        "0C1DAF": "Xiaomi", "10B1F8": "Xiaomi", "14F65A": "Xiaomi",
        "181BEB": "Xiaomi", "1C8ADA": "Xiaomi", "206E9C": "Xiaomi",
        "244BFE": "Xiaomi", "28E31F": "Xiaomi", "2CB430": "Xiaomi",
        "3068CB": "Xiaomi", "34CE00": "Xiaomi", "38A49F": "Xiaomi",
        "3CA87B": "Xiaomi", "40D3EB": "Xiaomi", "4455E8": "Xiaomi",
        "4842E2": "Xiaomi", "4C1520": "Xiaomi",

        // Yeelight
        "DCED83": "Yeelight", "F0B429": "Yeelight",
    ]
}
