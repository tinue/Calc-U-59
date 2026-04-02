import SwiftUI

struct DebugView: View {
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
        Text("DEBUG")
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
                    Text("C-DBG")
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

            // DEBUG enable toggle — styled like the TRACE button
            Button { vm.toggleDebug() } label: {
                HStack(spacing: 4) {
                    Text("D")
                    Circle()
                        .fill(vm.debugEnabled ? Color.green : Color.gray.opacity(0.4))
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
            vm.debugEnabled = true
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
