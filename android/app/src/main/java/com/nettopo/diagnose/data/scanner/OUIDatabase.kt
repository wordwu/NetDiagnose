package com.nettopo.diagnose.data.scanner

object OUIDatabase {
    fun lookup(mac: String): String? {
        val oui = mac.uppercase().filter { it in "0123456789ABCDEF" }.take(6)
        return entries[oui]
    }

    val entries = mapOf(
        "00158D" to "Aqara", "04CF8C" to "Aqara",
        "B06EBF" to "ASUS", "D017C2" to "ASUS", "E0CB4E" to "ASUS",
        "000A27" to "Apple", "001451" to "Apple", "0016CB" to "Apple", "001FF3" to "Apple",
        "002312" to "Apple", "080007" to "Apple", "0C771A" to "Apple", "1495CE" to "Apple",
        "183451" to "Apple", "1C9148" to "Apple", "28E02C" to "Apple", "38C986" to "Apple",
        "00000C" to "Cisco", "000142" to "Cisco", "000D65" to "Cisco", "0011BB" to "Cisco",
        "001D45" to "Cisco", "002255" to "Cisco", "00017B" to "D-Link", "001CF0" to "D-Link",
        "807A1F" to "Dahua", "84683E" to "Dahua", "9C6A3B" to "Dahua",
        "0C1DAF" to "Xiaomi", "10B1F8" to "Xiaomi", "14F65A" to "Xiaomi", "181BEB" to "Xiaomi",
        "1C8ADA" to "Xiaomi", "206E9C" to "Xiaomi", "244BFE" to "Xiaomi", "28E31F" to "Xiaomi",
        "2CB430" to "Xiaomi", "3068CB" to "Xiaomi", "34CE00" to "Xiaomi", "38A49F" to "Xiaomi",
        "3CA87B" to "Xiaomi", "40D3EB" to "Xiaomi", "4455E8" to "Xiaomi", "4842E2" to "Xiaomi",
        "4C1520" to "Xiaomi", "E4FE43" to "Intel", "F0C816" to "Intel", "D8BFC0" to "Shelly",
        "DCED83" to "Yeelight", "F0B429" to "Yeelight", "CCB5D1" to "Viomi",
        "0016B6" to "TP-Link", "001D0F" to "TP-Link", "10D7B0" to "TP-Link", "142D27" to "TP-Link",
        "18A6F7" to "TP-Link", "1C61B4" to "TP-Link", "2430A1" to "TP-Link",
        "000FB5" to "Netgear", "00146C" to "Netgear", "04A151" to "Netgear", "0C3CCD" to "Netgear",
        "105A17" to "Tuya", "1C9099" to "Tuya", "2C3AE8" to "Tuya", "34FCFD" to "Tuya",
        "48E74E" to "Tuya", "503266" to "Tuya", "68D98B" to "Tuya", "70E945" to "Tuya",
        "B827EB" to "Raspberry Pi", "DC26DC" to "Raspberry Pi", "E45F01" to "Raspberry Pi",
        "0000F0" to "Samsung", "001632" to "Samsung", "0C8910" to "Samsung", "149AEC" to "Samsung",
        "18105E" to "Samsung", "1CAAA7" to "Samsung", "2099E7" to "Samsung",
        "00216C" to "Hikvision", "183F70" to "Hikvision", "28EDE0" to "Hikvision",
        "347DE4" to "Hikvision", "40EE15" to "Hikvision", "4CBAA3" to "Hikvision",
        "503956" to "Hikvision", "54ADA7" to "Hikvision",
        "001132" to "Synology", "0024C3" to "QNAP",
        "1024E9" to "OPPO", "18C3D8" to "OPPO", "0008D3" to "OnePlus", "18AF61" to "OnePlus",
        "08D4C4" to "Espressif", "10CEA9" to "Espressif", "18B905" to "Espressif",
        "240ACA" to "Espressif", "280D8F" to "Espressif", "2CC0AF" to "Espressif",
        "30AEA4" to "Espressif", "34AB95" to "Espressif", "389C25" to "Espressif",
        "3C16CD" to "Espressif", "400D10" to "Espressif",
        "001A11" to "Google", "081735" to "Google", "183146" to "Google",
        "00040D" to "Ubiquiti", "0CA402" to "Ubiquiti", "10326E" to "Ubiquiti",
        "6830E1" to "Sonoff", "84F3EB" to "Sonoff", "600194" to "Sonoff",
        "001321" to "HP", "0019BB" to "HP", "00000E" to "Huawei", "000651" to "Huawei",
        "000A82" to "Huawei", "000C43" to "Huawei"
    )
}
