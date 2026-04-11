import SwiftUI

struct LiveDebugView: View {
    @Environment(EmulatorViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            liveHeader
            ScrollView {
                VStack(spacing: 1) {
                    partitionSection
                    prSourceFlagSection
                    programStepsSection
                    statusIndicatorsSection
                    returnAddressSection
                    calcFlagsSection
                    hirRegistersSection
                    tRegisterSection
                    dataRegistersSection
                }
                .padding(4)
            }
            .background(Color(white: 0.10))
        }
        .background(Color(white: 0.10))
        .onKeyPress(.space) {
            // Space: step when frozen
            if vm.isFrozen {
                vm.stepKeycode()
            }
            return .handled
        }
        .onKeyPress("f") {
            // F: toggle freeze/resume
            if vm.isFrozen {
                vm.unfreeze()
            } else {
                vm.freeze()
            }
            return .handled
        }
    }

    // MARK: - Header

    private var liveHeader: some View {
        HStack {
            Text("LIVE DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if vm.isFrozen {
                Button("STEP") { vm.stepKeycode() }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan)
            }
            Button(vm.isFrozen ? "RESUME" : "FREEZE") {
                vm.isFrozen ? vm.unfreeze() : vm.freeze()
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(vm.isFrozen ? Color.orange : Color(white: 0.6))
            Circle()
                .fill(vm.liveDebugEnabled ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Toggle("", isOn: Binding(
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

    // MARK: - Return Address Section

    private var returnAddressSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "RETURN ADDRESS") {
            Text(snap.returnAddress)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .lineLimit(2)
        }
    }

    // MARK: - Data Registers Section (Variables)

    private var dataRegistersSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "VARIABLES") {
            if snap.nonZeroRegs.isEmpty {
                Text("(all zero)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(snap.nonZeroRegs.enumerated()), id: \.offset) { _, entry in
                        let label = entry.isHidden ? String(format: "H%02d", entry.num) : String(format: "R%02d", entry.num)
                        Text(String(format: "%@ = %.10g", label, entry.value))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.85))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Program Steps Section

    private var programStepsSection: some View {
        let snap = vm.liveDebugSnapshot
        // Determine current line color based on PRG SOURCE
        let currentLineColor: Color = snap.prSourceFlag == 8
            ? Color(red: 0.35, green: 0.28, blue: 0.10)  // Darker yellow for ROM
            : Color(red: 0.10, green: 0.30, blue: 0.10)  // Green for RAM

        return SectionBox(title: "PROGRAM STEPS") {
            VStack(alignment: .leading, spacing: 0) {
                let window = snap.programWindow
                ForEach(0..<11, id: \.self) { i in
                    if i < window.count {
                        let entry = window[i]
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
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(entry.isCurrent ? currentLineColor : Color.clear)
                    } else {
                        HStack(spacing: 0) {
                            Spacer()
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                    }
                }
            }
            .frame(height: 165)
        }
    }

    // MARK: - Status Indicators Section (INV, 2nd, Angle Mode)

    private var statusIndicatorsSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "") {
            HStack(spacing: 12) {
                statusIndicator("INV", snap.isINV)
                statusIndicator("2nd", snap.is2nd)
                if let mode = snap.angleMode {
                    Text(modeStr(mode))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.85))
                } else {
                    Text("?")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Hierarchy & Stack Registers Section

    private var hirRegistersSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "HIR") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 12) {
                    hirRow("1", snap.hir1)
                    hirRow("2", snap.hir2)
                    hirRow("3", snap.hir3)
                    hirRow("4", snap.hir4)
                }
                HStack(spacing: 12) {
                    hirRow("5", snap.hir5)
                    hirRow("6", snap.hir6)
                    hirRow("7", snap.hir7)
                    hirRow("8", snap.hir8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - T Register Section

    private var tRegisterSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "") {
            Text(String(format: "T: %.10g", snap.tRegister))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    private func hirRow(_ label: String, _ value: Double) -> some View {
        Text("HIR \(label): \(String(format: "%.5g", value))")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(white: 0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calc Flags Section

    private var calcFlagsSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "FLAGS") {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        flagIndicator(num: i, state: snap.calcFlags[i])
                    }
                }
                HStack(spacing: 8) {
                    ForEach(5..<10, id: \.self) { i in
                        flagIndicator(num: i, state: snap.calcFlags[i])
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func flagIndicator(num: Int, state: Bool?) -> some View {
        let stateStr = state == nil ? "?" : (state! ? "1" : "0")
        let color = state == nil ? Color(white: 0.4) : (state! ? Color(white: 0.85) : Color(white: 0.5))
        return Text(String(format: "F%d:%@", num, stateStr))
            .foregroundStyle(color)
    }

    private func statusIndicator(_ label: String, _ state: Bool?) -> some View {
        let stateStr = state == nil ? "?" : (state! ? "●" : "○")
        let color = state == nil ? Color(white: 0.4) : (state! ? .white : Color(white: 0.5))
        return Text("\(label):\(stateStr)")
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

    private var partitionSection: some View {
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
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Program Source Flag Section

    private var prSourceFlagSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "") {
            Text(String(format: "Prg Source: %X", snap.prSourceFlag))
                .font(.system(size: 11, design: .monospaced))
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
            snap.isINV = nil
            snap.is2nd = false
            snap.printerSCOM = ["0000000000000000", "0000000000000000", "0000000000000000", "0000000000000000"]
            snap.scomRows = Array(repeating: "0123456789abcdef", count: 16)
            vm.liveDebugSnapshot = snap
            return vm
        }())
        .frame(width: 300, height: 600)
        .background(Color(white: 0.15))
}
