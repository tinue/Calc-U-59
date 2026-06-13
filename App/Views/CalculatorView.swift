import SwiftUI
import UniformTypeIdentifiers
import AudioToolbox

struct CalculatorView: View {
    @Environment(EmulatorViewModel.self) var viewModel

    enum FilePickerMode { case asm, stateFile }
    @State private var activeFilePickerMode: FilePickerMode?

    private static let asmTypes = [UTType(filenameExtension: "asm") ?? .plainText]
    private static let stateFileTypes = [
        UTType(filenameExtension: "ti59") ?? .data,
        UTType(filenameExtension: "ti58") ?? .data,
        UTType(filenameExtension: "ti58c") ?? .data
    ]

    private var filePickerBinding: Binding<Bool> {
        Binding(
            get: { activeFilePickerMode != nil },
            set: { _ in }  // No-op setter; we reset state in result handler
        )
    }

    #if os(macOS)
    @State private var isCommandPressed = false
    #else
    enum PortraitPage { case calc, printer, debug }
    @State private var portraitPage: PortraitPage = .calc
    @AppStorage(SettingsKey.portraitDebugPage) private var debugPageEnabled: Bool = false
    @State private var showingSettings = false
    @State private var resetLongPressTriggered = false
    #endif

    #if canImport(UIKit)
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    private func triggerResetFeedback() {
        #if os(iOS)
        let feedbackType = AppSettings.resolvedKeyboardFeedback()
        switch feedbackType {
        case .off:
            break
        case .haptic:
            haptic.impactOccurred()
        case .click:
            AudioServicesPlaySystemSound(1104)
        }
        #endif
    }

    private func triggerMemoryClearFeedback() {
        #if os(iOS)
        let feedbackType = AppSettings.resolvedKeyboardFeedback()
        switch feedbackType {
        case .off:
            break
        case .haptic:
            haptic.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                haptic.impactOccurred()
            }
        case .click:
            AudioServicesPlaySystemSound(1104)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AudioServicesPlaySystemSound(1104)
            }
        }
        #endif
    }

    var body: some View {
        layout
        .dynamicTypeSize(.small ... .large)
        .sheet(item: .init(
            get: { viewModel.cardPickerMode.map { PickerItem(mode: $0) } },
            set: { viewModel.cardPickerMode = $0?.mode }
        )) { item in
            CardPickerView(
                mode: item.mode,
                directory: CardStorage.directoryURL,
                defaultFileName: viewModel.cardFileName
            ) { url in
                switch item.mode {
                case .load: viewModel.insertCard(from: url)
                case .save: viewModel.insertBlankCard(savingTo: url)
                }
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                modelPicker
            }
        }
        .alert("ROM load error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .fileImporter(
            isPresented: filePickerBinding,
            allowedContentTypes: {
                guard let mode = activeFilePickerMode else { return [] }
                switch mode {
                case .asm:
                    return Self.asmTypes
                case .stateFile:
                    return Self.stateFileTypes
                }
            }(),
            allowsMultipleSelection: false
        ) { result in
            let mode = activeFilePickerMode

            guard case .success(let urls) = result, let url = urls.first else {
                activeFilePickerMode = nil
                return
            }

            switch mode {
            case .asm:
                viewModel.loadASMOverlayFile(url)
                activeFilePickerMode = nil
            case .stateFile:
                viewModel.loadStateFile(url)
                activeFilePickerMode = nil
            case .none:
                activeFilePickerMode = nil
            }
        }
        #if os(macOS)
        .task {
            while true {
                // Exit on cancellation: `try?` would swallow CancellationError and
                // turn this loop into a busy-spin once the sleep stops sleeping.
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                let pressed = NSEvent.modifierFlags.contains(.command)
                if isCommandPressed != pressed { isCommandPressed = pressed }
            }
        }
        #endif
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        // macOS: calculator | printer | debug
        // Calculator uses its intrinsic width; debug panel absorbs extra space.
        HStack(spacing: 0) {
            calculatorBody()
                .fixedSize(horizontal: true, vertical: false)
            Divider()
            PrinterView()
                .frame(minWidth: 220, maxWidth: 320)
            Divider()
            DebugView(activeFilePickerMode: $activeFilePickerMode)
                .frame(minWidth: 220)
        }
        #else
        // iOS/iPadOS: side-by-side when wide, button-navigated pages when portrait
        GeometryReader { geo in
            // Hide button labels when the calculator is too narrow to fit them comfortably.
            let showLabels = geo.size.width >= 1300
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    calculatorBody(showLabels: showLabels)
                        .fixedSize(horizontal: true, vertical: false)
                    Divider()
                    PrinterView()
                        .frame(minWidth: 290, maxWidth: 360)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Divider()
                        DebugView(activeFilePickerMode: $activeFilePickerMode)
                            .frame(minWidth: 220)
                    }
                }
            } else {
                portraitPages(showLabels: showLabels)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { portraitPage = .calc }
                    .onChange(of: debugPageEnabled) { _, enabled in
                        if !enabled && portraitPage == .debug { portraitPage = .printer }
                    }
            }
        }
        #endif
    }

    private func calculatorBody(showLabels: Bool = true) -> some View {
        ZStack {
            Color(red: 29/255, green: 29/255, blue: 28/255)

            VStack(spacing: 0) {
                KeyboardView()
                Spacer()
                cardReaderBar(showLabels: showLabels)
            }
            .background(Color(white: 29.0/255.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    // Identifiable wrapper so .sheet(item:) works with the enum
    private struct PickerItem: Identifiable {
        let mode: CardPickerView.Mode
        var id: Int { mode == .load ? 0 : 1 }
    }

    // MARK: - Card reader bar

    private func cardReaderBar(showLabels: Bool = true) -> some View {
        HStack(spacing: 12) {
            #if os(macOS)
            Button(isCommandPressed ? "Clean" : "Reset",
                   systemImage: isCommandPressed ? "xmark.circle.fill" : "arrow.counterclockwise") {
                if NSEvent.modifierFlags.contains(.command) {
                    viewModel.cleanResetMachine()
                } else {
                    viewModel.resetMachine()
                }
            }
            .foregroundStyle(isCommandPressed ? .red : .orange)
            .labelStyle(showLabel: showLabels)
            #else
            Button("Reset", systemImage: "arrow.counterclockwise") {
                if !resetLongPressTriggered {
                    triggerResetFeedback()
                    viewModel.resetMachine()
                }
            }
            .foregroundStyle(.orange)
            .labelStyle(showLabel: showLabels)
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 1.0).onEnded { _ in
                    triggerMemoryClearFeedback()
                    viewModel.cleanResetMachine()
                    resetLongPressTriggered = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        resetLongPressTriggered = false
                    }
                }
            )
            #endif

            #if !os(macOS)
            modelPicker
                .colorScheme(.dark)
            #endif

            Divider().frame(height: 20)

            Spacer()

            if viewModel.model.hasCardReader {
                if viewModel.cardState == .noCard {
                    Button("Crd", systemImage: "square.and.arrow.down") {
                        viewModel.cardPickerMode = .load
                    }
                    .labelStyle(showLabel: showLabels)
                    .controlSize(.regular)
                    Button("Crd", systemImage: "plus.rectangle") {
                        viewModel.cardPickerMode = .save
                    }
                    .labelStyle(showLabel: showLabels)
                    .controlSize(.regular)
                } else {
                    Button("Eject Card", systemImage: "eject") {
                        viewModel.ejectIfSwiping()
                    }
                    .labelStyle(showLabel: showLabels)
                }
            }
            #if os(macOS)
            Divider().frame(height: 20)
            Button("Preset") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = Self.stateFileTypes
                panel.allowsOtherFileTypes = true
                panel.message = "Select a .ti59, .ti58, or .ti58c state file"
                if panel.runModal() == .OK, let url = panel.url {
                    viewModel.loadStateFile(url)
                }
            }
            #else
            Divider().frame(height: 20)
            Button("Preset", systemImage: "doc.badge.arrow.up") {
                activeFilePickerMode = .stateFile
            }
            .labelStyle(showLabel: showLabels)
            .controlSize(.large)
            Divider().frame(height: 20)
            Button("Settings", systemImage: "gear") {
                showingSettings = true
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            #endif
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(white: 0.15))
        .foregroundStyle(.white)
    }

    // MARK: - Model picker

    private var modelPicker: some View {
        Picker("Model", selection: .init(
            get: { viewModel.model },
            set: { newModel in Task { await viewModel.start(model: newModel) } }
        )) {
            ForEach(MachineModel.allCases) { m in
                Text(m.displayName).tag(m)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    #if !os(macOS)
    @ViewBuilder
    private func portraitPages(showLabels: Bool) -> some View {
        ZStack {
            switch portraitPage {
            case .calc:
                calculatorBody(showLabels: showLabels)
                    .overlay(alignment: .topLeading) {
                        if debugPageEnabled {
                            pageArrow(systemImage: "chevron.left") { portraitPage = .debug }
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        pageArrow(systemImage: "chevron.right") { portraitPage = .printer }
                    }
            case .printer:
                PrinterView(portraitTopInset: 20)
                    .overlay(alignment: .topLeading) {
                        pageArrow(systemImage: "chevron.left") { portraitPage = .calc }
                    }
                    .overlay(alignment: .topTrailing) {
                        if debugPageEnabled {
                            pageArrow(systemImage: "chevron.right") { portraitPage = .debug }
                        }
                    }
            case .debug:
                DebugView(activeFilePickerMode: $activeFilePickerMode, portraitTopInset: 36)
                    .overlay(alignment: .topLeading) {
                        pageArrow(systemImage: "chevron.left") { portraitPage = .printer }
                    }
                    .overlay(alignment: .topTrailing) {
                        pageArrow(systemImage: "chevron.right") { portraitPage = .calc }
                    }
            }
        }
    }

    private func pageArrow(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 2)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
    #endif
}

// MARK: - Helpers

private extension View {
    /// Applies `.titleAndIcon` when `showLabel` is true, `.iconOnly` otherwise.
    @ViewBuilder
    func labelStyle(showLabel: Bool) -> some View {
        if showLabel { self.labelStyle(.titleAndIcon) }
        else { self.labelStyle(.iconOnly) }
    }
}

#Preview {
    CalculatorView()
        .environment(EmulatorViewModel())
}
