import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    #if !os(macOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    // -1 = last used; 0/1/2 = specific MachineModel.rawValue
    @AppStorage(SettingsKey.startupModel)    private var startupModelRaw: Int = -1
    @AppStorage(SettingsKey.traceLocation)   private var traceLocationRaw: Int = TraceLocation.local.rawValue
    @AppStorage(SettingsKey.traceCustomPath) private var traceCustomPath: String = ""

    var body: some View {
        #if os(macOS)
        settingsForm
            .frame(width: 400)
            .padding()
        #else
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var settingsForm: some View {
        Form {
            Section("General") {
                Picker("Startup Calculator", selection: $startupModelRaw) {
                    ForEach(MachineModel.allCases) { m in
                        Text(m.displayName).tag(m.rawValue)
                    }
                    Divider()
                    Text("Last Used").tag(-1)
                }
            }

            Section("Trace File") {
                Picker("Save Location", selection: $traceLocationRaw) {
                    Text(TraceLocation.local.displayName).tag(TraceLocation.local.rawValue)
                    Text(TraceLocation.iCloud.displayName).tag(TraceLocation.iCloud.rawValue)
                    #if os(macOS)
                    Text(TraceLocation.custom.displayName).tag(TraceLocation.custom.rawValue)
                    #endif
                }
                #if os(macOS)
                if traceLocationRaw == TraceLocation.custom.rawValue {
                    HStack {
                        Text(traceCustomPath.isEmpty ? "No folder chosen" : traceCustomPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose…") { chooseCustomFolder() }
                    }
                }
                #endif
            }
        }
        .formStyle(.grouped)
    }

    private func chooseCustomFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for TI59_TRACE.bin"
        if panel.runModal() == .OK, let url = panel.url {
            traceCustomPath = url.path
        }
        #endif
    }
}

#Preview {
    SettingsView()
}
