import SwiftUI

struct CPUDebugView: View {
    @Environment(EmulatorViewModel.self) var vm
    @State private var breakpointHexInput: String = ""
    @State private var selectedInstructionIndex: Int? = nil
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            controlBar

            // Content sections
            ScrollView {
                VStack(spacing: 1) {
                    breakpointsSection
                    romTraceSection
                    registersSection
                    controlRegistersSection
                    scomSection
                }
            }
        }
        .background(Color(white: 0.10))
        .focusable()
        .focused($isFocused)
        .onChange(of: vm.isFrozen) { oldValue, newValue in
            // When freeze is pressed, select the most recent instruction and focus for keyboard input
            if newValue && !oldValue {
                selectedInstructionIndex = vm.cpuDebugSnapshot.recentInstructions.count - 1
                isFocused = true
            }
        }
        .onKeyPress(.upArrow) {
            // Navigate up through instruction history
            guard vm.isFrozen else { return .ignored }
            if selectedInstructionIndex == nil {
                // Start from the most recent (bottom)
                selectedInstructionIndex = vm.cpuDebugSnapshot.recentInstructions.count - 1
            } else if let idx = selectedInstructionIndex, idx > 0 {
                selectedInstructionIndex = idx - 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            // Navigate down through instruction history
            guard vm.isFrozen else { return .ignored }
            if let idx = selectedInstructionIndex {
                if idx < vm.cpuDebugSnapshot.recentInstructions.count - 1 {
                    selectedInstructionIndex = idx + 1
                } else {
                    // Clear selection to show current
                    selectedInstructionIndex = nil
                }
            }
            return .handled
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Freeze/Resume button
            Button(action: {
                if vm.isFrozen {
                    vm.unfreeze()
                } else {
                    vm.freeze(reason: .manual)
                    // Explicitly select current instruction and request focus
                    selectedInstructionIndex = vm.cpuDebugSnapshot.recentInstructions.count - 1
                    isFocused = true
                }
            }) {
                Text(vm.isFrozen ? "RESUME" : "FREEZE")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(vm.isFrozen ? Color.orange : Color(white: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Step button (enabled only when frozen)
            Button(action: vm.singleStep) {
                Text("STEP")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(vm.isFrozen ? Color(white: 0.25) : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(!vm.isFrozen)

            // Status indicator
            if vm.isFrozen {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    if let pc = vm.cpuDebugSnapshot.pausedPC {
                        Text(String(format: "PAUSED AT 0x%04X", pc))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("RUNNING")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }

    // MARK: - Breakpoints Section

    private var breakpointsSection: some View {
        SectionBox(title: "BREAKPOINTS") {
            VStack(alignment: .leading, spacing: 8) {
                // Input field + ADD button
                HStack(spacing: 6) {
                    TextField("ROM addr (hex)", text: $breakpointHexInput)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    Button("ADD") {
                        if let pc = UInt16(breakpointHexInput, radix: 16) {
                            vm.addBreakpoint(pc)
                            breakpointHexInput = ""
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Active breakpoints list
                if vm.breakpoints.isEmpty {
                    Text("No breakpoints")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    HStack(spacing: 6) {
                        ForEach(vm.breakpoints.sorted(), id: \.self) { bp in
                            HStack(spacing: 4) {
                                Text(String(format: "0x%04X", bp))
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)

                                Button("×") {
                                    vm.removeBreakpoint(bp)
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.6))
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(white: 0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - ROM Trace Section

    private var romTraceSection: some View {
        SectionBox(title: "ROM TRACE") {
            if vm.cpuDebugSnapshot.recentInstructions.isEmpty {
                Text("(no instructions yet)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
            } else {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.cpuDebugSnapshot.recentInstructions.indices, id: \.self) { i in
                            let instr = vm.cpuDebugSnapshot.recentInstructions[i]
                            let isCurrent = (instr.pc == vm.cpuDebugSnapshot.currentPC)
                            let isSelected = (selectedInstructionIndex == i)

                            HStack(spacing: 8) {
                                Text(String(format: "0x%04X", instr.pc))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 50, alignment: .leading)

                                Text(String(format: "%04X", instr.opcode))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 50, alignment: .leading)

                                Text(instr.disasm)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isCurrent ? Color.green.opacity(0.2) : (isSelected ? Color(white: 0.20) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedInstructionIndex = (isSelected ? nil : i)
                            }
                            .id(i)
                        }
                    }
                    .onChange(of: vm.cpuDebugSnapshot.recentInstructions.count) {
                        // Auto-scroll to bottom (newest instruction)
                        if !vm.cpuDebugSnapshot.recentInstructions.isEmpty {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(vm.cpuDebugSnapshot.recentInstructions.count - 1, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: selectedInstructionIndex) {
                        // Scroll to selected instruction when navigating with arrow keys
                        if let idx = selectedInstructionIndex {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(idx, anchor: .top)
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }

    // MARK: - Registers Section

    private var registersSection: some View {
        SectionBox(title: "REGISTERS") {
            let frame = selectedInstructionIndex.flatMap { idx in
                guard idx >= 0 && idx < vm.cpuDebugSnapshot.recentInstructions.count else { return nil }
                return vm.cpuDebugSnapshot.recentInstructions[idx].frame
            } ?? vm.cpuDebugSnapshot.recentInstructions.last?.frame ?? TICpuFrame()

            let cpu = frame

            VStack(alignment: .leading, spacing: 6) {
                registerRow("A", cpu.A)
                registerRow("B", cpu.B)
                registerRow("C", cpu.C)
                registerRow("D", cpu.D)
                registerRow("E", cpu.E)
                registerRow("Sout", cpu.Sout)
            }
            .padding(8)
        }
    }

    private func registerRow(_ label: String, _ nibbles: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) -> some View {
        let array = [nibbles.0, nibbles.1, nibbles.2, nibbles.3, nibbles.4, nibbles.5, nibbles.6, nibbles.7,
                     nibbles.8, nibbles.9, nibbles.10, nibbles.11, nibbles.12, nibbles.13, nibbles.14, nibbles.15]
        return HStack(spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(Array(array.enumerated()), id: \.offset) { offset, n in
                    Text(String(format: "%X", n))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer()
        }
    }

    // MARK: - Control Registers Section

    private var controlRegistersSection: some View {
        SectionBox(title: "CONTROL REGISTERS") {
            let frame = selectedInstructionIndex.flatMap { idx in
                guard idx >= 0 && idx < vm.cpuDebugSnapshot.recentInstructions.count else { return nil }
                return vm.cpuDebugSnapshot.recentInstructions[idx].frame
            } ?? vm.cpuDebugSnapshot.recentInstructions.last?.frame ?? TICpuFrame()

            let cpu = frame

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    controlRegPair("KR", String(format: "0x%04X", cpu.KR))
                    controlRegPair("SR", String(format: "0x%04X", cpu.SR))
                }
                HStack {
                    controlRegPair("fA", String(format: "0x%04X", cpu.fA))
                    controlRegPair("fB", String(format: "0x%04X", cpu.fB))
                }
                HStack {
                    controlRegPair("R5", String(format: "0x%X", cpu.R5))
                    controlRegPair("digit", String(format: "0x%X", cpu.digit))
                }
                HStack {
                    controlRegPair("flags", String(format: "0x%04X", cpu.flags))
                    Spacer()
                }
                HStack {
                    controlRegPair("RAM_ADDR", String(format: "%02d", cpu.RAM_ADDR))
                    controlRegPair("RAM_OP", String(format: "%d", cpu.RAM_OP))
                    controlRegPair("REG_ADDR", String(format: "%02d", cpu.REG_ADDR))
                }
            }
            .padding(8)
        }
    }

    private func controlRegPair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()
        }
    }

    // MARK: - SCOM Section

    private var scomSection: some View {
        SectionBox(title: "SCOM") {
            let frame = selectedInstructionIndex.flatMap { idx in
                guard idx >= 0 && idx < vm.cpuDebugSnapshot.recentInstructions.count else { return nil }
                return vm.cpuDebugSnapshot.recentInstructions[idx].frame
            } ?? vm.cpuDebugSnapshot.recentInstructions.last?.frame ?? TICpuFrame()

            let cpu = frame

            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<16, id: \.self) { row in
                    let nibbles = withUnsafeBytes(of: cpu.SCOM) { bytes -> [UInt8] in
                        var arr: [UInt8] = []
                        for col in 0..<16 {
                            arr.append(bytes[row * 16 + col])
                        }
                        return arr
                    }

                    HStack(spacing: 2) {
                        Text(String(format: "S%02d", row))
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30, alignment: .leading)

                        HStack(spacing: 0) {
                            ForEach(Array(nibbles.enumerated()), id: \.offset) { col, n in
                                Text(String(format: "%X", n))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(8)
        }
    }
}

// MARK: - SectionBox Helper (reused from LiveDebugView)

private struct SectionBox<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.07))

            content
                .background(Color(white: 0.13))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(white: 0.25), lineWidth: 0.5)
        )
    }
}

#Preview {
    CPUDebugView()
        .environment(EmulatorViewModel())
}
