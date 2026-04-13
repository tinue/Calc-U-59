import SwiftUI
import UniformTypeIdentifiers

struct CalculatorView: View {
    @Environment(EmulatorViewModel.self) var viewModel
    #if os(macOS)
    @State private var isCommandPressed = false
    #else
    @State private var showingPrinter = false
    @State private var showingStateFilePicker = false
    #endif

    var body: some View {
        layout
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
        .fileImporter(
            isPresented: $showingStateFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "ti59") ?? .data,
                UTType(filenameExtension: "ti58") ?? .data,
                UTType(filenameExtension: "ti58c") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.loadStateFile(url)
            }
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
        #if os(macOS)
        .task {
            while true {
                try? await Task.sleep(for: .milliseconds(50))
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
            DebugView()
                .frame(minWidth: 220)
        }
        #else
        // iOS/iPadOS: side-by-side when wide, button-navigated pages when portrait
        GeometryReader { geo in
            // In portrait, hide button labels when the calculator is too narrow to
            // fit them comfortably (all iPhones; wide iPads always have room).
            let isPortrait = geo.size.height >= geo.size.width
            let showLabels = !isPortrait || geo.size.width >= 500
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    calculatorBody(showLabels: showLabels)
                        .fixedSize(horizontal: true, vertical: false)
                    Divider()
                    PrinterView()
                        .frame(minWidth: 260, maxWidth: 360)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Divider()
                        DebugView()
                            .frame(minWidth: 220)
                    }
                }
            } else {
                ZStack {
                    if showingPrinter {
                        PrinterView()
                            .overlay(alignment: .topLeading) {
                                pageArrow(systemImage: "chevron.left") {
                                    showingPrinter = false
                                }
                            }
                    } else {
                        calculatorBody(showLabels: showLabels)
                            .overlay(alignment: .topTrailing) {
                                pageArrow(systemImage: "chevron.right") {
                                    showingPrinter = true
                                }
                            }
                    }
                }
            }
        }
        #endif
    }

    private func calculatorBody(showLabels: Bool = true) -> some View {
        VStack(spacing: 0) {
            KeyboardView()
            cardReaderBar(showLabels: showLabels)
        }
        .background(Color(white: 0.08))
    }

    // Identifiable wrapper so .sheet(item:) works with the enum
    private struct PickerItem: Identifiable {
        let mode: CardPickerView.Mode
        var id: Int { mode == .load ? 0 : 1 }
    }

    // MARK: - Card reader bar

    private func cardReaderBar(showLabels: Bool = true) -> some View {
        HStack(spacing: 16) {
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
                viewModel.resetMachine()
            }
            .foregroundStyle(.orange)
            .labelStyle(showLabel: showLabels)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.0).onEnded { _ in
                    viewModel.cleanResetMachine()
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
                    .controlSize(.large)
                    Button("Crd", systemImage: "plus.rectangle") {
                        viewModel.cardPickerMode = .save
                    }
                    .labelStyle(showLabel: showLabels)
                    .controlSize(.large)
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
                panel.allowedContentTypes = [UTType(filenameExtension: "ti59") ?? .data,
                                             UTType(filenameExtension: "ti58") ?? .data,
                                             UTType(filenameExtension: "ti58c") ?? .data]
                panel.allowsOtherFileTypes = true
                panel.message = "Select a .ti59, .ti58, or .ti58c state file"
                if panel.runModal() == .OK, let url = panel.url {
                    viewModel.loadStateFile(url)
                }
            }
            #else
            Divider().frame(height: 20)
            Button("Preset", systemImage: "doc.badge.arrow.up") {
                showingStateFilePicker = true
            }
            .labelStyle(showLabel: showLabels)
            .controlSize(.large)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
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
    private func pageArrow(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(8)
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
