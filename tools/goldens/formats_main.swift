// Golden generator: dumps the Swift originals of the state-file parser,
// card-file parser, cue-card model, register-line helpers and BCD encoders
// so the C++ ports in Shared/ can be checked against them.
// Arguments: state files and card files to parse. See tools/goldens/README.md.
import Foundation

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%X", $0) }.joined() }
func num(_ d: Double) -> String { String(format: "%.17g", d) }

func dumpCue(_ c: CueCardContent, _ out: inout String) {
    out += "cue template \(c.template.rawValue)\n"
    out += "cue title \(c.title)\n"
    out += "cue banks \(c.banks.0.map(String.init) ?? "-") \(c.banks.1.map(String.init) ?? "-")\n"
    out += "cue id \(c.id)\n"
    for (i, l) in c.labels.enumerated() { out += "cue label\(i) \(l)\n" }
    out += "cue row1 \(c.row1)\ncue row1Align \(c.row1Align.rawValue)\n"
    out += "cue row2 \(c.row2)\ncue row2Align \(c.row2Align.rawValue)\n"
    out += "cue row2R \(c.row2R)\ncue row2RAlign \(c.row2RAlign.rawValue)\n"
    out += "cue style \(c.style.rawValue)\ncue color \(c.color.rawValue)\n"
    for line in c.encodeToLines(writeTemplate: .magnetCard) { out += "enc \(line)\n" }
    for line in c.encodeToLines() { out += "enc0 \(line)\n" }
}

var out = ""
for path in CommandLine.arguments.dropFirst() {
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    let rel = path.components(separatedBy: "/Calc-U-59/").last!
    if path.hasSuffix(".u59") {
        out += "CARD \(rel)\n"
        if let r = parseCardFile(text) {
            out += "data \(hex(Array(r.data)))\n"
            if let c = r.cueCard { dumpCue(c, &out) }
        } else {
            out += "nil\n"
        }
        out += "END\n"
        continue
    }
    for (maxStep, hidden) in [(479, false), (959, false), (479, true)] {
        out += "STATE \(rel) \(maxStep) \(hidden ? 1 : 0)\n"
        let r = parseStateFile(text, maxStepAddr: maxStep, allowHiddenRegisters: hidden)
        out += "partition \(r.partitionMaxStep) \(r.partitionWasExplicit ? 1 : 0)\n"
        for s in r.programSteps { out += "step \(s.stepAddr) \(s.keycode)\n" }
        for g in r.registers { out += "reg \(g.regNum) \(g.isHidden ? 1 : 0) \(hex(g.nibbles))\n" }
        for k in r.keystrokes {
            switch k {
            case .key(let c): out += "key \(c)\n"
            case .toggleTrace: out += "toggleTrace\n"
            case .wait(let t): out += "wait \(num(t))\n"
            case .waitFullSpeed(let t): out += "waitFullSpeed \(num(t))\n"
            case .trace(let n): out += "trace \(n ?? "-")\n"
            case .fullSpeed: out += "fullSpeed\n"
            case .regularSpeed: out += "regularSpeed\n"
            case .zeroElapseTime: out += "zeroElapseTime\n"
            case .reportElapseTime: out += "reportElapseTime\n"
            }
        }
        if let c = r.cueCardContent { dumpCue(c, &out) }
        out += "module \(r.solidStateModuleID ?? "-")\n"
        out += "printer \(r.printerConnected.map { $0 ? "1" : "0" } ?? "-")\n"
        out += "model \(r.model?.displayName ?? "-")\n"
        for e in r.errors { out += "error \(e)\n" }
        out += "END\n"
    }
}

// BCD encoders over literals (text path) and doubles (Double path).
let literals = ["0", "-0", "00", "1", "-1", "7", "10", "99", "100", "3641003032", "1234567890123", "12345678901234567",
                "-98765", "0.5", "-1.5e-3", "7.77E22", "1e-99", "9.999999999999e99", "1e100", "1e-100", "3.14159265358979",
                "2.5", "  42  ", "+5", "1.", ".5", "inf", "-inf", "nan", "abc", "", "1e5", "-0.0", "0001", "1E+05",
                "123456789012.5", "0.1", "0.3", "1.0000000000005", "9.9999999999995e8", "5e-324", "1.7976931348623157e308"]
for l in literals { out += "BCDT [\(l)] \(hex(encodeTI59BCD(text: l)))\n" }
var seed: UInt64 = 0x59
func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 11 }
for _ in 0..<300 {
    let mant = Double(next() % 10_000_000_000_000) / 1e12
    let exp = Int(next() % 199) - 99
    let v = (next() % 2 == 0 ? -1.0 : 1.0) * mant * pow(10.0, Double(exp))
    out += "BCDD \(num(v)) \(hex(encodeTI59BCD(v)))\n"
}

// Register-line helpers.
for _ in 0..<50 {
    let nib = (0..<16).map { _ in UInt8(next() % 16) }
    let enc = encodeRegisterLine(nib)
    out += "REG \(hex(nib)) \(enc.map { String(format: "%02X", $0) }.joined()) \(hex(decodeRegisterLine(enc)))\n"
}

// Math tokens.
for s in ["\\lambda\\Lambda", "^{-1}^{1}^{-}", "_{-1}_{1}", "\\leftrightarrows\\leftrightarrow\\leftarrow",
          "x^{2}+y_{i}", "\\blank", "\\pibar", "\\sqrt\\cbrt", "plain"] {
    out += "MATH \(s) \(expandMathTokens(s))\n"
}

FileHandle.standardOutput.write(out.data(using: .utf8)!)
