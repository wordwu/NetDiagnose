import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Content Router

struct ContentView: View {
    @ObservedObject var orchestrator: ScanOrchestrator
    @StateObject private var bgMonitor = BackgroundMonitorService.shared

    var body: some View {
        Group {
            if let result = orchestrator.scanResult {
                ResultView(
                    result: result,
                    orchestrator: orchestrator,
                    bgMonitor: bgMonitor,
                    onBack: { orchestrator.reset() },
                    onRescan: { orchestrator.startScan(subnet: result.config.subnet) }
                )
            } else if orchestrator.isScanning {
                ScanningView(
                    progress: orchestrator.scanProgress,
                    value: orchestrator.progressValue,
                    onCancel: { orchestrator.reset() }
                )
            } else {
                HomeView(
                    orchestrator: orchestrator,
                    bgMonitor: bgMonitor,
                    errorMsg: orchestrator.errorMessage
                )
            }
        }
        .background(Color(hex: "#020617"))
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var orchestrator: ScanOrchestrator
    @ObservedObject var bgMonitor: BackgroundMonitorService
    let errorMsg: String?

    @State private var manualSubnet = ""
    @State private var showManual = false
    @State private var detectedInfo: LocalNetworkInfo? = nil
    @State private var detecting = true
    @State private var showWiFiScan = false
    @State private var wifiNetworks: [WiFiScanner.WiFiNetwork] = []
    @State private var wifiCongestion: [WiFiScanner.ChannelCongestion] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App branding
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(.white)
                }

                VStack(spacing: 6) {
                    Text("NetDiagnose")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("免费网络健康诊断 · 一键扫描全屋设备")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }

            Spacer().frame(height: 30)

            // Network info card
            if detecting {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text("正在检测本地网络...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 8)
            } else if let info = detectedInfo {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Label(info.interfaceName, systemImage: "wifi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                        Text("· 本机 \(info.localIP)  ·  网关 \(info.gatewayIP)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    Text("子网 \(info.subnet).0/24  ·  掩码 \(info.netmask)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.cyan.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 4)
            }

            // Scan mode picker
            VStack(spacing: 6) {
                Text("扫描模式").font(.system(size: 11)).foregroundColor(.gray)
                Picker("", selection: $orchestrator.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Text(orchestrator.scanMode.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            // Background monitoring toggle
            HStack(spacing: 10) {
                Image(systemName: bgMonitor.isMonitoring ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(bgMonitor.isMonitoring ? .green : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("后台监控").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                    Text(bgMonitor.isMonitoring ? "每5分钟检测新设备并通知" : "关闭时不会自动检测")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { bgMonitor.isMonitoring },
                    set: { $0 ? bgMonitor.start() : bgMonitor.stop() }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 320)
            .padding(.bottom, 8)
            if let lastCheck = bgMonitor.lastCheck {
                Text("上次检测: \(lastCheck.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }

            // WiFi scan button
            Button(action: {
                Task {
                    let networks = await Task.detached { WiFiScanner.scanNearbyNetworks() }.value
                    let congestion = WiFiScanner.analyzeCongestion(networks)
                    await MainActor.run {
                        wifiNetworks = networks
                        wifiCongestion = congestion
                        showWiFiScan = true
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi").font(.system(size: 12))
                    Text("扫描周围 WiFi").font(.system(size: 12))
                }
                .foregroundColor(.cyan.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            // Scan button
            Button(action: {
                if let info = detectedInfo {
                    orchestrator.startScan(subnet: "\(info.subnet).0/24", mode: orchestrator.scanMode)
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                    Text("一键诊断")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(colors: [Color.cyan, Color.blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .frame(width: 300)
            .disabled(detectedInfo == nil)
            .opacity(detectedInfo == nil ? 0.5 : 1)

            if let err = errorMsg {
                Text(err).font(.system(size: 12)).foregroundColor(.red).padding(.top, 8)
            }

            // Manual subnet
            Button(action: { showManual.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: showManual ? "chevron.up" : "pencil")
                    Text(showManual ? "收起" : "手动输入子网")
                }
                .font(.system(size: 12))
                .foregroundColor(.cyan.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            if showManual {
                HStack(spacing: 8) {
                    TextField("例如 192.168.1.0/24", text: $manualSubnet)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: 220)

                    Button(action: {
                        orchestrator.startScan(subnet: manualSubnet)
                    }) {
                        Text("扫描")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.2))
                            .foregroundColor(.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(manualSubnet.isEmpty)
                }
                .padding(.top, 8)
            }

            Spacer().frame(height: 40)

            // Footer features
            HStack(spacing: 40) {
                featureItem(icon: "iphone.gen3", text: "设备识别")
                featureItem(icon: "bolt.horizontal", text: "延迟检测")
                featureItem(icon: "heart.text.square", text: "健康评分")
                featureItem(icon: "doc.richtext", text: "PDF 报告")
            }

            Spacer()
        }
        .padding()
        .task {
            let info = NetworkScanner.detectLocalNetwork()
            detectedInfo = info
            detecting = false
        }
        .frame(minWidth: 680, minHeight: 550)
        .background(Color(hex: "#020617"))
    }

    func featureItem(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.cyan.opacity(0.6))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }    }
}

// MARK: - Scanning View

struct ScanningView: View {
    let progress: String
    let value: Float
    let onCancel: () -> Void

    @State private var dots = 0
    let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.cyan.opacity(0.1), lineWidth: 6)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: CGFloat(value))
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: value)

                VStack(spacing: 4) {
                    Text("\(Int(value * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }

            Text(progress)
                .font(.system(size: 15))
                .foregroundColor(.gray)

            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.cyan)
                Text("正在扫描网络设备\(String(repeating: ".", count: dots))")
                    .foregroundColor(.gray)
                    .font(.system(size: 13))
            }
            .onReceive(timer) { _ in dots = (dots + 1) % 4 }

            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(hex: "#020617"))
    }
}

// MARK: - Result View

struct ResultView: View {
    let result: ScanResult
    @ObservedObject var orchestrator: ScanOrchestrator
    @ObservedObject var bgMonitor: BackgroundMonitorService
    let onBack: () -> Void
    let onRescan: () -> Void

    @State private var selectedDevice: NetworkDevice? = nil
    @State private var showDetail = false
    @State private var showDeviceList = false
    @State private var showRecs = false
    @State private var showHealth = false
    @State private var showExportSheet = false
    @State private var selectedTab: ResultTab = .diagnosis
    @State private var showShareCard = false
    @State private var expertMode = false
    @State private var showWiFiScan = false
    @State private var wifiNetworks: [WiFiScanner.WiFiNetwork] = []
    @State private var wifiCongestion: [WiFiScanner.ChannelCongestion] = []
    @State private var showDeviceTimeline = false

    enum ResultTab: String, CaseIterable {
        case diagnosis = "诊断结论"
        case topology = "拓扑图"
        case devices = "设备清单"
        case export = "导出"

        var icon: String {
            switch self {
            case .diagnosis: return "stethoscope"
            case .topology: return "circle.hexagongrid"
            case .devices: return "list.bullet.rectangle"
            case .export: return "square.and.arrow.up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with score + scenario
            topBarTabs

            // Tab content area
            if result.devices.isEmpty {
                Spacer()
                Text("没有发现设备").foregroundColor(.gray)
                Spacer()
            } else {
                tabContent
            }

            // Bottom divider
            Divider().background(Color(hex: "#1e293b"))

            // Tab picker at bottom
            tabPicker
        }
        .background(Color(hex: "#020617"))
        .frame(minWidth: 700, minHeight: 700)
        .sheet(isPresented: $showWiFiScan) {
            WiFiScanSheet(networks: wifiNetworks, congestion: wifiCongestion)
                .frame(width: 500, height: 550)
        }
        .sheet(isPresented: $showDeviceTimeline) {
            if let device = selectedDevice {
                DeviceTimelineSheet(device: device, snapshots: ScanHistoryService.shared.loadAllForDisplay())
                    .frame(width: 480, height: 520)
            }
        }
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheetMac(device: device, devices: result.devices, config: result.config)
                .frame(width: 420, height: 500)
        }
        .sheet(isPresented: $showDetail) {
            if let device = selectedDevice {
                DeviceNotesView(device: device)
            }
        }
        .sheet(isPresented: $showRecs) {
            RecommendationSheetMac(
                recommendations: RecommendationEngine.analyze(devices: result.devices, gatewayIP: result.config.gatewayIP, subnet: result.config.subnet).map { "\($0.title)：\($0.reason)" }
            ).frame(width: 480, height: 500)
        }
        .sheet(isPresented: $showHealth) {
            HealthDetailSheet(breakdown: orchestrator.healthBreakdown, tips: orchestrator.healthTips)
                .frame(width: 440, height: 420)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetNew(devices: result.devices, config: result.config, findings: orchestrator.diagnosticFindings, score: orchestrator.healthScore, notes: DeviceNotesService.shared.allNotes())
                .frame(width: 480, height: 420)
        }
    }

    // ── Tab picker ──

    var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ResultTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 14))
                        Text(tab.rawValue).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == tab ? .cyan : .gray)
                    .background(selectedTab == tab ? Color.cyan.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .background(Color(hex: "#0f172a"))
    }

    // ── Tab content switch ──

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .diagnosis:
            diagnosticTab
        case .topology:
            topologyTab
        case .devices:
            devicesTab
        case .export:
            exportTab
        }
    }

    // ── Top bar with scenario ──

    var topBarTabs: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                // Unified controls row: scenario buttons + expert toggle
                if !result.devices.isEmpty {
                    HStack(spacing: 8) {
                        // Scenario buttons
                        ForEach(NetworkScenario.allCases) { scenario in
                            Button {
                                orchestrator.selectedScenario = (orchestrator.selectedScenario == scenario) ? nil : scenario
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: scenarioIcon(scenario)).font(.system(size: 10))
                                    Text(scenario.rawValue).font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .frame(width: 100)
                                .background(orchestrator.selectedScenario == scenario ? Color.cyan.opacity(0.2) : Color.white.opacity(0.06))
                                .foregroundColor(orchestrator.selectedScenario == scenario ? .cyan : .gray)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        // Divider
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 24)

                        // Expert mode toggle — same style as scenario buttons
                        Button(action: { expertMode.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape.fill").font(.system(size: 10))
                                Text(expertMode ? "专家" : "精简").font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(width: 100)
                            .background(expertMode ? Color.cyan.opacity(0.2) : Color.white.opacity(0.06))
                            .foregroundColor(expertMode ? .cyan : .gray)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Divider
                        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 24)

                        // WiFi scan button
                        Button(action: {
                            Task {
                                let networks = await Task.detached { WiFiScanner.scanNearbyNetworks() }.value
                                let congestion = WiFiScanner.analyzeCongestion(networks)
                                await MainActor.run {
                                    wifiNetworks = networks
                                    wifiCongestion = congestion
                                    showWiFiScan = true
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "wifi").font(.system(size: 10))
                                Text("WiFi").font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(width: 100)
                            .background(Color.cyan.opacity(0.08))
                            .foregroundColor(.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Background monitoring indicator
                        if bgMonitor.isMonitoring {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("监控中").font(.system(size: 10)).foregroundColor(.green.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Score badge
                if !result.devices.isEmpty {
                    Button(action: { showHealth = true }) {
                        HStack(spacing: 5) {
                            Circle().fill(scoreColor).frame(width: 8, height: 8)
                            Text("\(orchestrator.healthScore)/100")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(scoreColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color(hex: "#0f172a"))

            // Scenario focus hint
            if let s = orchestrator.selectedScenario {
                HStack {
                    Text(s.focus).font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 6)
                .background(Color(hex: "#0f172a"))
            }
        }
    }

    func scenarioIcon(_ s: NetworkScenario) -> String {
        switch s {
        case .home: return "house"
        case .office: return "building.2"
        case .event: return "network"
        case .hotel: return "bed.double"
        }
    }

    // ── Diagnosis Tab ──

    var diagnosticTab: some View {
        DiagnosticConclusionView(
            findings: orchestrator.diagnosticFindings,
            score: orchestrator.healthScore,
            devices: result.devices,
            scanDuration: result.scanDuration,
            previousSnapshot: orchestrator.previousSnapshot,
            expertMode: expertMode
        )
    }

    // ── Topology Tab ──

    var topologyTab: some View {
        VStack {
            TopologyHTMLView(devices: result.devices, config: result.config, selectedDevice: $selectedDevice)
                .frame(maxHeight: .infinity)
        }
    }

    // ── Devices Tab ──

    var devicesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                healthScoreSection
                deviceTableWithNotes
                tipsSection
                ctaSection
            }
            .padding(20)
        }
    }

    // ── Device table with notes column ──

    var deviceTableWithNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("设备清单 (\(result.devices.count) 台)", systemImage: "list.bullet.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                // Header - adjusts columns based on expert mode
                HStack(spacing: 8) {
                    Text("IP").frame(width: 120, alignment: .leading)
                    if expertMode {
                        Text("MAC").frame(width: 130, alignment: .leading)
                        Text("厂商").frame(width: 70, alignment: .leading)
                    }
                    Text("类型").frame(width: expertMode ? 60 : 80, alignment: .leading)
                    if expertMode {
                        Text("延迟").frame(width: 55, alignment: .trailing)
                    }
                    Text("备注").frame(width: 100, alignment: .leading)
                    Text("状态").frame(width: 35, alignment: .center)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(hex: "#1e293b"))

                ForEach(result.devices.sorted { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) { device in
                    HStack(spacing: 8) {
                        Text(device.ipAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                            .foregroundColor(device.isGateway ? .yellow : .white)

                        if expertMode {
                            Text(device.macAddress ?? "--")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 130, alignment: .leading)
                                .foregroundColor(.gray)

                            Text(device.vendor ?? "--")
                                .font(.system(size: 10))
                                .frame(width: 70, alignment: .leading)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: device.deviceType.icon)
                                .font(.system(size: 9))
                            Text(device.deviceType.rawValue)
                                .font(.system(size: 10))
                        }
                        .frame(width: expertMode ? 60 : 80, alignment: .leading)
                        .foregroundColor(.cyan.opacity(0.7))

                        if expertMode {
                            latencyView(device.latencyMs)
                                .frame(width: 55, alignment: .trailing)
                        }

                        // Notes column with edit button
                        HStack(spacing: 4) {
                            DeviceNoteTag(ip: device.ipAddress)
                            Button {
                                selectedDevice = device
                                showDetail = true
                            } label: {
                                Image(systemName: "pencil.circle").font(.system(size: 10))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            Button {
                                selectedDevice = device
                                showDeviceTimeline = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                                    .foregroundColor(.cyan.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 100, alignment: .leading)

                        Circle()
                            .fill(device.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .frame(width: 35)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(device.isGateway ? Color.orange.opacity(0.08) : .clear)

                    if device.id != result.devices.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(hex: "#0f172a"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // ── Export Tab ──

    var exportTab: some View {
        ExportSheetInline(
            devices: result.devices,
            config: result.config,
            findings: orchestrator.diagnosticFindings,
            score: orchestrator.healthScore,
            notes: DeviceNotesService.shared.allNotes(),
            showShareCard: $showShareCard
        )
    }

    var scoreColor: Color {
        let s = orchestrator.healthScore
        return s >= 80 ? .green : s >= 60 ? .yellow : s >= 40 ? .orange : .red
    }

    // ── Health Score Section (NetDiagnose style) ──

    var healthScoreSection: some View {
        HStack(spacing: 20) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 8)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: CGFloat(orchestrator.healthScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1), value: orchestrator.healthScore)
                VStack(spacing: 2) {
                    Text("\(orchestrator.healthScore)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("/100")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(scoreLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                let online = result.devices.filter({ $0.isOnline }).count
                HStack(spacing: 16) {
                    Label("\(online) 在线", systemImage: "wifi")
                        .foregroundColor(.green)
                    Label("\(result.devices.count - online) 离线", systemImage: "wifi.slash")
                        .foregroundColor(.gray)
                    if let avg = orchestrator.avgLatency {
                        Label("\(String(format: "%.0f", avg))ms", systemImage: "stopwatch")
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 12))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("扫描耗时")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Text(String(format: "%.1f 秒", result.scanDuration))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(Color(hex: "#0f172a"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var scoreLabel: String {
        switch orchestrator.healthScore {
        case 90...: return "网络健康"
        case 70..<90: return "网络基本正常"
        case 50..<70: return "网络需要关注"
        default: return "网络状况不佳"
        }
    }

    // ── Device Table (NetDiagnose style) ──

    var deviceTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("设备清单 (\(result.devices.count) 台)", systemImage: "list.bullet.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("IP").frame(width: 120, alignment: .leading)
                    Text("MAC").frame(width: 130, alignment: .leading)
                    Text("厂商").frame(width: 70, alignment: .leading)
                    Text("类型").frame(width: 60, alignment: .leading)
                    Text("信度").frame(width: 30, alignment: .center)
                    Text("延迟").frame(width: 55, alignment: .trailing)
                    Text("风险").frame(width: 30, alignment: .center)
                    Text("状态").frame(width: 35, alignment: .center)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(hex: "#1e293b"))

                ForEach(result.devices.sorted { ($0.latencyMs ?? 9999) < ($1.latencyMs ?? 9999) }) { device in
                    HStack(spacing: 8) {
                        Text(device.ipAddress)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                            .foregroundColor(device.isGateway ? .yellow : .white)

                        Text(device.macAddress ?? "--")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 130, alignment: .leading)
                            .foregroundColor(.gray)

                        Text(device.vendor ?? "--")
                            .font(.system(size: 10))
                            .frame(width: 70, alignment: .leading)
                            .foregroundColor(.gray)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: device.deviceType.icon)
                                .font(.system(size: 9))
                            Text(device.deviceType.rawValue)
                                .font(.system(size: 10))
                        }
                        .frame(width: 60, alignment: .leading)
                        .foregroundColor(.cyan.opacity(0.7))

                        confidenceDot(device.identificationConfidence)
                            .frame(width: 30)

                        latencyView(device.latencyMs)
                            .frame(width: 55, alignment: .trailing)

                        riskDot(device.riskLevel)
                            .frame(width: 30)

                        Circle()
                            .fill(device.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .frame(width: 35)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(device.isGateway ? Color.orange.opacity(0.08) : .clear)

                    if device.id != result.devices.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(hex: "#0f172a"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    func latencyView(_ ms: Double?) -> some View {
        guard let ms = ms else {
            return AnyView(Text("--").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary))
        }
        let color: Color = ms < 5 ? .green : ms < 15 ? .mint : ms < 50 ? .yellow : ms < 100 ? .orange : .red
        return AnyView(
            Text(String(format: "%.1fms", ms))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(color)
        )
    }

    func confidenceDot(_ c: IdentificationConfidence) -> some View {
        let color: Color = c == .high ? .green : c == .medium ? .yellow : .gray
        return Text(c == .high ? "H" : c == .medium ? "M" : "L")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
    }

    func riskDot(_ r: RiskLevel) -> some View {
        let color: Color = r == .high ? .red : r == .medium ? .orange : .green
        return Circle().fill(color).frame(width: 6, height: 6)
    }

    // ── Tips ──

    var tipsSection: some View {
        Group {
            if !orchestrator.healthTips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("诊断建议", systemImage: "lightbulb.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    ForEach(orchestrator.healthTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Color.yellow).frame(width: 6, height: 6).padding(.top, 6)
                            Text(tip).font(.system(size: 13)).foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }

    // ── Export ──

    var exportSection: some View {
        HStack {
            Button(action: { showExportSheet = true }) {
                Label("导出 PDF 报告", systemImage: "doc.richtext")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .tint(.cyan)

            Text("报告内含 \"Generated by NetDiagnose\" 标识")
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
    }

    // ── CTA ──

    var ctaSection: some View {
        Group {
            if orchestrator.healthScore < 80 {
                VStack(spacing: 0) {
                    Divider().padding(.vertical, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("网络评分 \(orchestrator.healthScore)/100 · 想提升？")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("用 NetTopo 深度分析网络拓扑，找出问题根源")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("了解更多") {
                            NSWorkspace.shared.open(URL(string: "mailto:81677632@qq.com")!)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.cyan.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }


}
