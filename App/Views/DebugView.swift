import SwiftUI
import UniformTypeIdentifiers

struct DebugView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var tab: DebugTab = .live
    @Binding var activeFilePickerMode: CalculatorView.FilePickerMode?
    var portraitTopInset: CGFloat = 0
    enum DebugTab { case live, cpu, log }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("CALCULATOR", .live)
                    .disabled(vm.asmOverlayActive)
                    .opacity(vm.asmOverlayActive ? 0.35 : 1.0)
                tabButton("CPU", .cpu)
                tabButton("LOG", .log)
                Spacer()
            }
            .padding(.top, portraitTopInset)
            .background(Color(white: 0.07))

            // Tab content
            switch tab {
            case .live: LiveDebugView()
            case .cpu:
                VStack(spacing: 0) {
                    CPUInspectorView()
                        .frame(maxHeight: .infinity)

                    Divider().background(Color(white: 0.25))

                    ASMDebugContent(activeFilePickerMode: $activeFilePickerMode)
                }
            case .log:
                StaticDebugContent()
            }
        }
        .background(Color(white: 0.10))
        .onChange(of: vm.asmOverlayActive) { _, active in
            if active { tab = .cpu }
        }
    }

    private func tabButton(_ label: String, _ tab_: DebugTab) -> some View {
        Button(label) { tab = tab_ }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tab == tab_ ? .white : .white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(tab == tab_ ? Color(white: 0.20) : Color.clear)
    }
}

// MARK: - Static Debug Content (original DebugView body)

private struct StaticDebugContent: View {
    @Environment(EmulatorViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            header
            outputArea
            buttonBar
        }
        .background(Color(white: 0.10))
    }

    // MARK: - Header

    private var header: some View {
        Text("DEBUG LOG")
            .font(.caption.bold())
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(white: 0.07))
    }

    // MARK: - Selectable output area

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(vm.debugLines.isEmpty ? " " : vm.debugLines.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
                    .id(vm.debugClearID)
                Color.clear.frame(height: 1).id("bottom")
            }
            .background(Color(white: 0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(white: 0.25), lineWidth: 0.5)
            )
            .onChange(of: vm.debugLines.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Button bar

    private var buttonBar: some View {
        VStack(spacing: 8) {
            // Row 1: Main action buttons
            HStack(spacing: 8) {
                Button("SCOM") { vm.debugDumpSCOM() }
                Button("Memory") { vm.debugDumpMemory() }
                Button("Prog") { vm.debugDumpProg() }
                Button("Vars") { vm.debugDumpVars() }

                Spacer()

                // Clear button
                Button {
                    vm.clearDebug()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .disabled(vm.debugLines.isEmpty)
            }

            // Row 2: Status toggles
            HStack(spacing: 8) {
                Button { vm.cIndicatorDebug.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("TRACE")
                        Circle()
                            .fill(vm.isTraceAvailable
                                ? (vm.cIndicatorDebug ? Color.orange : Color.gray.opacity(0.4))
                                : Color.red.opacity(0.5))
                            .frame(width: 8, height: 8)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(vm.isTraceAvailable ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: vm.isTraceAvailable ? 0.25 : 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!vm.isTraceAvailable)

                Button { vm.toggleDebug() } label: {
                    HStack(spacing: 4) {
                        Text("LOG")
                        Circle()
                            .fill({
                                switch vm.debugLevel {
                                case .off:   return Color.gray.opacity(0.4)
                                case .info:  return Color.orange
                                case .debug: return Color.red
                                }
                            }())
                            .frame(width: 8, height: 8)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }
}

private struct ASMDebugContent: View {
    @Environment(EmulatorViewModel.self) var vm
    @Binding var activeFilePickerMode: CalculatorView.FilePickerMode?

    var body: some View {
        VStack(spacing: 0) {
            Text("ASM OVERLAY")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(white: 0.07))

            VStack(alignment: .leading, spacing: 8) {
                Text("File: \(vm.asmFileName)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85))
                Text("Words: \(vm.asmWordCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.75))
                Text(vm.asmStatusMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(white: 0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(white: 0.25), lineWidth: 0.5)
            )
            .padding(8)

            HStack(spacing: 8) {
                Button("Select File") {
                    activeFilePickerMode = .asm
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Run") {
                    vm.runASMOverlay()
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(!vm.canRunASM)

                Button("Clear") {
                    vm.clearASMOverlay()
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.15))
        }
        .background(Color(white: 0.10))
    }
}

#Preview {
    @Previewable @State var mode: CalculatorView.FilePickerMode? = nil
    DebugView(activeFilePickerMode: $mode)
        .environment({
            let vm = EmulatorViewModel()
            vm.debugLevel = .info
            vm.debugLines = [
                "── RAM (part=60) ──",
                "RAM[60] = 3.141592653589",
                "RAM[65] = 7.77e+22",
                "── SCOM ──",
                "SCOM[9] = [6, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]",
            ]
            return vm
        }())
        .frame(width: 260, height: 400)
}
