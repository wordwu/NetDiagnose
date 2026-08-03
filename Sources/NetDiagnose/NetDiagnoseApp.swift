import SwiftUI

@main
struct NetDiagnoseApp: App {
    @StateObject private var orchestrator = ScanOrchestrator()

    var body: some Scene {
        WindowGroup {
            ContentView(orchestrator: orchestrator)
                .frame(minWidth: 900, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 800)
    }
}
