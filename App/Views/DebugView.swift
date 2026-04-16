import SwiftUI

struct DebugView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var tab: DebugTab = .live
    enum DebugTab { case live, cpu, log }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("LIVE", .live)
                tabButton("CPU", .cpu)
                tabButton("LOG", .log)
                Spacer()
            }
            .background(Color(white: 0.07))

            // Tab content
            switch tab {
            case .live: LiveDebugView()
            case .cpu:
                if vm.isFrozen {
                    CPUInspectorView()
                } else {
                    SimpleLiveCPUView()
                }
            case .log:  StaticDebugContent()
            }
        }
        .background(Color(white: 0.10))
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
        HStack(spacing: 10) {
            Button("Vars") { vm.debugDumpVars() }

            Button("SCOM") { vm.debugDumpSCOM() }

            Button("Prog") { vm.debugDumpProg() }

            Button("Memory") { vm.debugDumpMemory() }

            Spacer()

            // Clear button
            Button {
                vm.clearDebug()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .disabled(vm.debugLines.isEmpty)

            // C indicator drop logger — prints one line per drop event to console
            Button { vm.cIndicatorDebug.toggle() } label: {
                HStack(spacing: 4) {
                    Text("TRACE")
                    Circle()
                        .fill(vm.cIndicatorDebug ? Color.orange : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // DEBUG level toggle: OFF (gray) → INFO (orange) → DEBUG (red) → OFF
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .font(.caption.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }
}

#Preview {
    DebugView()
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
