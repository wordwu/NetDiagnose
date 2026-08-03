import Foundation

struct DiagnosticEngine {
    static func analyze(
        devices: [NetworkDevice],
        previous: ScanSnapshot?,
        scenario: NetworkScenario? = nil,
        notes: DeviceNotesService? = nil
    ) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []

        let online = devices.filter(\.isOnline)
        let stealth = devices.filter { $0.isStealth }
        let visible = devices.filter { !$0.isStealth }
        let risky = devices.filter { $0.riskLevel != .low }
        let unknown = devices.filter { $0.deviceType == .unknown || $0.identificationConfidence == .low }
        let highLatency = devices.filter { ($0.latencyMs ?? 0) > 100 }
        let openPorts = devices.filter { !$0.openPorts.isEmpty }

        // ── Helpers ──
        func name(_ d: NetworkDevice) -> String {
            if let n = notes?.get(for: d), !n.label.isEmpty { return "\(n.label)(\(d.ipAddress))" }
            if let h = d.hostname, !h.isEmpty { return "\(h)(\(d.ipAddress))" }
            return d.ipAddress
        }
        func short(_ d: NetworkDevice) -> String {
            if let n = notes?.get(for: d), !n.label.isEmpty { return n.label }
            if let h = d.hostname, !h.isEmpty { return h }
            return d.ipAddress
        }

        // ── 1. 网络基础 ──
        if online.isEmpty && stealth.isEmpty {
            findings.append(DiagnosticFinding(severity: .critical,
                title: "全部设备离线", explanation: "\(devices.count) 台设备无一在线，路由器可能宕机或子网选错",
                action: "检查路由器电源、网线、确认扫描子网与当前网络一致"))
        } else if online.isEmpty && !stealth.isEmpty {
            findings.append(DiagnosticFinding(severity: .warning,
                title: "仅发现隐身设备", explanation: "\(stealth.count) 台设备在 ARP 表中但未响应 ping（可能屏蔽 ICMP）",
                action: "网络可能正常，只是设备禁 ping；可尝试深度扫描"))
        } else if visible.count > 0 {
            let ratio = Double(online.count) / Double(visible.count)
            if ratio >= 0.9 {
                findings.append(DiagnosticFinding(severity: .good,
                    title: "在线率良好", explanation: "\(online.count)/\(visible.count) 台在线 (\(Int(ratio*100))%)",
                    action: "网络状态健康"))
            } else if ratio < 0.5 {
                let offlineIPs = visible.filter { !$0.isOnline }.map { name($0) }
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "近半设备离线", explanation: "仅 \(online.count)/\(visible.count) 台在线。离线: \(offlineIPs.joined(separator: "、"))",
                    action: "检查网关是否重启、DHCP 租约是否过期", affectedIPs: offlineIPs))
            }
        }

        // ── 2. 高风险设备（具体说明风险原因） ──
        for d in risky {
            let risks = d.riskNotes.joined(separator: "；")
            let ports = d.openPorts.filter { [23,3389,5900,21,22,80,443,8080,3306,5432,1194,51820].contains($0) }
            let portDetail = ports.isEmpty ? "" : "，开放端口: \(ports.sorted().map { portName($0) }.joined(separator: "、"))"
            findings.append(DiagnosticFinding(severity: .critical,
                title: "风险设备: \(name(d))",
                explanation: "\(risks)\(portDetail)",
                action: "\(short(d)) 存在安全风险，建议检查并限制网络访问",
                affectedIPs: [d.ipAddress]))
        }

        // ── 3. 未识别设备（区分已知/未知） ──
        let trulyUnknown = unknown.filter {
            notes?.get(for: $0).isKnown != true
        }
        let knownButLowConf = unknown.filter {
            notes?.get(for: $0).isKnown == true
        }
        if !trulyUnknown.isEmpty {
            let list = trulyUnknown.map { "\(name($0)) [MAC: \($0.macAddress ?? "无")]" }.joined(separator: "、")
            findings.append(DiagnosticFinding(severity: .warning,
                title: "\(trulyUnknown.count) 台陌生设备",
                explanation: list,
                action: "核实这些设备身份，如非己方设备立即隔离",
                affectedIPs: trulyUnknown.map(\.ipAddress)))
        }
        if !knownButLowConf.isEmpty {
            let list = knownButLowConf.map { name($0) }.joined(separator: "、")
            findings.append(DiagnosticFinding(severity: .info,
                title: "\(knownButLowConf.count) 台已知设备识别度低",
                explanation: list,
                action: "可手动编辑备注完善设备信息",
                affectedIPs: knownButLowConf.map(\.ipAddress)))
        }

        // ── 4. 高延迟 ──
        for d in highLatency.prefix(5) {
            let lat = d.latencyMs.map { String(format: "%.0fms", $0) } ?? "?"
            findings.append(DiagnosticFinding(severity: .warning,
                title: "高延迟: \(name(d)) \(lat)",
                explanation: "\(short(d)) 延迟 \(lat)，超过正常阈值 100ms，可能 WiFi 信号弱或网络拥堵",
                action: "将 \(short(d)) 靠近路由器，或检查是否有大流量任务占用带宽",
                affectedIPs: [d.ipAddress]))
        }

        // ── 5. 开放端口（区分场景 + 端口变化） ──
        let scenePorts = dangerousPorts(for: scenario)
        for d in openPorts {
            let bad = d.openPorts.filter { scenePorts.keys.contains($0) }
            if bad.isEmpty { continue }
            // Check if these ports are new (compared to previous scan)
            let prevDevice = previous?.devices.first(where: { $0.ipAddress == d.ipAddress })
            let prevPorts = Set(prevDevice?.openPorts ?? [])
            let newPorts = bad.filter { !prevPorts.contains($0) }

            let portNames = bad.sorted().map { portName($0) }
            if !newPorts.isEmpty {
                let newNames = newPorts.sorted().map { portName($0) }
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "新开端口: \(name(d))",
                    explanation: "\(short(d)) 本次扫描新开放了 \(newNames.joined(separator: "、"))，上次未发现",
                    action: "确认是否为正常服务变更，如非预期请立即排查",
                    affectedIPs: [d.ipAddress]))
            } else {
                findings.append(DiagnosticFinding(severity: .info,
                    title: "开放端口: \(name(d))",
                    explanation: "\(short(d)) 开放了 \(portNames.joined(separator: "、"))",
                    action: "如无需外网访问，建议关闭或限制局域网访问",
                    affectedIPs: [d.ipAddress]))
            }
        }

        // ── 6. 设备备注反哺：已知设备离线告警 ──
        if let notes = notes {
            let knownDevices = devices.filter { notes.get(for: $0).isKnown }
            let knownOffline = knownDevices.filter { !$0.isOnline }
            if !knownOffline.isEmpty {
                let names = knownOffline.map { "\(short($0))(\($0.ipAddress))" }.joined(separator: "、")
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "已知设备离线: \(names)",
                    explanation: "\(knownOffline.count) 台你标记过的设备当前不在线",
                    action: "确认这些设备是否正常关机或离开网络",
                    affectedIPs: knownOffline.map(\.ipAddress)))
            }
        }

        // ── 7. 场景专项检查 ──
        if let scenario = scenario {
            findings += scenarioChecks(devices: devices, scenario: scenario, notes: notes, nameFn: name, shortFn: short)
        }

        // ── 8. 历史对比 ──
        if let prev = previous {
            let prevIPs = Set(prev.devices.map(\.ipAddress))
            let currIPs = Set(devices.map(\.ipAddress))
            let newIPs = currIPs.subtracting(prevIPs)
            let lostIPs = prevIPs.subtracting(currIPs)

            for ip in newIPs {
                guard let d = devices.first(where: { $0.ipAddress == ip }) else { continue }
                let isNoteKnown = notes?.get(for: d).isKnown == true
                findings.append(DiagnosticFinding(
                    severity: isNoteKnown ? .info : .warning,
                    title: "\(isNoteKnown ? "已知设备回归" : "新设备上线"): \(name(d))",
                    explanation: "\(short(d)) 上次扫描时不在网络中，本次出现\(isNoteKnown ? "（你已标记为已知设备）" : "，请注意核实身份")",
                    action: isNoteKnown ? "设备已重新连接，无需操作" : "确认此设备身份，如非己方设备请立即处理",
                    affectedIPs: [ip]))
            }

            for ip in lostIPs {
                guard let past = prev.devices.first(where: { $0.ipAddress == ip }) else { continue }
                let currDevice = devices.first(where: { $0.ipAddress == ip })
                let displayName = currDevice.map { name($0) } ?? ip
                let note = currDevice.flatMap { notes?.get(for: $0) }
                let labelHint = (note?.label).map { "（\($0)）" } ?? ""
                let isKnown = note?.isKnown == true
                findings.append(DiagnosticFinding(
                    severity: isKnown ? .warning : .info,
                    title: "\(isKnown ? "已知设备离线" : "设备消失"): \(displayName)\(labelHint)",
                    explanation: "上次在线，本次离线。厂商: \(past.vendor ?? "未知")，类型: \(past.deviceType.rawValue)",
                    action: isKnown ? "\(note?.label ?? displayName) 离线，检查是否正常关机" : "设备可能已离开网络",
                    affectedIPs: [ip]))
            }

            // Port changes between scans
            for curr in devices {
                guard let past = prev.devices.first(where: { $0.ipAddress == curr.ipAddress }) else { continue }
                let added = Set(curr.openPorts).subtracting(past.openPorts)
                let removed = Set(past.openPorts).subtracting(curr.openPorts)
                if !added.isEmpty {
                    let names = added.sorted().map { portName($0) }.joined(separator: "、")
                    findings.append(DiagnosticFinding(severity: .warning,
                        title: "\(name(curr)) 端口新增",
                        explanation: "\(short(curr)) 新开放了 \(names)（上次未开放）",
                        action: "确认是否为正常服务变更",
                        affectedIPs: [curr.ipAddress]))
                }
                if !removed.isEmpty {
                    let names = removed.sorted().map { portName($0) }.joined(separator: "、")
                    findings.append(DiagnosticFinding(severity: .info,
                        title: "\(name(curr)) 端口关闭",
                        explanation: "\(short(curr)) 关闭了 \(names)，相比上次更安全",
                        action: "正常变更，无需操作",
                        affectedIPs: [curr.ipAddress]))
                }
            }
        }

        return findings
    }

    // ── Scene-specific port lists ──
    static func dangerousPorts(for scenario: NetworkScenario?) -> [Int: String] {
        var base: [Int: String] = [23: "Telnet", 21: "FTP", 3306: "MySQL", 5432: "PostgreSQL", 6379: "Redis", 27017: "MongoDB", 5900: "VNC"]
        switch scenario {
        case .home:
            base[80] = "HTTP"
            base[443] = "HTTPS"
            base[8080] = "HTTP-Proxy"
            base[22] = "SSH"
        case .office:
            base[445] = "SMB"
            base[631] = "IPP打印机"
            base[3389] = "远程桌面"
            base[22] = "SSH"
            base[80] = "HTTP"
            base[443] = "HTTPS"
            base[9100] = "RAW打印机"
        case .event: // 公司
            base[3389] = "远程桌面"
            base[22] = "SSH"
            base[1194] = "OpenVPN"
            base[51820] = "WireGuard"
            base[500] = "IPsec-IKE"
            base[4500] = "IPsec-NAT"
            base[1723] = "PPTP"
            base[80] = "HTTP"
            base[443] = "HTTPS"
        case .hotel:
            base[554] = "RTSP摄像头"
            base[80] = "HTTP"
            base[443] = "HTTPS"
            base[631] = "IPP打印机"
            base[9100] = "RAW打印机"
            base[1900] = "UPnP"
            base[5353] = "mDNS"
        case .none:
            base[3389] = "远程桌面"
            base[22] = "SSH"
            base[80] = "HTTP"
            base[443] = "HTTPS"
        }
        return base
    }

    static func portName(_ port: Int) -> String {
        let map: [Int: String] = [23:"Telnet", 21:"FTP", 22:"SSH", 80:"HTTP", 443:"HTTPS", 445:"SMB",
            631:"IPP", 3389:"RDP", 5900:"VNC", 8080:"HTTP-Proxy", 3306:"MySQL", 5432:"PostgreSQL",
            6379:"Redis", 27017:"MongoDB", 9100:"RAW打印", 554:"RTSP", 1900:"UPnP", 5353:"mDNS",
            1194:"OpenVPN", 51820:"WireGuard", 500:"IPsec-IKE", 4500:"IPsec-NAT", 1723:"PPTP"]
        return map[port] ?? "端口\(port)"
    }

    // ── Scenario-specific checks ──
    static func scenarioChecks(
        devices: [NetworkDevice],
        scenario: NetworkScenario,
        notes: DeviceNotesService?,
        nameFn: (NetworkDevice) -> String,
        shortFn: (NetworkDevice) -> String
    ) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []
        let online = devices.filter(\.isOnline)

        switch scenario {
        case .home:
            // 陌生设备
            let strangers = devices.filter { d in
                d.deviceType == .unknown && notes?.get(for: d).isKnown != true
            }
            if !strangers.isEmpty {
                let list = strangers.map { nameFn($0) }.joined(separator: "、")
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "家庭网络: \(strangers.count) 台陌生设备",
                    explanation: list,
                    action: "立即核实这些设备身份，如非家庭成员设备 → 改 WiFi 密码",
                    affectedIPs: strangers.map(\.ipAddress)))
            }
            // IoT 过多
            let iot = devices.filter { $0.deviceType == .iot || $0.deviceType == .camera }
            if iot.count > 8 {
                findings.append(DiagnosticFinding(severity: .info,
                    title: "家庭网络: \(iot.count) 台 IoT 设备",
                    explanation: "智能家居设备数量较多，建议划分到访客网络隔离",
                    action: "路由器上创建独立 IoT VLAN 或访客 WiFi"))
            }

        case .office:
            // 打印机
            let printers = devices.filter { $0.deviceType == .printer || ($0.openPorts.contains(631) || $0.openPorts.contains(9100)) }
            if printers.isEmpty {
                findings.append(DiagnosticFinding(severity: .info,
                    title: "办公网络: 未检测到打印机",
                    explanation: "未发现 IPP(631) 或 RAW(9100) 打印服务",
                    action: "如需网络打印，确认打印机已联网并开启网络打印协议"))
            } else {
                let list = printers.map { nameFn($0) }.joined(separator: "、")
                findings.append(DiagnosticFinding(severity: .info,
                    title: "办公网络: \(printers.count) 台打印机在线",
                    explanation: list,
                    action: "确认打印服务正常"))
            }
            // NAS
            let nas = devices.filter { $0.deviceType == .nas || $0.openPorts.contains(445) }
            if nas.isEmpty {
                findings.append(DiagnosticFinding(severity: .info,
                    title: "办公网络: 未检测到 NAS/文件共享",
                    explanation: "未发现 SMB(445) 共享服务",
                    action: "如需文件共享服务器，确认 NAS 在线"))
            }
            // 远程桌面暴露
            let rdp = devices.filter { $0.openPorts.contains(3389) }
            if !rdp.isEmpty {
                let list = rdp.map { nameFn($0) }.joined(separator: "、")
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "办公网络: 远程桌面暴露",
                    explanation: "\(list) 开放了 3389(RDP)，可能被外网扫描攻击",
                    action: "关闭公网 RDP 端口映射，改用 VPN 后再连远程桌面"))
            }

        case .event: // 公司
            // 网关延迟
            if let gw = online.first(where: \.isGateway), let lat = gw.latencyMs {
                if lat > 20 {
                    findings.append(DiagnosticFinding(severity: .warning,
                        title: "公司网络: 网关延迟 \(String(format: "%.0f", lat))ms",
                        explanation: "网关延迟偏高（>20ms），影响办公体验",
                        action: "检查网关 CPU/内存负载，暂停大流量下载"))
                } else {
                    findings.append(DiagnosticFinding(severity: .good,
                        title: "公司网络: 网关延迟 \(String(format: "%.0f", lat))ms 正常",
                        explanation: "网关响应速度良好",
                        action: ""))
                }
            }
            // VPN 暴露
            let vpnPorts = [1194, 51820, 500, 4500, 1723]
            let vpnDevices = devices.filter { d in !Set(d.openPorts).intersection(vpnPorts).isEmpty }
            if !vpnDevices.isEmpty {
                for d in vpnDevices {
                    let ports = d.openPorts.filter(vpnPorts.contains).map { portName($0) }.joined(separator: "、")
                    findings.append(DiagnosticFinding(severity: .warning,
                        title: "公司网络: \(nameFn(d)) 暴露 VPN 端口",
                        explanation: "开放了 \(ports)，可能被外部攻击者扫描",
                        action: "确认 VPN 服务为合法部署，检查认证和加密配置"))
                }
            }
            // DNS 异常（简单检查：网关是否有 DNS 端口）
            let dnsDevices = devices.filter { $0.openPorts.contains(53) && !$0.isGateway }
            if !dnsDevices.isEmpty {
                let list = dnsDevices.map { nameFn($0) }.joined(separator: "、")
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "公司网络: 非网关设备开放 DNS(53)",
                    explanation: "\(list) 开放了 DNS 端口，可能存在 DNS 劫持风险",
                    action: "排查这些设备是否为合法 DNS 服务器"))
            }

        case .hotel:
            // 摄像头
            let cameras = devices.filter { $0.deviceType == .camera || $0.openPorts.contains(554) }
            if cameras.isEmpty {
                findings.append(DiagnosticFinding(severity: .info,
                    title: "酒店网络: 未检测到摄像头",
                    explanation: "未发现 RTSP(554) 或识别为 camera 的设备",
                    action: "确认酒店监控系统是否接入当前网络"))
            } else {
                for cam in cameras {
                    findings.append(DiagnosticFinding(severity: .info,
                        title: "酒店网络: \(nameFn(cam)) 摄像头在线",
                        explanation: "\(shortFn(cam)) 开放 RTSP(554) 或识别为摄像头设备",
                        action: "确认属于酒店管理系统，非私装"))
                }
            }
            // UPnP 暴露
            let upnp = devices.filter { $0.openPorts.contains(1900) }
            if !upnp.isEmpty && upnp.contains(where: \.isGateway) {
                findings.append(DiagnosticFinding(severity: .warning,
                    title: "酒店网络: 网关 UPnP 已开启",
                    explanation: "UPnP 允许内网设备自动映射端口到公网，存在安全隐患",
                    action: "建议在路由器管理页面关闭 UPnP"))
            }
        }

        return findings
    }
}
