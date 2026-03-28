import SwiftUI

@main
struct CalcU59App: App {
    @State private var viewModel = EmulatorViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CalculatorView()
                .environment(viewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.persistConstantMemory()
            }
        }
    }
}
