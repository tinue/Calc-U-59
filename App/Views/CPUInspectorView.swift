import SwiftUI
import Combine

// MARK: - Heatmap Renderer

/// Off-screen 80×64 pixel buffer for the ROM heatmap.
/// Cells are only repainted when their heat step increases — steps are monotonically non-decreasing.
private final class HeatmapRenderer: ObservableObject {
    static let cols = 80
    static let rows = 64
    static let cellCount = cols * rows  // 5 120

    @Published private(set) var cgImage: CGImage? = nil
    private var cellSteps: [UInt8] = Array(repeating: 0xFF, count: cellCount)  // 0xFF = uninitialized
    private var pixelBuf: [UInt8]  = Array(repeating: 0,    count: cellCount * 4)

    func update(hitCount: [UInt32]) {
        var anyChanged = false
        for addr in 0..<Self.cellCount {
            let count   = addr < hitCount.count ? hitCount[addr] : 0
            let newStep = heatStep(count)
            guard newStep != cellSteps[addr] else { continue }
            cellSteps[addr] = newStep
            setPixel(addr: addr, step: newStep)
            anyChanged = true
        }
        if anyChanged { cgImage = makeImage() }
    }

    func reset() {
        cellSteps = Array(repeating: 0xFF, count: Self.cellCount)
        for addr in 0..<Self.cellCount { setPixel(addr: addr, step: 0) }
        cgImage = makeImage()
    }

    // Fixed absolute thresholds: first hit → step 1 (immediately visible, dark amber).
    // Steps only increase — enables incremental repaint.
    private func heatStep(_ count: UInt32) -> UInt8 {
        switch count {
        case 0:         return 0
        case 1...2:     return 1
        case 3...9:     return 2
        case 10...49:   return 3
        case 50...249:  return 4
        default:        return 5
        }
    }

    private func setPixel(addr: Int, step: UInt8) {
        let (r, g, b) = rgb(for: step)
        let base = addr * 4
        pixelBuf[base]   = r
        pixelBuf[base+1] = g
        pixelBuf[base+2] = b
        pixelBuf[base+3] = 255
    }

    // Pre-computed RGB for each step (HSB → RGB: hue 0.06–0.14, sat 0.9–1.0, bri 0.35–1.0).
    private func rgb(for step: UInt8) -> (UInt8, UInt8, UInt8) {
        switch step {
        case 0:  return (46,  46,  46)   // dark gray  (cold)
        case 1:  return (89,  38,   9)   // very dark amber
        case 2:  return (140, 67,   0)   // dark amber
        case 3:  return (191, 115,  0)   // amber
        case 4:  return (230, 165,  0)   // light amber
        default: return (255, 214,  0)   // bright yellow
        }
    }

    private func makeImage() -> CGImage? {
        pixelBuf.withUnsafeBytes { ptr -> CGImage? in
            guard let base = ptr.baseAddress else { return nil }
            guard let data = CFDataCreate(nil, base.assumingMemoryBound(to: UInt8.self), pixelBuf.count),
                  let provider = CGDataProvider(data: data) else { return nil }
            return CGImage(
                width: Self.cols, height: Self.rows,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: Self.cols * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }
    }
}

// MARK: - CPU Inspector View

/// Unified CPU inspector: shows instruction history and register state live (when enabled)
/// or frozen (when paused). Header mirrors the CALCULATOR tab style.
struct CPUInspectorView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var selectedIndex: Int? = nil
    @FocusState private var isFocused: Bool
    @StateObject private var heatmapRenderer = HeatmapRenderer()
    @State private var heatmapHoveredAddress: Int? = nil

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
            .onAppear {
                isFocused = true
                // Gate CPU tracing + snapshot building on panel visibility.
                // Entering also resets the ROM heatmap (counts start at "visible").
                vm.cpuDebugEnabled = true
            }
            .onDisappear { vm.cpuDebugEnabled = false }
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
        let freezeEnabled = !vm.isFrozen && !vm.pendingCPUScanLoopFreeze
        let freezeOnStartEnabled = !vm.isFrozen && !vm.pendingCPUScanLoopFreeze

        return HStack(spacing: 8) {
            Text("CPU DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()

            Button("FREEZE") { vm.freeze(from: .cpu) }
                .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .opacity(freezeEnabled ? 1 : 0.4)
                .disabled(!freezeEnabled)

            Button("FREEZE ON START") { vm.freezeOnScanLoopExit() }
                .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .opacity(freezeOnStartEnabled ? 1 : 0.4)
                .disabled(!freezeOnStartEnabled)

            Button("ARMED") { vm.disarmCPUScanLoopFreeze() }
                .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .opacity(vm.pendingCPUScanLoopFreeze ? 1 : 0.4)
                .disabled(!vm.pendingCPUScanLoopFreeze)

            let cpuOwned = vm.isFrozen && vm.freezeOwner == .cpu

            Button("RESUME") { vm.unfreeze() }
                .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.orange)
                .opacity(cpuOwned ? 1 : 0.4)
                .disabled(!cpuOwned)

            Button("STEP") { vm.stepFrozen() }
                .font(.system(size: baseFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.cyan)
                .opacity(cpuOwned ? 1 : 0.4)
                .disabled(!cpuOwned)
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
        let nibbleString = array.reversed().map { String(format: "%X", $0) }.joined()
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
        // Use the same isCurrent entry that highlights the instruction list row —
        // cpuDebugSnapshot.currentPC is the *next* (pre-fetch) PC, which is one ahead.
        let currentPC = displayHistory.first(where: { $0.isCurrent }).map { Int($0.pc) } ?? -1
        let cols      = CGFloat(HeatmapRenderer.cols)
        let rows      = CGFloat(HeatmapRenderer.rows)
        let cellSize  = max(2.0, width / cols)
        let cw        = width / cols  // on-screen cell width (may differ from cellSize when width < 160)

        // Convert a canvas-local point to a ROM address (nil if out of bounds).
        func addressAt(_ pt: CGPoint) -> Int? {
            let col = Int(pt.x / cw)
            let row = Int(pt.y / cellSize)
            guard col >= 0, col < Int(cols), row >= 0, row < Int(rows) else { return nil }
            return row * Int(cols) + col
        }

        return VStack(spacing: 0) {
            HStack {
                Text("ROM HEATMAP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let addr = heatmapHoveredAddress {
                    Text(String(format: "0x%04X", addr))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.85))
                        .padding(.trailing, 6)
                }
                Button("CLR") { vm.clearRomHeatmap(); heatmapRenderer.reset() }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(white: 0.07))

            // Canvas blits the cached CGImage (cheap) + draws one green PC dot per frame.
            // CGImage coordinate origin is bottom-left; SwiftUI Canvas is top-left → flip.
            Canvas { ctx, size in
                let cw = size.width  / cols
                let ch = size.height / rows
                ctx.withCGContext { cgCtx in
                    // Flip to match SwiftUI top-left coordinates for CGImage draw.
                    cgCtx.saveGState()
                    cgCtx.translateBy(x: 0, y: size.height)
                    cgCtx.scaleBy(x: 1, y: -1)
                    cgCtx.interpolationQuality = .none
                    if let img = heatmapRenderer.cgImage {
                        cgCtx.draw(img, in: CGRect(origin: .zero, size: size))
                    }
                    cgCtx.restoreGState()
                    // Green PC dot — drawn after restoreGState (back in SwiftUI coords).
                    if currentPC < 0x1400 {
                        let col = currentPC % Int(cols)
                        let row = currentPC / Int(cols)
                        cgCtx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
                        cgCtx.fill(CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch,
                                          width: max(1, cw - 0.5), height: max(1, ch - 0.5)))
                    }
                }
            }
            .frame(height: rows * cellSize)
            .background(Color(white: 0.13))
            // macOS pointer hover and iPadOS pointer device.
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): heatmapHoveredAddress = addressAt(location)
                case .ended:               heatmapHoveredAddress = nil
                }
            }
            // iOS/iPadOS finger touch: show address while held, clear on lift.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in heatmapHoveredAddress = addressAt(value.location) }
                    .onEnded   { _     in heatmapHoveredAddress = nil }
            )
            .onChange(of: vm.romHitCount) { _, hitCount in
                heatmapRenderer.update(hitCount: hitCount)
            }
            .onAppear {
                heatmapRenderer.update(hitCount: vm.romHitCount)
            }
        }
        .cornerRadius(3)
    }

    // MARK: - Helpers

    private func bin16(_ v: UInt16) -> String {
        let bits = (0..<16).map { i in (v >> (15 - i)) & 1 }
        return stride(from: 0, to: 16, by: 4)
            .map { g in bits[g..<g+4].map { String($0) }.joined() }
            .joined(separator: " ")
    }

    private func adaptiveFontSize(width: CGFloat) -> CGFloat {
        if width < 350 { return 9 }
        else if width < 500 { return 11 }
        else { return 13 }
    }
}
