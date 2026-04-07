import SwiftUI

/// Detailed CPU inspector for frozen state.
/// Shows 32 snapshots with full state inspection and proper scrolling navigation.
struct CPUInspectorView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var selectedIndex: Int? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Control bar
            HStack(spacing: 12) {
                Button(action: vm.unfreeze) {
                    Text("RESUME")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("PAUSED")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.15))
            .focusable()
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onKeyPress(.upArrow) {
                guard !vm.cpuInspectorHistory.isEmpty else { return .ignored }
                if let idx = selectedIndex {
                    if idx > 0 {
                        selectedIndex = idx - 1
                    }
                } else {
                    selectedIndex = vm.cpuInspectorHistory.count - 1
                }
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !vm.cpuInspectorHistory.isEmpty else { return .ignored }
                if let idx = selectedIndex {
                    if idx < vm.cpuInspectorHistory.count - 1 {
                        selectedIndex = idx + 1
                    } else {
                        selectedIndex = nil
                    }
                }
                return .handled
            }

            // Instructions list with scrollbar
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(vm.cpuInspectorHistory.enumerated()), id: \.offset) { idx, snapshot in
                            let isSelected = (selectedIndex == idx)
                            let opacity = snapshot.isHistory ? 1.0 : 0.4  // Dim speculative instructions
                            let bgColor: Color = snapshot.isCurrent ? Color.green.opacity(0.35) : (isSelected ? Color(white: 0.20) : Color.clear)

                            HStack(spacing: 8) {
                                Text(String(format: "0x%04X", snapshot.pc))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.9 * opacity))
                                    .frame(width: 50, alignment: .leading)

                                Text(String(format: "%04X", snapshot.opcode))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7 * opacity))
                                    .frame(width: 50, alignment: .leading)

                                Text(snapshot.disasm)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85 * opacity))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(bgColor)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = (isSelected ? nil : idx)
                            }
                            .id(idx)
                        }
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if let idx = newValue {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(idx, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: vm.cpuInspectorHistory.count) {
                        // When history is loaded, scroll to the frozen instruction (isCurrent)
                        if let currentIdx = vm.cpuInspectorHistory.firstIndex(where: { $0.isCurrent }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(currentIdx, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 200)

            // State display sections
            if let idx = selectedIndex, idx >= 0, idx < vm.cpuInspectorHistory.count {
                let snap = vm.cpuInspectorHistory[idx]
                let cpu = snap.cpuState

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Registers
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REGISTERS")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.6))

                            registerDisplay("A", cpu.A)
                            registerDisplay("B", cpu.B)
                            registerDisplay("C", cpu.C)
                            registerDisplay("D", cpu.D)
                            registerDisplay("E", cpu.E)
                            registerDisplay("Sout", cpu.Sout)
                        }
                        .padding(8)
                        .background(Color(white: 0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Control registers
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CONTROL REGISTERS")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.6))

                            HStack(spacing: 16) {
                                Text("KR: \(String(format: "0x%04X", cpu.KR))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("SR: \(String(format: "0x%04X", cpu.SR))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            HStack(spacing: 16) {
                                Text("fA: \(String(format: "0x%04X", cpu.fA))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("fB: \(String(format: "0x%04X", cpu.fB))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            HStack(spacing: 16) {
                                Text("flags: \(String(format: "0x%04X", cpu.flags))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("R5: \(String(format: "0x%X", cpu.R5))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(8)
                        .background(Color(white: 0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(8)
                }
            }

            Spacer()
        }
        .background(Color(white: 0.10))
    }

    private func registerDisplay(_ label: String, _ nibbles: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) -> some View {
        let array = [nibbles.0, nibbles.1, nibbles.2, nibbles.3, nibbles.4, nibbles.5, nibbles.6, nibbles.7,
                     nibbles.8, nibbles.9, nibbles.10, nibbles.11, nibbles.12, nibbles.13, nibbles.14, nibbles.15]
        return HStack(spacing: 1) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30, alignment: .leading)

            HStack(spacing: 1) {
                ForEach(array, id: \.self) { n in
                    Text(String(format: "%X", n))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer()
        }
    }
}
