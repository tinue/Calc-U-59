import Foundation

// ── .ti59 state file format ───────────────────────────────────────────────────
//
// A plain UTF-8 text file understood by parseStateFile(_:).  Four optional
// sections, introduced by their keyword followed by a colon:
//
//   PARTITION: nnn[.xx]
//       Sets the program/data split.  nnn is the last visible step number
//       (display shows nnn, total steps = nnn + 1).  The .xx suffix (register
//       count) is accepted for documentation purposes but ignored by the parser.
//       Total steps must be a multiple of 80; valid range 80–960.
//       Default if omitted: 479 (480 steps, 60 program-RAM registers).
//
//   PROGRAM:
//       One or more lines of keycodes.  Three formats are accepted and may be
//       mixed freely within the same file:
//
//         Format 1 — bare keycodes:        76 11 42 00
//         Format 2 — step-number prefix:   002  42 00
//         Format 3 — printer listing:      002  STO  00
//
//       A 3-or-more-digit number at the start of a line sets the current step
//       address (sparse loading: unlisted steps default to 00).  Without a
//       prefix, keycodes continue from the previous step.  Mnemonic text is
//       silently ignored; only numeric tokens 0–99 are treated as keycodes.
//
//       A line containing only "..." is a gap marker: it is ignored by the
//       parser (steps in the gap remain 00) but documents that a section of
//       zeros has been intentionally omitted.
//
//   REGISTERS:
//       Lines of the form "NN = value", where NN is 00–99 and value is any
//       floating-point literal accepted by Swift's Double initialiser.
//
//   KEYSTROKES:
//       Keystrokes to inject after the program and registers have been loaded,
//       simulating physical key presses on the hardware matrix.
//
//       Matrix codes use the same numeric format as PROGRAM lines, but no
//       step-number prefix is supported.  Mnemonic labels are silently ignored.
//       Each line's codes are pressed one at a time with a default 0.5 s gap
//       between presses.
//
//       An explicit wait between lines is specified with:
//           Wait: 2s        (seconds)
//           Wait: 500ms     (milliseconds)
//       The wait is applied after the preceding line completes, before the
//       next line starts.
//
//       Matrix code format: row*10 + col, row 1–9 (top–bottom), col 1–5 (left–right).
//       Valid matrix codes: 11–95.  Example:
//           21 84 65 83 95   # [2nd][π] × 2 =  → display should show 6.283185307
//           Wait: 1s
//           42 00            # STO 00
//
// Lines beginning with # (after optional leading whitespace) are comments.
// Inline comments after # are also stripped.  All section keywords are
// case-insensitive.

// MARK: - Result types

/// A single event in the KEYSTROKES section.
enum KeystrokeEvent {
    case key(UInt8)          // matrix code to press (row*10 + col, row 1–9, col 1–5)
    case wait(TimeInterval)  // explicit pause before the next keystroke line
}

struct LoadStateResult {
    var partitionMaxStep: Int = 479
    /// True when the file contained an explicit PARTITION: line; false = default was used.
    var partitionWasExplicit: Bool = false
    /// Sparse list of (stepAddress, keycode) pairs. Steps not listed default to 0x00.
    var programSteps: [(stepAddr: Int, keycode: UInt8)] = []
    var registers: [(regNum: Int, nibbles: [UInt8])] = []
    var keystrokes: [KeystrokeEvent] = []
    var errors: [String] = []
}

// MARK: - Parser

private enum ParseSection { case none, partition, program, registers, keystrokes }

func parseStateFile(_ text: String) -> LoadStateResult {
    var result = LoadStateResult()
    var section: ParseSection = .none
    var currentStep = 0

    for rawLine in text.components(separatedBy: .newlines) {
        // Strip inline comment, then trim
        let line = rawLine.components(separatedBy: "#").first!
            .trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }

        let upper = line.uppercased()

        // Section header: PARTITION:
        if upper.hasPrefix("PARTITION:") {
            section = .partition
            let rest = String(line.dropFirst("PARTITION:".count))
                .trimmingCharacters(in: .whitespaces)
            // Take the part before the dot (or whole token if no dot)
            let numStr = rest.components(separatedBy: ".").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if let n = Int(numStr) {
                let partitionSteps = n + 1
                // Round up to nearest valid boundary: multiples of 80, from 80 to 960
                // (each unit of 10 program-RAM regs = 80 steps; max 120 regs = 960 steps)
                let rounded = stride(from: 80, through: 960, by: 80)
                    .first(where: { $0 >= partitionSteps }) ?? 960
                result.partitionMaxStep = rounded - 1
            }
            result.partitionWasExplicit = true
            continue
        }

        // Section header: PROGRAM:
        if upper.hasPrefix("PROGRAM:") {
            section = .program
            continue
        }

        // Section header: REGISTERS:
        if upper.hasPrefix("REGISTERS:") {
            section = .registers
            continue
        }

        // Section header: KEYSTROKES:
        if upper.hasPrefix("KEYSTROKES:") {
            section = .keystrokes
            continue
        }

        // Content lines
        switch section {
        case .none, .partition:
            break
        case .program:
            if line == "..." { break }  // gap marker — steps in between remain 00
            let (maybeStart, codes) = parseProgLine(line)
            if let start = maybeStart { currentStep = start }
            for code in codes {
                result.programSteps.append((stepAddr: currentStep, keycode: code))
                currentStep += 1
            }
        case .registers:
            parseRegLine(line, into: &result.registers, errors: &result.errors)
        case .keystrokes:
            if let t = parseWaitLine(line) {
                result.keystrokes.append(.wait(t))
            } else {
                for code in parseKeystrokeLine(line) {
                    result.keystrokes.append(.key(code))
                }
            }
        }
    }

    return result
}

// MARK: - Line parsers

/// Parse one program line. Returns the step address set by a prefix (if any) and
/// the keycodes found on the line. A 3-or-more-digit token that is a valid step
/// address (0–479) is treated as a position prefix, not a keycode.
private func parseProgLine(_ line: String) -> (stepAddr: Int?, keycodes: [UInt8]) {
    let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    var startStep: Int? = nil
    var keycodes: [UInt8] = []

    for token in tokens {
        if startStep == nil && token.count >= 3, let n = Int(token), n >= 0, n <= 479 {
            startStep = n   // step-address prefix: sets position, not a keycode
            continue
        }
        // 1–2 digit numeric token in 0–99 range is a keycode
        if token.count <= 2, let n = Int(token), n >= 0, n <= 99 {
            keycodes.append(UInt8(n))
        }
    }
    return (startStep, keycodes)
}

private func parseRegLine(_ line: String,
                           into registers: inout [(regNum: Int, nibbles: [UInt8])],
                           errors: inout [String]) {
    // Expected format: "NN = <float>"
    let parts = line.components(separatedBy: "=")
    guard parts.count >= 2 else { return }
    let nnStr  = parts[0].trimmingCharacters(in: .whitespaces)
    let valStr = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
    guard let regNum = Int(nnStr), regNum >= 0, regNum <= 99 else { return }
    guard let value = Double(valStr) else {
        errors.append("Cannot parse register \(nnStr) value: \"\(valStr)\"")
        return
    }
    registers.append((regNum: regNum, nibbles: encodeTI59BCD(value)))
}

/// Parse one KEYSTROKES line: return all 1–2 digit numeric tokens in 11–95.
/// No step-address prefix logic — every valid token is a matrix code.
/// Valid matrix codes: 11–95 (col 1–5). Mnemonic labels and other non-numeric tokens are silently ignored.
private func parseKeystrokeLine(_ line: String) -> [UInt8] {
    let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    var keycodes: [UInt8] = []
    for token in tokens {
        if token.count <= 2, let n = Int(token), n >= 11, n <= 95 {
            keycodes.append(UInt8(n))
        }
    }
    return keycodes
}

/// Parse a "Wait: <value><unit>" line.  Returns the interval in seconds, or nil.
/// Supported units: "s" (seconds), "ms" (milliseconds).  Case-insensitive.
private func parseWaitLine(_ line: String) -> TimeInterval? {
    let upper = line.uppercased()
    guard upper.hasPrefix("WAIT:") else { return nil }
    let rest = String(line.dropFirst("WAIT:".count)).trimmingCharacters(in: .whitespaces)
    if rest.uppercased().hasSuffix("MS"),
       let v = Double(rest.dropLast(2).trimmingCharacters(in: .whitespaces)) {
        return v / 1000.0
    }
    if rest.uppercased().hasSuffix("S"),
       let v = Double(rest.dropLast(1).trimmingCharacters(in: .whitespaces)) {
        return v
    }
    return nil
}

// MARK: - BCD encoder

/// Encode a Double as TI-59 BCD: 16 nibbles.
///
/// Register layout (matches the TMC0598 RAM serial-BCD convention):
///   nibble[0]     = sign flags: bit 1 = mantissa negative, bit 2 = exponent negative (values: 0/2/4/6)
///   nibble[1]     = exponent LSD (decimal units digit)
///   nibble[2]     = exponent MSD (decimal tens digit)
///   nibble[3]     = mantissa LSD (least significant digit)
///   nibble[15]    = mantissa MSD (most significant digit)
///
/// Exponent encoding (10's complement for negatives):
///   exp ≥ 0  → stored = exp          (0–49, direct)
///   exp < 0  → stored = 100 + exp    (e.g. exp=-1 → stored=99, exp=-50 → stored=50)
///
/// Mantissa is normalised so the first digit is non-zero (1.xxxxxxxxxx × 10^exp).
/// Returns all-zero for 0.0, NaN, or ±Inf.
func encodeTI59BCD(_ value: Double) -> [UInt8] {
    var nibbles = [UInt8](repeating: 0, count: 16)
    guard value.isFinite && value != 0.0 else { return nibbles }

    let negative = value < 0.0
    let absVal   = abs(value)

    // Normalised form: mantissa in [1.0, 10.0), exponent is base-10.
    var exp      = Int(floor(log10(absVal)))
    var mantissa = absVal / pow(10.0, Double(exp))

    // Correct floating-point rounding at boundaries
    if mantissa >= 10.0 { mantissa /= 10.0; exp += 1 }
    else if mantissa < 1.0 { mantissa *= 10.0; exp -= 1 }

    // nibble[0]: bit 1 = mantissa sign (1=negative), bit 2 = exponent sign (1=negative)
    nibbles[0] = (negative ? 2 : 0) | (exp < 0 ? 4 : 0)

    // nibble[1..2]: exponent magnitude (0–99), not 10's complement.
    // RAM serial BCD layout: nibble[1]=LSD (units), nibble[2]=MSD (tens).
    let expMag = abs(exp)
    nibbles[1] = UInt8(expMag % 10)   // units digit of magnitude
    nibbles[2] = UInt8(expMag / 10)   // tens  digit of magnitude

    // nibble[15..3]: 13 mantissa digits, MSD at nibble[15], LSD at nibble[3].
    // (Serial BCD arithmetic propagates carry from low to high index, so LSD
    //  lives at the lower index.  MSD = nibble[15] matches the display order.)
    var remaining = mantissa
    for i in stride(from: 15, through: 3, by: -1) {
        let digit = Int(remaining)
        nibbles[i] = UInt8(min(max(digit, 0), 9))
        remaining = (remaining - Double(digit)) * 10.0
    }

    return nibbles
}
