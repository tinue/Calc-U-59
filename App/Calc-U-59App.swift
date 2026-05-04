import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct CalcU59App: App {
    @State private var viewModel = EmulatorViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CalculatorView()
                .environment(viewModel)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                viewModel.suspendForBackground()
            case .active:
                viewModel.resumeFromBackground()
            default:
                break
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Calc-U-59") {
                    NSApp.orderFrontStandardAboutPanel(options: AppInfo.aboutPanelOptions)
                }
            }
        }
        #endif
    }
}
