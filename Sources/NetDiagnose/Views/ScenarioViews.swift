import SwiftUI

struct ScenarioPickerView: View {
    @Binding var selected: NetworkScenario?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("网络场景（可选）").font(.system(size: 12)).foregroundColor(.gray)
            HStack(spacing: 8) {
                ForEach(NetworkScenario.allCases) { scenario in
                    Button {
                        selected = (selected == scenario) ? nil : scenario
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: scenarioIcon(scenario))
                                .font(.system(size: 10))
                            Text(scenario.rawValue)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(minWidth: 80)
                        .background(selected == scenario ? Color.cyan.opacity(0.2) : Color.white.opacity(0.06))
                        .foregroundColor(selected == scenario ? .cyan : .gray)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let s = selected {
                Text(s.focus).font(.system(size: 11)).foregroundColor(.secondary).padding(.top, 2)
            }
        }
    }

    func scenarioIcon(_ s: NetworkScenario) -> String {
        switch s {
        case .home: return "house"
        case .office: return "building.2"
        case .event: return "network"    // 公司 = 网络基础设施
        case .hotel: return "bed.double"
        }
    }
}

struct ShareCardView: View {
    let score: Int
    let deviceCount: Int
    let onlineCount: Int
    let subnet: String
    let topFinding: String

    var body: some View {
        VStack(spacing: 0) {
            // Card design for sharing (1200x630 aspect)
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 30)).foregroundColor(.cyan)
                    Text("NetDiagnose").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Spacer()
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("网络健康评分").font(.system(size: 14)).foregroundColor(.gray)
                        Text("\(score)/100").font(.system(size: 56, weight: .bold, design: .monospaced)).foregroundColor(scoreColor)
                        HStack(spacing: 16) {
                            Label("\(onlineCount)/\(deviceCount) 在线", systemImage: "wifi").foregroundColor(.green).font(.system(size: 13))
                            Label(subnet, systemImage: "network").foregroundColor(.gray).font(.system(size: 13))
                        }
                        Text(topFinding).font(.system(size: 13)).foregroundColor(.gray).lineLimit(2)
                    }
                    Spacer()
                }

                Spacer()

                HStack {
                    Text("免费网络诊断 · 81677632@qq.com").font(.system(size: 11)).foregroundColor(.gray)
                    Spacer()
                    Text(Date().formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            .padding(32)
            .frame(width: 600, height: 315)
            .background(LinearGradient(colors: [Color(hex: "#0f172a"), Color(hex: "#020617")], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    var scoreColor: Color {
        score >= 80 ? .green : score >= 60 ? .yellow : .orange
    }
}
