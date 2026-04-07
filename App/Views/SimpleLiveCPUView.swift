import SwiftUI

/// Simple, high-speed CPU display while emulation is running.
/// Shows current instruction and basic status, doesn't need to be pretty.
struct SimpleLiveCPUView: View {
    @Environment(EmulatorViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            // Current instruction
            HStack(spacing: 8) {
                Text(String(format: "PC: 0x%04X", vm.cpuDebugSnapshot.currentPC))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                if let lastInstr = vm.cpuDebugSnapshot.recentInstructions.last {
                    Text(String(format: "%04X", lastInstr.opcode))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(lastInstr.disasm)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.13))

            // Instructions trace (compact list)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.cpuDebugSnapshot.recentInstructions, id: \.pc) { instr in
                        let isCurrent = (instr.pc == vm.cpuDebugSnapshot.currentPC)
                        HStack(spacing: 6) {
                            Text(String(format: "0x%04X", instr.pc))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 50, alignment: .leading)

                            Text(instr.disasm)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isCurrent ? Color.green.opacity(0.15) : Color.clear)
                    }
                }
            }

            Spacer()
        }
        .background(Color(white: 0.10))
        .onAppear {
            vm.cpuDebugEnabled = true
        }
        .onDisappear {
            vm.cpuDebugEnabled = false
        }
    }
}
