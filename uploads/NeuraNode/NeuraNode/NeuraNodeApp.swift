import SwiftUI
import UIKit

@main
struct NeuraNodeApp: App {
    @StateObject private var nodeManager = NodeManager()

    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(nodeManager)
                .preferredColorScheme(.dark)
        }
    }
}
