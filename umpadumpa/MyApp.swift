import SwiftUI
#if os(macOS)
import AppKit
#endif

@main struct MyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup("UmpaDumpa") {
            ContentView(model: model)
                .preferredColorScheme(.light)
                .onAppear {
                    NSApp.appearance = NSAppearance(named: .aqua)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 840)
        #else
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.light)
        }
        #endif
    }
}
