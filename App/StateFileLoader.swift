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
//       One or more lines of keycodes.  Two formats are accepted and may be
//       mixed freely within the same file, but the choice is per line — a
//       single line is always entirely one format, never a mix of both:
//
//         Format 1 — bare keycodes:        76 11 42 00
//         Format 2 — step-number prefix:   002  61        (one step per line)
//
//       A 3-or-more-digit number at the start of a line sets the current step
//       address (sparse loading: unlisted steps default to 00) and marks the
//       line as format 2. Format-2 lines carry exactly one keycode — the
//       first numeric token after the prefix; any further token on that line
//       (e.g. the mnemonic label from a printer listing, such as "002 61 GTO"
//       or the self-describing "473 00 0" for a digit key) is ignored. This
//       matters because digit keys' mnemonics are themselves numeric ("0"–"9"),
//       so a naive scan would misread the label as a second keycode. Without
//       a prefix (format 1), every numeric token 0–99 on the line is a
//       keycode, continuing from the previous step. Mnemonic text is silently
//       ignored in both formats.
//
//       A line containing only "..." is a gap marker: it is ignored by the
//       parser (steps in the gap remain 00) but documents that a section of
//       zeros has been intentionally omitted.
//
//   REGISTERS:
//       Lines of the form "NN = value", where NN is 00–99 and value is any
//       floating-point literal accepted by Swift's Double initialiser. NN
//       addresses a normal data register (reachable via STO/RCL on the real
//       hardware) — including 60–99 on the TI-59, which are ordinary
//       registers there, not the TI-58C's extra ones (see next paragraph).
//       TI-58C files only: its 4 *extra* constant-memory registers — never
//       reachable via STO/RCL, not normal registers "60"-"63" — may be loaded
//       with "HNN = value" syntax, where NN is 00–03. See
//       `reference/CoreArchitecture.md` § "TI-58C Extra (Constant Memory)
//       Registers" for what lives there and why they're numbered separately.
//
//   KEYSTROKES:
//       Keystrokes to inject after the program and registers have been loaded,
//       simulating physical key presses on the hardware matrix.
//
//       Matrix codes use the same numeric format as PROGRAM lines, but no
//       step-number prefix is supported.  Mnemonic labels are silently ignored.
//       Each key is held 100 ms, then released, then playback waits for the
//       CPU to actually reach the keyboard-scan idle loop before the next
//       event — this guarantees no keystroke is ever lost to a still-computing
//       calculator, no matter how long the preceding computation takes.
//
//       Note: "Adv" (2nd + `.`) is a repeat-while-held key on real hardware —
//       holding it for 100ms at regular speed typically fires it 2-3 times,
//       roughly matching a brief real button press. At full speed this can
//       fire far more times (the busy gate it waits on is a fixed CPU-step
//       count, not a real-time delay, so full speed can clear/re-fire it many
//       times within the same 100ms of real hold) — switch to RegularSpeed:
//       before pressing "Adv" via KEYSTROKES to avoid a paper-feed runaway.
//
//       An explicit wait between lines is specified with:
//           Wait: 2s        (seconds)
//           Wait: 500ms     (milliseconds)
//       This is a fixed pause on top of the above — useful for letting a human
//       watch the display before the script moves on — not required for
//       correctness.
//
//       FullSpeed: / RegularSpeed: switch the emulator to/from full emulation
//       speed persistently (no duration, no auto-revert) — useful for racing
//       through a long computation. Speed always reverts to regular at the
//       end of the KEYSTROKES sequence even if the script omits RegularSpeed:.
//       WaitFullSpeed: <time> (below) remains supported for a bounded window.
//
//       ZeroElapseTime / ReportElapseTime read the core's elapsed-instruction
//       counter (zeroed on reset, tracking wall-clock time via the model's
//       clock speed). ZeroElapseTime snapshots the current count as a baseline;
//       ReportElapseTime writes the elapsed time since that baseline to the
//       debug log (regardless of the debug level setting). Both may appear
//       any number of times, in any order.
//
//       A CPU instruction trace can be scripted with:
//           Trace: name.bin  starts (or restarts) a trace, writing every
//                            executed instruction to name.bin under the
//                            configured trace directory (see Settings).
//                            An existing file of that name is silently
//                            overwritten. The rest of the line, verbatim
//                            (no whitespace splitting), is the filename —
//                            it must not contain "/" or "\". Starting a
//                            new Trace: while one is open first closes it.
//           Trace: Off       stops the current scripted trace, if any.
//       Any trace still open when the KEYSTROKES sequence finishes is
//       closed automatically. This is unrelated to the "99" virtual key
//       below, which toggles the emulated printer's own TRACE switch.
//
//       Matrix code format: row*10 + col, row 1–9 (top–bottom), col 1–5 (left–right).
//       Valid matrix codes: 11–95.  Example:
//           Trace: demo.bin
//           21 84 65 83 95   # [2nd][π] × 2 =  → display should show 6.283185307
//           Wait: 1s
//           42 00            # STO 00
//           Trace: Off
//
//   SOLID-STATE-MODULE: ML
//       Specifies the solid-state module to load. Module ID on same line.
//       Valid IDs: ML, ST, RE, SY, NG, AV, LE, SA, BD, MU, EE, SE, AG, RP
//
//   PRINTER: on
//       Specifies whether the printer is connected. Value on same line.
//       Valid values: "on" / "off" / "true" / "false" / "1" / "0"
//
// Lines beginning with # (after optional leading whitespace) are comments.
// Inline comments after # are also stripped.  All section keywords are
// case-insensitive.

// MARK: - Result types

/// A single event in the KEYSTROKES section.
enum KeystrokeEvent {
    case key(UInt8)                  // matrix code to press (row*10 + col, row 1–9, col 1–5)
    case toggleTrace                 // virtual: toggle the emulated printer's TRACE latch (file token: 99)
    case wait(TimeInterval)          // explicit pause; emulator runs at normal speed
    case waitFullSpeed(TimeInterval) // enable full speed, wait, then restore normal speed
    case trace(String?)              // start CPU trace capture to the given filename, or stop it (nil) — unrelated to .toggleTrace
    case fullSpeed                   // persistent: switch to full speed until a matching .regularSpeed (or end of script)
    case regularSpeed                // persistent: switch back to normal speed
    case zeroElapseTime              // snapshot the core's elapsed-tick counter as the report baseline
    case reportElapseTime            // report elapsed time since the last .zeroElapseTime to the debug log
}

struct LoadStateResult {
    var partitionMaxStep: Int = 479
    /// True when the file contained an explicit PARTITION: line; false = default was used.
    var partitionWasExplicit: Bool = false
    /// Sparse list of (stepAddress, keycode) pairs. Steps not listed default to 0x00.
    var programSteps: [(stepAddr: Int, keycode: UInt8)] = []
    /// `regNum` is the user-facing number as written in the file: 00–99 for a
    /// normal register, 00–03 for an extra (H-prefixed, TI-58C-only) register.
    /// `isHidden` disambiguates the two — do NOT infer it from `regNum`'s
    /// range, since normal TI-59 registers legitimately go up to 99.
    var registers: [(regNum: Int, nibbles: [UInt8], isHidden: Bool)] = []
    var keystrokes: [KeystrokeEvent] = []
    var cueCardContent: CueCardContent? = nil
    var solidStateModuleID: String? = nil
    var printerConnected: Bool? = nil
    /// MODEL: TI-59 / TI-58 / TI-58C — switches the machine variant before applying state.
    var model: MachineModel? = nil
    /// SKIP-RESET: on — skip machine reset; apply only PROGRAM/REGISTERS/PARTITION/CUECARD/KEYSTROKES.
    var skipReset: Bool = false
    var errors: [String] = []
}

// MARK: - Parser

private enum ParseSection { case none, partition, program, registers, keystrokes, cuecard }

private func stripInlineComment(_ line: String) -> String {
    line.components(separatedBy: "#").first?
        .trimmingCharacters(in: .whitespaces) ?? ""
}

private func parseHexBytes(_ hexString: String, count: Int) -> [UInt8]? {
    let tokens = hexString.components(separatedBy: " ").filter { !$0.isEmpty }
    guard tokens.count == count else { return nil }
    let bytes = tokens.compactMap { UInt8($0, radix: 16) }
    return bytes.count == count ? bytes : nil
}

func parseStateFile(_ text: String, maxStepAddr: Int = 479, allowHiddenRegisters: Bool = false) -> LoadStateResult {
    var result = LoadStateResult()
    var section: ParseSection = .none
    var currentStep = 0

    for rawLine in text.components(separatedBy: .newlines) {
        let line = stripInlineComment(rawLine)
        if line.isEmpty { continue }

        let upper = line.uppercased()

        // Inline-value directives (not section headers, can appear anywhere)
        if upper.hasPrefix("SOLID-STATE-MODULE:") {
            let id = String(line.dropFirst("SOLID-STATE-MODULE:".count)).trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { result.solidStateModuleID = id }
            continue
        }
        if upper.hasPrefix("PRINTER:") {
            let val = String(line.dropFirst("PRINTER:".count)).trimmingCharacters(in: .whitespaces).lowercased()
            result.printerConnected = (val == "on" || val == "true" || val == "1")
            continue
        }
        if upper.hasPrefix("SKIP-RESET:") {
            let val = String(line.dropFirst("SKIP-RESET:".count)).trimmingCharacters(in: .whitespaces).lowercased()
            result.skipReset = (val == "on" || val == "true" || val == "1")
            continue
        }
        if upper.hasPrefix("MODEL:") {
            let val = String(line.dropFirst("MODEL:".count)).trimmingCharacters(in: .whitespaces).uppercased()
            if let m = MachineModel.allCases.first(where: { $0.displayName == val }) {
                result.model = m
            } else {
                let valid = MachineModel.allCases.map(\.displayName).joined(separator: ", ")
                result.errors.append("Unknown MODEL: '\(val)' — expected \(valid)")
            }
            continue
        }

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

        // Section header: CUECARD:
        if upper.hasPrefix("CUECARD:") {
            section = .cuecard
            result.cueCardContent = CueCardContent()
            continue
        }

        // Content lines
        switch section {
        case .none, .partition:
            break
        case .program:
            if line == "..." { break }  // gap marker — steps in between remain 00
            let (maybeStart, codes) = parseProgLine(line, maxStepAddr: maxStepAddr)
            if let start = maybeStart { currentStep = start }
            for code in codes {
                result.programSteps.append((stepAddr: currentStep, keycode: code))
                currentStep += 1
            }
        case .registers:
            parseRegLine(line, allowHiddenRegisters: allowHiddenRegisters, into: &result.registers, errors: &result.errors)
        case .keystrokes:
            if let t = parseWaitFullSpeedLine(line) {
                result.keystrokes.append(.waitFullSpeed(t))
            } else if let t = parseWaitLine(line) {
                result.keystrokes.append(.wait(t))
            } else if upper.hasPrefix("TRACE:") {
                if let event = parseTraceLine(line, errors: &result.errors) {
                    result.keystrokes.append(event)
                }
            } else if upper.hasPrefix("FULLSPEED:") {
                result.keystrokes.append(.fullSpeed)
            } else if upper.hasPrefix("REGULARSPEED:") {
                result.keystrokes.append(.regularSpeed)
            } else if upper.hasPrefix("ZEROELAPSETIME") {
                result.keystrokes.append(.zeroElapseTime)
            } else if upper.hasPrefix("REPORTELAPSETIME") {
                result.keystrokes.append(.reportElapseTime)
            } else {
                result.keystrokes.append(contentsOf: parseKeystrokeLine(line))
            }
        case .cuecard:
            if var card = result.cueCardContent {
                card.parseLine(line)
                result.cueCardContent = card
            }
        }
    }

    return result
}

// MARK: - Line parsers

/// Parse one program line. Returns the step address set by a prefix (if any) and
/// the keycodes found on the line. A 3-or-more-digit token at the start of the
/// line that is a valid step address (0–479) is a position prefix, not a keycode.
///
/// The notation is chosen once per line, not per token: a prefixed line (format 2)
/// always carries exactly one keycode — the token right after the prefix — and any
/// further token on that line is a mnemonic label to be ignored, even if the label
/// happens to be numeric (digit keys 0–9 are their own mnemonic, e.g. "473 00 0").
/// An un-prefixed line (format 1) treats every numeric token as a keycode.
private func parseProgLine(_ line: String, maxStepAddr: Int = 479) -> (stepAddr: Int?, keycodes: [UInt8]) {
    let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return (nil, []) }

    var startIndex = 0
    var startStep: Int? = nil
    if tokens[0].count >= 3, let n = Int(tokens[0]), n >= 0, n <= maxStepAddr {
        startStep = n   // step-address prefix: sets position, not a keycode
        startIndex = 1
    }

    if startStep != nil {
        // Format 2: single keycode follows the prefix; anything after it is a label.
        guard startIndex < tokens.count,
              tokens[startIndex].count <= 2,
              let n = Int(tokens[startIndex]), n >= 0, n <= 99 else {
            return (startStep, [])
        }
        return (startStep, [UInt8(n)])
    }

    // Format 1: every 1–2 digit numeric token in 0–99 range is a keycode.
    var keycodes: [UInt8] = []
    for token in tokens where token.count <= 2 {
        if let n = Int(token), n >= 0, n <= 99 {
            keycodes.append(UInt8(n))
        }
    }
    return (startStep, keycodes)
}

private func parseRegLine(_ line: String,
                           allowHiddenRegisters: Bool,
                           into registers: inout [(regNum: Int, nibbles: [UInt8], isHidden: Bool)],
                           errors: inout [String]) {
    // Expected format: "NN = <float>" (normal register, 00-99) or "HNN = <float>"
    // (TI-58C's 4 extra registers, H00-H03). regNum is kept as the user-facing
    // number in both cases (never pre-offset into RAM-index space here) —
    // isHidden is what the caller must branch on, not regNum's range: normal
    // TI-59 registers legitimately go up to 99, well past H-register range.
    let parts = line.components(separatedBy: "=")
    guard parts.count >= 2 else { return }
    let nnStr  = parts[0].trimmingCharacters(in: .whitespaces)
    let valStr = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

    var regNum: Int
    var isHidden = false
    if let n = Int(nnStr), n >= 0, n <= 99 {
        regNum = n
    } else if nnStr.uppercased().hasPrefix("H"),
              let n = Int(nnStr.dropFirst()), n >= 0, n <= 3 {
        if !allowHiddenRegisters {
            errors.append("Extra register \(nnStr) is only valid for TI-58C files.")
            return
        }
        regNum = n
        isHidden = true
    } else {
        return
    }

    guard Double(valStr) != nil else {
        errors.append("Cannot parse register \(nnStr) value: \"\(valStr)\"")
        return
    }
    registers.append((regNum: regNum, nibbles: encodeTI59BCD(text: valStr), isHidden: isHidden))
}

/// Parse one KEYSTROKES line into `KeystrokeEvent`s.
/// Token `99` maps to `.toggleTrace`; tokens 11–95 map to `.key`.
/// No step-address prefix logic — every valid token is an event.
/// Mnemonic labels and other non-numeric tokens are silently ignored.
private func parseKeystrokeLine(_ line: String) -> [KeystrokeEvent] {
    let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    var events: [KeystrokeEvent] = []
    for token in tokens {
        guard token.count <= 2, let n = Int(token) else { continue }
        if n == 99 {
            events.append(.toggleTrace)
        } else if n >= 11, n <= 95 {
            events.append(.key(UInt8(n)))
        }
    }
    return events
}

/// Parse a "Wait: <value><unit>" line.  Returns the interval in seconds, or nil.
/// Supported units: "s" (seconds), "ms" (milliseconds).  Case-insensitive.
private func parseWaitLine(_ line: String) -> TimeInterval? {
    parseWaitInterval(line, prefix: "WAIT:")
}

/// Parse a "WaitFullSpeed: <value><unit>" line.  Returns the interval in seconds, or nil.
/// When played back, the emulator runs at full speed for this interval and then reverts.
private func parseWaitFullSpeedLine(_ line: String) -> TimeInterval? {
    parseWaitInterval(line, prefix: "WAITFULLSPEED:")
}

private func parseWaitInterval(_ line: String, prefix: String) -> TimeInterval? {
    guard line.uppercased().hasPrefix(prefix) else { return nil }
    let rest = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    let restUpper = rest.uppercased()
    if restUpper.hasSuffix("MS"),
       let v = Double(rest.dropLast(2).trimmingCharacters(in: .whitespaces)) {
        return v / 1000.0
    }
    if restUpper.hasSuffix("S"),
       let v = Double(rest.dropLast(1).trimmingCharacters(in: .whitespaces)) {
        return v
    }
    return nil
}

/// Parse a "Trace: <filename>" / "Trace: Off" line (caller has already
/// verified the "TRACE:" prefix). The entire trimmed remainder of the line
/// is taken verbatim as the filename — no whitespace splitting, since a
/// filename may legitimately contain spaces and there is nothing else to
/// parse on this line. Returns nil (and appends an error) for a bare
/// "Trace:" with no filename, or one containing a path separator.
private func parseTraceLine(_ line: String, errors: inout [String]) -> KeystrokeEvent? {
    let rest = String(line.dropFirst("TRACE:".count)).trimmingCharacters(in: .whitespaces)
    if rest.uppercased() == "OFF" {
        return .trace(nil)
    }
    if rest.isEmpty {
        errors.append("Trace: requires a filename or \"Off\".")
        return nil
    }
    if rest.contains("/") || rest.contains("\\") {
        errors.append("Trace: filename \"\(rest)\" must not contain a path separator.")
        return nil
    }
    return .trace(rest)
}

// MARK: - BCD encoder


// MARK: - .U59 card file parser

// ── .U59 text card file format ────────────────────────────────────────────────
//
// A plain UTF-8 text file with four sections, in this order:
//
//   Calc-U-59 Card 1.0          ← magic / version line (required, first line)
//
//   CUECARD:                    ← optional; same key: value syntax as .ti59 files
//       Template: MagnetCard    ← always MagnetCard; Banks: is omitted (comes from HEADER)
//       Title: …
//       A: …  …  E:  A': …  …  E':  (same fields as .ti59 CUECARD section)
//
//   HEADER:                     ← required; decoded from binary bytes 0–3 and 244–245
//       Partition: 1C           ← hex byte (0x1C = 959 steps, 0x13 = 239 steps, …)
//       DataType: program       ← "program" | "data"
//       Bank: 1                 ← bank number 1–4; encodes as page byte 10,13,16,19
//       Protection: no          ← "yes" | "no"
//       Checksum: 02            ← hex byte; stored in bytes 244–245 of the 246-byte bank
//
//   DATA:                       ← required; 30 rows of 8 bytes (bank bytes 4–243)
//       D00: HH HH HH HH HH HH HH HH    ← D00–D29; nibble sequence per row is reversed
//       …                                   so significant data reads left-to-right
//       D29: HH HH HH HH HH HH HH HH
//
// Comments (# …) are stripped.  All section keywords and HEADER keys are
// case-insensitive.  CUECARD lines are parsed by the CueCardContent.parseLine helper.
// The bank badge for the MagnetCard cue card is injected from HEADER Bank: value.

struct CardFileResult {
    var data: Data           // full 246-byte bank buffer
    var cueCard: CueCardContent?
}

private enum CardSection { case none, cuecard, header, data }

func parseCardFile(_ text: String) -> CardFileResult? {
    var lines = text.components(separatedBy: .newlines)
    guard let firstLine = lines.first, firstLine.hasPrefix("Calc-U-59 Card ") else { return nil }
    lines.removeFirst()

    var section: CardSection = .none
    var cueCard = CueCardContent()
    var hasCueCard = false
    var partition: UInt8 = 0
    var dataType: UInt8 = 0x11
    var pageByte: UInt8 = 0x10
    var protection: UInt8 = 0x00
    var hasHeader = false
    var checksum: UInt8 = 0x00
    var dataBytes = [UInt8](repeating: 0, count: 240)  // bank bytes 4–243 (30 × 8)
    var hasData = false
    var dataRowIndex = 0  // track which register we're reading

    for raw in lines {
        let line = stripInlineComment(raw)
        if line.isEmpty { continue }

        let upper = line.uppercased()
        if upper == "CUECARD:" { section = .cuecard; hasCueCard = true; continue }
        if upper == "HEADER:"  { section = .header; continue }
        if upper == "DATA:"    { section = .data; hasData = true; dataRowIndex = 0; continue }

        switch section {
        case .none: continue

        case .cuecard:
            cueCard.parseLine(line)

        case .header:
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces).lowercased()
            switch key {
            case "partition":
                guard let v = UInt8(val, radix: 16) else { return nil }
                partition = v; hasHeader = true
            case "datatype":
                dataType = val == "program" ? 0x11 : 0x10
            case "bank":
                guard let n = Int(val), n >= 1, n <= 4 else { return nil }
                pageByte = UInt8(0x10 | ((n - 1) * 3))
            case "protection":
                protection = val == "yes" ? 0x10 : 0x00
            case "checksum":
                guard let v = UInt8(val, radix: 16) else { return nil }
                checksum = v
            default: break
            }

        case .data:
            // R### format: 30 registers per bank, 8 bytes each. Same format as ti58c.mem.
            // Labels are informational only; don't validate against bank header.
            guard line.hasPrefix("R") else { return nil }
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { return nil }
            let hexString = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            guard let fileBytes = parseHexBytes(hexString, count: 8) else { return nil }

            // Card files reverse the bytes compared to ti58c.mem format.
            // So: reverse file bytes, then decode using shared logic.
            let fileReversed = Array(fileBytes.reversed())
            let nibbles = decodeRegisterLine(fileReversed)
            let bankBytes: [UInt8] = (0..<8).map { i in
                (nibbles[2*i] << 4) | nibbles[2*i + 1]
            }

            // Store at current row offset
            let dataIndex = dataRowIndex * 8
            for (i, byte) in bankBytes.enumerated() {
                guard dataIndex + i < 240 else { break }
                dataBytes[dataIndex + i] = byte
            }
            dataRowIndex += 1
        }
    }

    guard hasHeader && hasData else { return nil }

    var bank246 = [UInt8](repeating: 0, count: 246)
    bank246[0] = partition
    bank246[1] = dataType
    bank246[2] = pageByte
    bank246[3] = protection
    bank246.replaceSubrange(4..<244, with: dataBytes)
    bank246[244] = checksum
    bank246[245] = checksum

    if hasCueCard {
        cueCard.template = .magnetCard
        let bankNum = Int((pageByte & 0x0F) / 3) + 1
        cueCard.banks = (bankNum, nil)
    }

    return CardFileResult(data: Data(bank246), cueCard: hasCueCard ? cueCard : nil)
}

// MARK: - BCD encoder

/// Encodes a `REGISTERS:` literal exactly as written in the state file.
///
/// A pure decimal integer (optional leading `-`, digits only — no `.`, no
/// `e`/`E`) is built digit-by-digit from the source text, never touching
/// `Double`. This is defense-in-depth, not a fix for an active bug: 787a227
/// already made `encodeTI59BCD(_:Double)`'s `%.12e` conversion correctly
/// rounded, and a pure integer like "3641003032" is well within `Double`'s
/// exact-integer range, so it round-trips exactly through that path too (the
/// off-by-one/trailing-9s failure reported after this preset was written
/// turned out to be a v1.5.0 build, which predates 787a227 and still has the
/// old iterative mantissa/pow/subtract loop — not a gap in the fix). Still,
/// the TI-59's register mantissa holds 13 significant digits, more than a
/// human ever keys in on the keypad, and a keyed-in integer never takes a
/// Double detour on real hardware, so building it straight from the literal
/// text removes an unnecessary step for the one input class where it's easy
/// to. Values that actually use a decimal point or exponent notation
/// ("-1.5e-3", "7.77E22") are genuinely floating-point and still go through
/// `encodeTI59BCD(_:Double)` below.
func encodeTI59BCD(text: String) -> [UInt8] {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.range(of: "^-?[0-9]+$", options: .regularExpression) != nil else {
        return Double(trimmed).map(encodeTI59BCD) ?? [UInt8](repeating: 0, count: 16)
    }

    var digits = trimmed
    let negative = digits.hasPrefix("-")
    if negative { digits.removeFirst() }
    while digits.count > 1 && digits.hasPrefix("0") { digits.removeFirst() }
    if digits == "0" { return [UInt8](repeating: 0, count: 16) }

    var nibbles = [UInt8](repeating: 0, count: 16)
    let exp = digits.count - 1   // normalised so the first digit is the mantissa MSD
    nibbles[0] = negative ? 2 : 0
    nibbles[1] = UInt8(exp % 10)
    nibbles[2] = UInt8(exp / 10)

    // nibble[15..3]: 13 mantissa digits, MSD at nibble[15], LSD at nibble[3].
    // Digits past the 13th significant figure (offset >= 13) don't fit in the
    // register and are dropped -- the same limit real hardware imposes.
    let digitChars = Array(digits)
    for (offset, i) in stride(from: 15, through: 3, by: -1).enumerated() {
        guard offset < digitChars.count, let d = digitChars[offset].wholeNumberValue else { continue }
        nibbles[i] = UInt8(d)
    }
    return nibbles
}

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

    // Get 13 correctly-rounded significant digits and the base-10 exponent via
    // the C library's %e conversion, rather than an iterative float digit
    // extraction (mantissa/10, subtract, multiply by 10, repeat): that loop
    // accumulates rounding error over 13 iterations and can turn e.g.
    // 1731371735 into a stored mantissa of 1731371734.999090.  %e is defined
    // to always emit a single leading digit in [1,9] and to bump the exponent
    // itself on rounding overflow (e.g. 9.9999999999995e8 -> 1.000000000000e9),
    // so no separate boundary correction is needed here.
    let formatted = String(format: "%.12e", absVal)
    let eIndex = formatted.firstIndex(of: "e")!
    let digitChars = formatted[..<eIndex].filter { $0.isNumber }
    let exp = Int(formatted[formatted.index(after: eIndex)...])!

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
    for (offset, i) in stride(from: 15, through: 3, by: -1).enumerated() {
        let digitIndex = digitChars.index(digitChars.startIndex, offsetBy: offset)
        nibbles[i] = UInt8(digitChars[digitIndex].wholeNumberValue!)
    }

    return nibbles
}
