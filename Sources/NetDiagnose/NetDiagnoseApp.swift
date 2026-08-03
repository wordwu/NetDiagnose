import SwiftUI

@main
struct NetDiagnoseApp: App {
    var body: some Scene {
        Window("NetDiagnose — 免费网络健康诊断", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 580)
    }
}
