// Golden generator: dumps TI59KeyNames (the Swift original) so the C++ port
// in Shared/KeyNames.cpp can be checked against it. See tools/goldens/README.md.
import Foundation

var out = ""
for kc in 0...105 {
    out += "M \(kc) \(TI59KeyNames.mnemonic(for: UInt8(kc))) \(TI59KeyNames.stepsAfter(for: UInt8(kc)))\n"
}
// argumentSteps over deterministic pseudo-random programs biased toward
// branch/operand opcodes, plus all-keycode sweeps.
var seed: UInt64 = 0x59
func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
let hot: [UInt8] = [61, 67, 71, 77, 87, 97, 22, 27, 40, 42, 43, 69, 58, 0, 1, 9, 36, 83, 86, 76]
for _ in 0..<400 {
    let n = Int(next() % 40) + 1
    var steps = [UInt8]()
    for _ in 0..<n { steps.append(next() % 3 == 0 ? UInt8(next() % 100) : hot[Int(next() % UInt64(hot.count))]) }
    let args = TI59KeyNames.argumentSteps(in: steps).sorted()
    out += "A " + steps.map(String.init).joined(separator: " ") + " | " + args.map(String.init).joined(separator: " ") + "\n"
}
FileHandle.standardOutput.write(out.data(using: .utf8)!)
