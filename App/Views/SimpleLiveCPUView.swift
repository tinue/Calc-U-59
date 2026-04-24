import SwiftUI

/// Simple, high-speed CPU display while emulation is running.
/// Shows current instruction and basic status, doesn't need to be pretty.
struct SimpleLiveCPUView: View {
    @Environment(EmulatorViewModel.self) var vm

    var body: some View {
        GeometryReader { geo in
            let baseFontSize = adaptiveFontSize(width: geo.size.width)

            VStack(spacing: 0) {
                // Control bar
                HStack(spacing: 12) {
                    Button(action: { vm.freeze(reason: .manual, waitForKeycode: false) }) {
                        Text("FREEZE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(white: 0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Text("RUNNING")
                        .font(.caption.bold())
                        .foregroundStyle(.green)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(white: 0.07))

                // Current instruction
                HStack(spacing: 8) {
                    Text(String(format: "PC: 0x%04X", vm.cpuDebugSnapshot.currentPC))
                        .font(.system(size: baseFontSize + 2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))

                    if let lastInstr = vm.cpuDebugSnapshot.recentInstructions.last {
                        Text(String(format: "%04X", lastInstr.opcode))
                            .font(.system(size: baseFontSize + 2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))

                        Text(lastInstr.disasm)
                            .font(.system(size: baseFontSize + 2, design: .monospaced))
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
                        ForEach(Array(vm.cpuDebugSnapshot.recentInstructions.enumerated()), id: \.offset) { _, instr in
                            let isCurrent = (instr.pc == vm.cpuDebugSnapshot.currentPC)
                            HStack(spacing: 6) {
                                Text(String(format: "0x%04X", instr.pc))
                                    .foregroundStyle(.white.opacity(0.8))

                                Text(instr.disasm)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .font(.system(size: baseFontSize + 2, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isCurrent ? Color.green.opacity(0.15) : Color.clear)
                        }
                    }
                }

                Spacer()
            }
            .textSelection(.enabled)
            .background(Color(white: 0.10))
        }
    }

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
