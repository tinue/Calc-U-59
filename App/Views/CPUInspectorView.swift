import SwiftUI

/// Detailed CPU inspector for frozen state.
/// Shows 32 snapshots with full state inspection and proper scrolling navigation.
struct CPUInspectorView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var selectedIndex: Int? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let baseFontSize = adaptiveFontSize(width: geo.size.width)

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

                    Button(action: {
                        vm.stepFrozen()
                    }) {
                        Text("STEP")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(white: 0.25))
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
                .background(Color(white: 0.07))

                // Instructions list with scrollbar
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(vm.cpuInspectorHistory.enumerated()), id: \.offset) { idx, snapshot in
                                let isSelected = (selectedIndex == idx)
                                let opacity = snapshot.isHistory ? 1.0 : 0.4  // Dim speculative instructions
                                let bgColor: Color = snapshot.isCurrent ? Color.green.opacity(0.35) : (isSelected ? Color(white: 0.20) : Color.clear)

                                HStack(spacing: 8) {
                                    Text(String(format: "%04X", snapshot.pc))
                                        .foregroundStyle(.white.opacity(0.9 * opacity))

                                    Text(String(format: "%04X", snapshot.opcode))
                                        .foregroundStyle(.white.opacity(0.7 * opacity))

                                    Text(snapshot.disasm)
                                        .foregroundStyle(.white.opacity(0.85 * opacity))
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .font(.system(size: baseFontSize + 2, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(bgColor)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = (isSelected ? nil : idx)
                                    isFocused = true
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
                        .onChange(of: vm.cpuInspectorUpdateID) { _, _ in
                            // Auto-select current instruction whenever snapshot rebuilds (freeze or step)
                            if let currentIdx = vm.cpuInspectorHistory.firstIndex(where: { $0.isCurrent }) {
                                selectedIndex = currentIdx
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    proxy.scrollTo(currentIdx, anchor: .center)
                                }
                            }
                        }
                        .onAppear {
                            // Fallback: history already populated when view appears
                            if let currentIdx = vm.cpuInspectorHistory.firstIndex(where: { $0.isCurrent }) {
                                selectedIndex = currentIdx
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    proxy.scrollTo(currentIdx, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(height: 200)

                // State display sections
                if let idx = selectedIndex, idx >= 0, idx < vm.cpuInspectorHistory.count {
                    let snap = vm.cpuInspectorHistory[idx]
                    let cpu = snap.frame

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            // Registers
                            inspectorSection(title: "REGISTERS") {
                                VStack(alignment: .leading, spacing: 2) {
                                    registerDisplay("A",    cpu.A,    baseFontSize: baseFontSize)
                                    registerDisplay("B",    cpu.B,    baseFontSize: baseFontSize)
                                    registerDisplay("C",    cpu.C,    baseFontSize: baseFontSize)
                                    registerDisplay("D",    cpu.D,    baseFontSize: baseFontSize)
                                    registerDisplay("E",    cpu.E,    baseFontSize: baseFontSize)
                                    registerDisplay("Sout", cpu.Sout, baseFontSize: baseFontSize)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }

                            // Control registers
                            inspectorSection(title: "CONTROL REGISTERS") {
                                let cond = (cpu.flags & 0x0800) != 0 ? 1 : 0
                                let idle = (cpu.flags & 0x0001) != 0 ? 1 : 0
                                let postDigit = Int(cpu.postDigit)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("KR: \(String(format: "%04X", cpu.KR)) [\(bin16(cpu.KR))]")
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text("fA: \(String(format: "%04X", cpu.fA)) [\(bin16(cpu.fA))]")
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text("fB: \(String(format: "%04X", cpu.fB)) [\(bin16(cpu.fB))]")
                                        .foregroundStyle(.white.opacity(0.85))
                                    HStack(spacing: 16) {
                                        Text("SR: \(String(format: "%04X", cpu.SR))")
                                            .foregroundStyle(.white.opacity(0.85))
                                        Text("R5: \(cpu.R5)")
                                            .foregroundStyle(.white.opacity(0.85))
                                        Spacer()
                                    }
                                    HStack(spacing: 16) {
                                        Text(String(format: "COND: %d", cond))
                                            .foregroundStyle(cond == 1 ? Color.yellow.opacity(0.4) : Color.yellow)
                                        Text(String(format: "IDLE: %d", idle))
                                            .foregroundStyle(idle == 1 ? .white : .white.opacity(0.45))
                                        Text(String(format: "DIGIT: %2d", postDigit))
                                            .foregroundStyle(.white.opacity(0.85))
                                        Spacer()
                                    }
                                }
                                .font(.system(size: baseFontSize + 2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }

                            // Display state
                            inspectorSection(title: "DISPLAY STATE") {
                                let displayOn = cpu.dispFilter < 3
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 16) {
                                        Text("Filter: \(cpu.dispFilter)")
                                            .foregroundStyle(.white.opacity(0.85))
                                        Text(displayOn ? "ON" : "BLANKED")
                                            .foregroundStyle(displayOn ? Color.green.opacity(0.85) : Color.red.opacity(0.7))
                                        Spacer()
                                    }
                                }
                                .font(.system(size: baseFontSize + 2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(4)
                    }
                    .textSelection(.enabled)
                }

                Spacer()
            }
            .focusable()
            .focused($isFocused)
            .onAppear {
                isFocused = true
                selectedIndex = nil
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
            .background(Color(white: 0.10))
        }
    }

    // MARK: - Section Container (mirrors LIVE SectionBox)

    private func inspectorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(white: 0.07))
            content()
                .background(Color(white: 0.13))
        }
        .cornerRadius(3)
    }

    // MARK: - Register Row

    private func registerDisplay(_ label: String, _ nibbles: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8), baseFontSize: CGFloat) -> some View {
        let array = [nibbles.0, nibbles.1, nibbles.2, nibbles.3, nibbles.4, nibbles.5, nibbles.6, nibbles.7,
                     nibbles.8, nibbles.9, nibbles.10, nibbles.11, nibbles.12, nibbles.13, nibbles.14, nibbles.15]
        let nibbleString = array.map { String(format: "%X", $0) }.joined()
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: baseFontSize + 2, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()

            Text(nibbleString)
                .font(.system(size: baseFontSize + 2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()
        }
    }

    // MARK: - Helpers

    private func bin16(_ v: UInt16) -> String {
        let s = String(v, radix: 2)
        return String(repeating: "0", count: max(0, 16 - s.count)) + s
    }

    // MARK: - Adaptive Font Sizing

    private func adaptiveFontSize(width: CGFloat) -> CGFloat {
        if width < 350 {
            return 9
        } else if width < 500 {
            return 11
        } else {
            return 13
        }
    }
}
