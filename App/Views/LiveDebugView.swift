import SwiftUI

struct LiveDebugView: View {
    @Environment(EmulatorViewModel.self) var vm

    var body: some View {
        GeometryReader { geo in
            let baseFontSize = adaptiveFontSize(width: geo.size.width)

            VStack(spacing: 0) {
                liveHeader(baseFontSize: baseFontSize)
                debugSection(baseFontSize: baseFontSize)
                ScrollView {
                    VStack(spacing: 1) {
                        partitionSection(baseFontSize: baseFontSize)
                        prSourceFlagSection(baseFontSize: baseFontSize)
                        programStepsSection(baseFontSize: baseFontSize)
                        scomFieldsSection(baseFontSize: baseFontSize)
                        returnAddressSection(baseFontSize: baseFontSize)
                        calcFlagsSection(baseFontSize: baseFontSize)
                        hirRegistersSection(baseFontSize: baseFontSize)
                        tRegisterSection(baseFontSize: baseFontSize)
                        dataRegistersSection(baseFontSize: baseFontSize)
                    }
                    .padding(4)
                }
                .background(Color(white: 0.10))
            }
            .background(Color(white: 0.10))
        }
    }

    // MARK: - Adaptive Font Sizing

    private func adaptiveFontSize(width: CGFloat) -> CGFloat {
        if width < 350 {
            return 9      // iPad Mini: compact
        } else if width < 500 {
            return 11     // iPad Air: normal
        } else {
            return 13     // Mac: large
        }
    }

    // MARK: - Header

    private func liveHeader(baseFontSize: CGFloat) -> some View {
        HStack {
            Text("LIVE DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if vm.isFrozen {
                Button("STEP") { vm.stepKeycode() }
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
                .fill(vm.liveDebugEnabled ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Toggle("", isOn: .init(
                get: { vm.liveDebugEnabled },
                set: { vm.liveDebugEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.07))
    }

    // MARK: - DEBUG Section

    private func debugSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "DEBUG") {
            HStack(spacing: 12) {
                Text(String(format: "FA:%04X", snap.fA))
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.65))
                Text(String(format: "FB:%04X", snap.fB))
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.65))
                Text("IO:\(snap.ioUserFlags)")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85))
                Text("KEY:\(snap.lastKey)")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Return Address Section

    private func returnAddressSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "RETURN ADDRESS") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    levelWithColor("L6", 5, snap)
                    levelWithColor("L5", 4, snap)
                    levelWithColor("L4", 3, snap)
                }
                HStack(spacing: 8) {
                    levelWithColor("L3", 2, snap)
                    levelWithColor("L2", 1, snap)
                    levelWithColor("L1", 0, snap)
                }
            }
            .font(.system(size: baseFontSize + 2, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func levelWithColor(_ label: String, _ index: Int, _ snap: LiveDebugSnapshot) -> some View {
        let sourceFlag = index < snap.returnAddressSourceFlags.count ? snap.returnAddressSourceFlags[index] : 0
        let address = index < snap.returnAddresses.count ? snap.returnAddresses[index] : 0
        let isZero = address == 0
        let color: Color
        switch sourceFlag {
        case 0: color = isZero ? Color(red: 0.10, green: 0.30, blue: 0.10) : Color(red: 0.25, green: 0.60, blue: 0.25)    // Green for RAM
        case 1: color = isZero ? Color(red: 0.30, green: 0.10, blue: 0.30) : Color(red: 0.60, green: 0.25, blue: 0.60)    // Purple for library
        case 8: color = isZero ? Color(red: 0.35, green: 0.28, blue: 0.10) : Color(red: 0.70, green: 0.60, blue: 0.25)    // Yellow for ROM
        default: color = isZero ? Color(white: 0.5) : Color(white: 0.8)                                                    // Gray for unknown
        }
        return Text("\(label):\(String(format: "%03d", address))")
            .foregroundStyle(color)
    }

    // MARK: - Data Registers Section (Variables)

    private func dataRegistersSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "VARIABLES") {
            if snap.nonZeroRegs.isEmpty {
                Text("(all zero)")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snap.nonZeroRegs.enumerated()), id: \.offset) { _, entry in
                        let label = entry.isHidden ? String(format: "H%02d", entry.num) : String(format: "R%02d", entry.num)
                        Text(String(format: "%@ = %.10g", label, entry.value))
                            .font(.system(size: baseFontSize + 2, design: .monospaced))
                            .foregroundStyle(Color(white: 0.85))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Program Steps Section

    @ViewBuilder
    private func programStepsSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot

        if vm.isFrozen, let program = vm.frozenCachedProgram {
            // Frozen mode: show full scrollable program
            let currentIdx = vm.frozenCachedCurrentIndex
            let currentLineColor: Color = snap.prSourceFlag == 8
                ? Color(red: 0.35, green: 0.28, blue: 0.10)  // Yellow for ROM
                : Color(red: 0.10, green: 0.30, blue: 0.10)  // Green for RAM

            SectionBox(title: "PROGRAM STEPS") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(program, id: \.stepNum) { entry in
                                HStack(spacing: 0) {
                                    Text(String(format: "%03d", entry.stepNum))
                                        .foregroundStyle(entry.isCurrent ? .white : Color(white: 0.55))
                                    Text("  ")
                                    Text(String(format: "%02d", entry.keycode))
                                        .foregroundStyle(entry.isCurrent ? Color(red: 0.6, green: 1.0, blue: 0.6)
                                                                         : Color(white: 0.45))
                                    Text("  ")
                                    Text(entry.mnemonic)
                                        .foregroundStyle(entry.isCurrent ? .white : Color(white: 0.65))
                                    Spacer()
                                }
                                .font(.system(size: baseFontSize + 2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(entry.isCurrent ? currentLineColor : Color.clear)
                                .id(entry.stepNum)

                                // Show next step underneath current (with PC and mnemonic)
                                if entry.isCurrent && snap.nextStepNum >= 0 {
                                    HStack(spacing: 0) {
                                        Text(String(format: "%03d", snap.nextStepNum))
                                            .foregroundStyle(Color(white: 0.45))
                                        Text("  ")
                                        Text(String(format: "%02d", snap.nextStepKeycode))
                                            .foregroundStyle(Color(white: 0.35))
                                        Text("  ")
                                        Text(snap.nextStepMnemonic.isEmpty ? "?" : snap.nextStepMnemonic)
                                            .foregroundStyle(Color(white: 0.45))
                                        Text("  ← next")
                                            .font(.system(size: baseFontSize, design: .monospaced))
                                            .foregroundStyle(Color.cyan)
                                        Spacer()
                                    }
                                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                                    .background(Color(red: 0.08, green: 0.15, blue: 0.20))
                                }
                            }
                        }
                    }
                    .onChange(of: currentIdx) {
                        if currentIdx >= 0 && currentIdx < program.count {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(program[currentIdx].stepNum, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        if currentIdx >= 0 {
                            proxy.scrollTo(program[currentIdx].stepNum, anchor: .center)
                        }
                    }
                }
                .frame(height: 165, alignment: .top)
            }
        } else {
            // Normal mode: show current step window (±5 around current)
            let currentLineColor: Color = snap.prSourceFlag == 8
                ? Color(red: 0.35, green: 0.28, blue: 0.10)  // Darker yellow for ROM
                : Color(red: 0.10, green: 0.30, blue: 0.10)  // Green for RAM

            SectionBox(title: "PROGRAM STEPS") {
                VStack(alignment: .leading, spacing: 0) {
                    let window = snap.programWindow
                    ForEach(window, id: \.stepNum) { entry in
                        HStack(spacing: 0) {
                            Text(String(format: "%03d", entry.stepNum))
                                .foregroundStyle(entry.isCurrent ? .white : Color(white: 0.55))
                            Text("  ")
                            Text(String(format: "%02d", entry.keycode))
                                .foregroundStyle(entry.isCurrent ? Color(red: 0.6, green: 1.0, blue: 0.6)
                                                                 : Color(white: 0.45))
                            Text("  ")
                            Text(entry.mnemonic)
                                .foregroundStyle(entry.isCurrent ? .white : Color(white: 0.65))
                            if entry.isCurrent {
                                Text("  ← running")
                                    .font(.system(size: baseFontSize, design: .monospaced))
                                    .foregroundStyle(Color.cyan)
                            }
                            Spacer()
                        }
                        .font(.system(size: baseFontSize + 2, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(entry.isCurrent ? currentLineColor : Color.clear)
                    }
                    // Pad with empty rows to maintain fixed height
                    ForEach(0..<max(0, 11 - window.count), id: \.self) { _ in
                        HStack(spacing: 0) {
                            Spacer()
                        }
                        .font(.system(size: baseFontSize + 2, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                    }
                }
                .frame(height: 165, alignment: .top)
            }
        }
    }

    // MARK: - SCOM Fields Section (IO User Flags, Last Key, Angle Mode)

    private func scomFieldsSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "") {
            HStack(spacing: 12) {
                Text("FIX:\(snap.fixIndicator)")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.85))
                if let mode = snap.angleMode {
                    Text(modeStr(mode))
                        .font(.system(size: baseFontSize + 2, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                } else {
                    Text("?")
                        .font(.system(size: baseFontSize + 2, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4))
                }
                Text("Eng")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(snap.engIndicator.isEmpty ? Color(white: 0.4) : Color(white: 0.85))
                Text("2nd")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(snap.secondIndicator.isEmpty ? Color(white: 0.4) : Color(white: 0.85))
                Text("INV")
                    .font(.system(size: baseFontSize + 2, design: .monospaced))
                    .foregroundStyle(snap.invIndicator.isEmpty ? Color(white: 0.4) : Color(white: 0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Hierarchy & Stack Registers Section

    private func hirRegistersSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "HIR") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 12) {
                    hirRow("1", snap.hir1, baseFontSize: baseFontSize)
                    hirRow("2", snap.hir2, baseFontSize: baseFontSize)
                    hirRow("3", snap.hir3, baseFontSize: baseFontSize)
                    hirRow("4", snap.hir4, baseFontSize: baseFontSize)
                }
                HStack(spacing: 12) {
                    hirRow("5", snap.hir5, baseFontSize: baseFontSize)
                    hirRow("6", snap.hir6, baseFontSize: baseFontSize)
                    hirRow("7", snap.hir7, baseFontSize: baseFontSize)
                    hirRow("8", snap.hir8, baseFontSize: baseFontSize)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - T Register Section

    private func tRegisterSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        let isZero = snap.tRegister == 0
        let color = isZero ? Color(white: 0.5) : Color(white: 0.85)
        return SectionBox(title: "") {
            Text(String(format: "T: %.10g", snap.tRegister))
                .font(.system(size: baseFontSize + 2, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func hirRow(_ label: String, _ value: Double, baseFontSize: CGFloat) -> some View {
        let isZero = value == 0
        let color = isZero ? Color(white: 0.5) : Color(white: 0.85)
        return Text("HIR \(label): \(String(format: "%.5g", value))")
            .font(.system(size: baseFontSize + 2, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calc Flags Section

    private func calcFlagsSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "FLAGS") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        flagIndicator(num: i, state: snap.calcFlags[i], baseFontSize: baseFontSize)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(5..<10, id: \.self) { i in
                        flagIndicator(num: i, state: snap.calcFlags[i], baseFontSize: baseFontSize)
                    }
                }
            }
            .font(.system(size: baseFontSize + 2, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func flagIndicator(num: Int, state: Bool?, baseFontSize: CGFloat) -> some View {
        let stateStr = state == nil ? "?" : (state! ? "1" : "0")
        let color = state == nil ? Color(white: 0.4) : (state! ? Color(white: 0.85) : Color(white: 0.5))
        return Text(String(format: "F%d:%@", num, stateStr))
            .foregroundStyle(color)
    }

    private func modeStr(_ mode: LiveDebugSnapshot.AngleMode) -> String {
        switch mode {
        case .deg: return "DEG"
        case .rad: return "RAD"
        case .grad: return "GRAD"
        }
    }

    // MARK: - Partition Section

    private func partitionSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        let totalSteps = snap.programRegCount * 8
        let dataRegs = snap.dataRegCount

        // Format partition as (lastStep.lastDataReg)
        let lastStep = totalSteps > 0 ? totalSteps - 1 : 0
        let partitionStr: String
        if dataRegs > 0 {
            let lastDataReg = dataRegs - 1
            partitionStr = "(\(lastStep).\(lastDataReg))"
        } else {
            partitionStr = "(\(lastStep).)"
        }

        return SectionBox(title: "PARTITION") {
            Text("Steps: \(totalSteps), Registers: \(dataRegs) \(partitionStr)")
                .font(.system(size: baseFontSize + 2, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Program Source Flag Section

    private func prSourceFlagSection(baseFontSize: CGFloat) -> some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "") {
            Text(String(format: "Prg Source: %X", snap.prSourceFlag))
                .font(.system(size: baseFontSize + 2, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

}

// MARK: - Section Container

private struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
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
}

#Preview {
    LiveDebugView()
        .environment({
            let vm = EmulatorViewModel()
            var snap = LiveDebugSnapshot()
            snap.nonZeroRegs = [
                .init(num: 5, value: 3.141592653589),
                .init(num: 9, value: 2.718281828),
            ]
            snap.programWindow = [
                .init(stepNum: 38, keycode: 41, mnemonic: "STO", isCurrent: false),
                .init(stepNum: 39, keycode: 5, mnemonic: "5", isCurrent: false),
                .init(stepNum: 40, keycode: 41, mnemonic: "STO", isCurrent: false),
                .init(stepNum: 41, keycode: 0, mnemonic: "0", isCurrent: false),
                .init(stepNum: 42, keycode: 60, mnemonic: "LBL", isCurrent: false),
                .init(stepNum: 43, keycode: 1, mnemonic: "1", isCurrent: true),
                .init(stepNum: 44, keycode: 42, mnemonic: "RCL", isCurrent: false),
                .init(stepNum: 45, keycode: 5, mnemonic: "5", isCurrent: false),
                .init(stepNum: 46, keycode: 55, mnemonic: "+", isCurrent: false),
                .init(stepNum: 47, keycode: 57, mnemonic: "=", isCurrent: false),
            ]
            snap.hir1 = 3.141592653589
            snap.hir2 = 2.718281828
            snap.hir3 = 1.414213562
            snap.hir4 = 1.732050808
            snap.hir5 = 1.618033989
            snap.hir6 = 0
            snap.hir7 = 0
            snap.hir8 = 0
            snap.tRegister = 2.71828
            snap.prSourceFlag = 0xA
            snap.pendingOpsCount = 2
            snap.angleMode = .deg
            snap.dataRegCount = 60
            snap.programRegCount = 60
            snap.calcFlags = [false, true, nil, false, true, nil, false, nil, true, nil]
            snap.fixIndicator = "-"
            snap.fA = 0x0340
            snap.fB = 0x08E0
            snap.engIndicator = "Eng"
            snap.secondIndicator = "2nd"
            snap.invIndicator = "INV"
            snap.ioUserFlags = "12345"
            snap.lastKey = "67"
            snap.printerSCOM = ["0000000000000000", "0000000000000000", "0000000000000000", "0000000000000000"]
            snap.scomRows = Array(repeating: "0123456789abcdef", count: 16)
            vm.liveDebugSnapshot = snap
            return vm
        }())
        .frame(width: 300, height: 600)
        .background(Color(white: 0.15))
}
