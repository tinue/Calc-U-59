import SwiftUI

/// Unified CPU inspector: shows instruction history and register state live (when enabled)
/// or frozen (when paused). Header mirrors the CALCULATOR tab style.
struct CPUInspectorView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var selectedIndex: Int? = nil
    @FocusState private var isFocused: Bool

    // Unified instruction list — live from cpuDebugSnapshot when running, cpuInspectorHistory when frozen.
    private var displayHistory: [EmulatorViewModel.InspectorSnapshot] {
        if vm.isFrozen {
            return vm.cpuInspectorHistory
        } else {
            let instrs = vm.cpuDebugSnapshot.recentInstructions
            return instrs.enumerated().map { idx, instr in
                EmulatorViewModel.InspectorSnapshot(
                    pc: instr.pc,
                    opcode: instr.opcode,
                    disasm: instr.disasm,
                    frame: instr.frame,
                    isHistory: true,
                    isCurrent: idx == instrs.count - 1
                )
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let baseFontSize = adaptiveFontSize(width: geo.size.width)

            VStack(spacing: 0) {
                cpuHeader(baseFontSize: baseFontSize)

                // Instructions list
                ScrollView {
                    ScrollViewReader { proxy in
                        let history = displayHistory
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.offset) { idx, snapshot in
                                let isSelected = (selectedIndex == idx)
                                let opacity = snapshot.isHistory ? 1.0 : 0.4
                                let bgColor: Color = snapshot.isCurrent
                                    ? Color.green.opacity(0.35)
                                    : (isSelected ? Color(white: 0.20) : Color.clear)

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
                            // Freeze or step: auto-select and scroll to current instruction.
                            if let currentIdx = vm.cpuInspectorHistory.firstIndex(where: { $0.isCurrent }) {
                                selectedIndex = currentIdx
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    proxy.scrollTo(currentIdx, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: vm.cpuDebugSnapshot) { _, _ in
                            guard !vm.isFrozen else { return }
                            let last = displayHistory.count - 1
                            guard last >= 0 else { return }
                            selectedIndex = last
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                        .onAppear {
                            if vm.isFrozen {
                                if let currentIdx = vm.cpuInspectorHistory.firstIndex(where: { $0.isCurrent }) {
                                    selectedIndex = currentIdx
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        proxy.scrollTo(currentIdx, anchor: .center)
                                    }
                                }
                            } else {
                                let last = displayHistory.count - 1
                                if last >= 0 {
                                    selectedIndex = last
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        proxy.scrollTo(last, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(height: 200)

                // State display for selected instruction
                let history = displayHistory
                if let idx = selectedIndex, idx >= 0, idx < history.count {
                    let snap = history[idx]
                    let cpu = snap.frame

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
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
                                        Text("COND: \(cond)")
                                            .foregroundStyle(cond == 1 ? Color.yellow.opacity(0.4) : Color.yellow)
                                        Text("IDLE: \(idle)")
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

                            inspectorSection(title: "DISPLAY STATE") {
                                let displayOn = cpu.displayOn != 0
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 16) {
                                        Text("Decay: \(cpu.maxDigitDecay)")
                                            .foregroundStyle(.white.opacity(0.85))
                                        Text(displayOn ? "ON" : "OFF")
                                            .foregroundStyle(displayOn ? Color.green.opacity(0.85) : Color.red.opacity(0.7))
                                        Spacer()
                                    }
                                }
                                .font(.system(size: baseFontSize + 2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }

                            romHeatmapSection(width: geo.size.width)
                        }
                        .padding(4)
                    }
                    .textSelection(.enabled)
                }

                Spacer()
            }
            .focusable()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress(.upArrow) {
                let history = displayHistory
                guard !history.isEmpty else { return .ignored }
                if let idx = selectedIndex {
                    if idx > 0 { selectedIndex = idx - 1 }
                } else {
                    selectedIndex = history.count - 1
                }
                return .handled
            }
            .onKeyPress(.downArrow) {
                let history = displayHistory
                guard !history.isEmpty else { return .ignored }
                if let idx = selectedIndex {
                    if idx < history.count - 1 {
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

    // MARK: - Header

    private func cpuHeader(baseFontSize: CGFloat) -> some View {
        HStack {
            Text("CPU DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if vm.isFrozen {
                Button("STEP") { vm.stepFrozen() }
                    .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan)
            }
            if vm.pendingFreezeOnPCChange {
                Button("ARMED") { vm.pendingFreezeOnPCChange = false }
                    .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.yellow)
            } else {
                Button("FREEZE ON START") { vm.freezeOnNextPCChange() }
                    .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
            }
            Button(vm.isFrozen ? "RESUME" : "FREEZE") {
                vm.isFrozen ? vm.unfreeze() : vm.freeze()
            }
            .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(vm.isFrozen ? Color.orange : Color(white: 0.6))
            Circle()
                .fill(vm.cpuDebugEnabled ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Toggle("", isOn: .init(
                get: { vm.cpuDebugEnabled },
                set: { vm.cpuDebugEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.07))
    }

    // MARK: - Section Container

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

    // MARK: - ROM Heatmap Section

    private func romHeatmapSection(width: CGFloat) -> some View {
        let hitCount  = vm.romHitCount
        let maxCount  = vm.romMaxHitCount
        let currentPC = Int(vm.cpuDebugSnapshot.currentPC)
        let cols      = 80
        let rows      = 64
        let cellSize  = max(2.0, width / CGFloat(cols))

        return VStack(spacing: 0) {
            HStack {
                Text("ROM HEATMAP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button("CLR") { vm.clearRomHeatmap() }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(white: 0.07))

            Canvas { context, size in
                let cw = size.width / CGFloat(cols)
                let ch = cw
                for addr in 0..<0x1400 {
                    let col = addr % cols
                    let row = addr / cols
                    let rect = CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch,
                                      width: max(1, cw - 0.5), height: max(1, ch - 0.5))
                    let color: Color = addr == currentPC
                        ? .green
                        : heatColor(count: hitCount[addr], maxCount: maxCount)
                    context.fill(Path(rect), with: .color(color))
                }
            }
            .frame(height: CGFloat(rows) * cellSize)
            .background(Color(white: 0.13))
        }
        .cornerRadius(3)
    }

    // Logarithmic normalization: the hottest address (maxCount) maps to step 5 (bright yellow);
    // an address hit once maps to step 1 (dark amber); never-hit stays dark gray.
    private func heatColor(count: UInt32, maxCount: UInt32) -> Color {
        guard count > 0, maxCount > 0 else { return Color(white: 0.18) }
        let ratio = log(Double(count) + 1) / log(Double(maxCount) + 1)  // 0.0 ... 1.0
        let step  = max(1, Int(ratio * 5.0))                             // 1 ... 5
        switch step {
        case 5:  return Color(hue: 0.14, saturation: 1.0, brightness: 1.00)  // bright yellow
        case 4:  return Color(hue: 0.12, saturation: 1.0, brightness: 0.90)  // light amber
        case 3:  return Color(hue: 0.10, saturation: 1.0, brightness: 0.75)  // amber
        case 2:  return Color(hue: 0.08, saturation: 1.0, brightness: 0.55)  // dark amber
        default: return Color(hue: 0.06, saturation: 0.9, brightness: 0.35)  // very dark amber
        }
    }

    // MARK: - Helpers

    private func bin16(_ v: UInt16) -> String {
        let s = String(v, radix: 2)
        return String(repeating: "0", count: max(0, 16 - s.count)) + s
    }

    private func adaptiveFontSize(width: CGFloat) -> CGFloat {
        if width < 350 { return 9 }
        else if width < 500 { return 11 }
        else { return 13 }
    }
}
