import SwiftUI

struct LiveDebugView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var scomExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            liveHeader
            ScrollView {
                VStack(spacing: 1) {
                    dataRegistersSection
                    programStepsSection
                    hirRegistersSection
                    calcFlagsSection
                    partitionSection
                    printerSCOMSection
                    scomSection
                }
                .padding(4)
            }
            .background(Color(white: 0.10))
        }
        .background(Color(white: 0.10))
    }

    // MARK: - Header

    private var liveHeader: some View {
        HStack {
            Text("LIVE DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
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

    // MARK: - Data Registers Section

    private var dataRegistersSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "DATA REGISTERS") {
            if snap.nonZeroRegs.isEmpty {
                Text("(all zero)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(snap.nonZeroRegs, id: \.num) { entry in
                        Text(String(format: "R%02d = %.10g", entry.num, entry.value))
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
        SectionBox(title: "PROGRAM STEPS") {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(vm.liveDebugSnapshot.programWindow, id: \.stepNum) { entry in
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
                    .background(entry.isCurrent
                        ? Color(red: 0.10, green: 0.30, blue: 0.10)
                        : Color.clear)
                }
            }
        }
    }

    // MARK: - Hierarchy & Stack Registers Section

    private var hirRegistersSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "HIERARCHY REGISTERS (SCOM 1–8)") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        hirRow("HIR 1", snap.hir1)
                        hirRow("HIR 2", snap.hir2)
                        hirRow("HIR 3", snap.hir3)
                        hirRow("HIR 4", snap.hir4)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        hirRow("HIR 5", snap.hir5)
                        hirRow("HIR 6", snap.hir6)
                        hirRow("HIR 7", snap.hir7)
                        hirRow("HIR 8", snap.hir8)
                    }
                }
                Divider()
                    .background(Color(white: 0.25))
                    .padding(.vertical, 2)
                HStack(spacing: 4) {
                    Text("T (SCOM 11)")
                        .foregroundStyle(Color(white: 0.5))
                        .frame(width: 40, alignment: .leading)
                    Text(String(format: "%.10g", snap.tRegister))
                        .foregroundStyle(Color(white: 0.85))
                }
                .font(.system(size: 11, design: .monospaced))
                Divider()
                    .background(Color(white: 0.25))
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        Text("Pending ops:")
                            .foregroundStyle(Color(white: 0.5))
                        Text(String(snap.pendingOpsCount))
                            .foregroundStyle(Color(white: 0.85))
                        Spacer()
                        if let mode = snap.angleMode {
                            Text("Mode: " + modeStr(mode))
                                .foregroundStyle(Color(white: 0.85))
                        } else {
                            Text("Mode: ?")
                                .foregroundStyle(Color(white: 0.4))
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                Divider()
                    .background(Color(white: 0.25))
                    .padding(.vertical, 2)
                Text("AOS pending operations & stack top (SCOM 1–8, 11, 13)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func hirRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Color(white: 0.5))
                .frame(width: 28, alignment: .leading)
            Text(String(format: "%.10g", value))
                .foregroundStyle(Color(white: 0.85))
        }
        .font(.system(size: 11, design: .monospaced))
    }

    // MARK: - Calc Flags Section

    private var calcFlagsSection: some View {
        let snap = vm.liveDebugSnapshot
        return SectionBox(title: "CALC FLAGS (0–9)") {
            VStack(alignment: .leading, spacing: 3) {
                // Flags arranged in 2 rows of 5
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
                Divider()
                    .background(Color(white: 0.25))
                // Status fields (TBD)
                HStack(spacing: 12) {
                    statusIndicator("INV", snap.isINV)
                    statusIndicator("2nd", snap.is2nd)
                    if let mode = snap.angleMode {
                        Text("Angle: " + modeStr(mode))
                            .foregroundStyle(Color(white: 0.65))
                    } else {
                        Text("Angle: ?")
                            .foregroundStyle(Color(white: 0.4))
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
        return SectionBox(title: "PARTITION") {
            HStack(spacing: 16) {
                Text("Prog: \(snap.programRegCount)")
                Text("Data: \(snap.dataRegCount)")
                Text("Steps: \(snap.programRegCount * 8)")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(white: 0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Printer SCOM Section

    private var printerSCOMSection: some View {
        SectionBox(title: "PRINTER SCOM (rows 0–3)") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(vm.liveDebugSnapshot.printerSCOM.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 4) {
                        Text("S\(String(format: "%02d", i))")
                            .foregroundStyle(Color(white: 0.5))
                        Text(row)
                            .foregroundStyle(Color(white: 0.85))
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - SCOM Section (Collapsible)

    private var scomSection: some View {
        DisclosureGroup(isExpanded: $scomExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(vm.liveDebugSnapshot.scomRows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 4) {
                        Text("S\(String(format: "%02d", i))")
                            .foregroundStyle(Color(white: 0.5))
                        Text(row)
                            .foregroundStyle(Color(white: 0.85))
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        } label: {
            Text("SCOM (all 16 rows)")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .background(Color(white: 0.07))
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
