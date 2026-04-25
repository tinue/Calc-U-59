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
    @AppStorage(SettingsKey.traceLocation)   private var traceLocationRaw: Int = TraceLocation.iCloud.rawValue
    @AppStorage(SettingsKey.traceCustomPath) private var traceCustomPath: String = ""
    @AppStorage(SettingsKey.traceMaxFileSizeMB) private var traceMaxFileSizeMB: Int = 10
    @AppStorage(SettingsKey.keyboardFeedback) private var keyboardFeedbackRaw: Int = KeyboardFeedbackType.off.rawValue

    // Trigger refresh of warning after re-authorization
    @State private var authRefreshTrigger: UUID = UUID()

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
        .onAppear {
            // Force iCloud on iOS/iPadOS
            traceLocationRaw = TraceLocation.iCloud.rawValue
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

                Picker("Keyboard Feedback", selection: $keyboardFeedbackRaw) {
                    ForEach(KeyboardFeedbackType.allCases) { feedback in
                        // Only show haptic on iOS/iPadOS where it's available
                        #if os(iOS)
                        Text(feedback.displayName).tag(feedback.rawValue)
                        #else
                        if feedback != .haptic {
                            Text(feedback.displayName).tag(feedback.rawValue)
                        }
                        #endif
                    }
                }
            }

            Section("Trace File") {
                #if os(macOS)
                Picker("Save Location", selection: $traceLocationRaw) {
                    Text(TraceLocation.local.displayName).tag(TraceLocation.local.rawValue)
                    Text(TraceLocation.iCloud.displayName).tag(TraceLocation.iCloud.rawValue)
                    Text(TraceLocation.custom.displayName).tag(TraceLocation.custom.rawValue)
                }
                if traceLocationRaw == TraceLocation.custom.rawValue {
                    HStack {
                        Text(traceCustomPath.isEmpty ? "No folder chosen" : traceCustomPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose…") { chooseCustomFolder() }
                    }

                    // Show warning if path exists but no bookmark (old settings without re-authorization)
                    Group {
                        if AppSettings.customTracePathNeedsReauthorization() {
                            Text("⚠️ This folder needs to be re-authorized. Click 'Choose…' again to allow trace file writing.")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .id(authRefreshTrigger)  // Re-evaluate when trigger changes
                }
                #endif

                HStack {
                    Text("Maximum File Size")
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("Size", value: $traceMaxFileSizeMB, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("MB")
                            .foregroundStyle(.secondary)
                    }
                }
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
        panel.message = "Choose a folder for CALCU59_TRACE.bin"
        if panel.runModal() == .OK, let url = panel.url {
            print("[SettingsView] User selected folder: \(url.path)")
            // Use AppSettings to save with security-scoped bookmark
            // This must be done BEFORE updating the @AppStorage property
            AppSettings.setCustomTraceDirectory(url)
            // Now update the UI binding (which will also update UserDefaults via @AppStorage)
            traceCustomPath = url.path
            print("[SettingsView] Folder saved with bookmark")
            // Trigger refresh of warning so it disappears if bookmark was successful
            authRefreshTrigger = UUID()
            print("[SettingsView] Triggered UI refresh")
        }
        #endif
    }
}

#Preview {
    SettingsView()
}
