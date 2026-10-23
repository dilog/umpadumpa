import SwiftUI
#if os(macOS)
import AppKit
#endif

@main struct MyApp: App {
    @State private var model = AppModel()

    init() {
        ignoreBrokenPipe()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup("UmpaDumpa") {
            ContentView(model: model)
                .preferredColorScheme(.light)
                .background(HiddenWindowTitle())
                .onAppear {
                    NSApp.appearance = NSAppearance(named: .aqua)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 840)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(AppVersion.aboutMenuTitle(from: Bundle.main.infoDictionary ?? [:])) {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: aboutPanelOptions())
                }
            }
        }
        #else
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.light)
        }
        #endif
    }

    #if os(macOS)
    /// Keeps the traffic lights and hides the title text so the bar does not repeat UmpaDumpa.
    private struct HiddenWindowTitle: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            NSView(frame: .zero)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                nsView.window?.titleVisibility = .hidden
            }
        }
    }

    private func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]

        let name = AppVersion.displayName(from: info)
        if !name.isEmpty {
            options[.applicationName] = name
        }

        let version = AppVersion.marketingVersion(from: info)
        if !version.isEmpty {
            options[.applicationVersion] = version
        }

        let build = AppVersion.buildNumber(from: info)
        if !build.isEmpty {
            options[.version] = build
        }

        return options
    }
    #endif
}
