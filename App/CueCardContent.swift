import Foundation

// MARK: - Math token expansion

/// Expands math-notation shorthand tokens to Unicode characters.
/// Used in cue card content files to make math notation (Greek letters, subscripts, superscripts)
/// easy to author without requiring a Unicode picker.
///
/// Supported tokens:
/// - Greek: `\lambda`, `\sigma`, `\mu`, `\theta`, `\alpha`, `\beta`, `\Delta`, `\Sigma`, etc.
/// - Arrows: `\to`, `\leftarrow`, `\updownarrow`
/// - Subscripts: `_{i}`, `_{j}`, `_{0}`…`_{9}`, `_{a}`, `_{e}`, `_{o}`, `_{x}`, `_{n}`, `_{m}`, `_{k}`
/// - Superscripts: `^{0}`…`^{9}`, `^{-1}`, `^{-}`, `^{+}`, `^{n}`, `^{T}`
/// - Symbols: `\sqrt`, `\inf`, `\sum`, `\product`, `\integral`, `\approx`, `\neq`, `\leq`, `\geq`
///
/// Example: `a_{i}_{j}^{-1}` → `aᵢⱼ⁻¹`
func expandMathTokens(_ input: String) -> String {
    var result = input

    // Tokens are processed in order: longer matches before shorter ones that share a prefix
    let tokens: [(String, String)] = [
        // Greek letters
        ("\\lambda", "λ"),   // U+03BB
        ("\\Lambda", "Λ"),   // U+039B
        ("\\sigma", "σ"),    // U+03C3
        ("\\Sigma", "Σ"),    // U+03A3
        ("\\mu", "μ"),       // U+03BC
        ("\\theta", "θ"),    // U+03B8
        ("\\Theta", "Θ"),    // U+0398
        ("\\alpha", "α"),    // U+03B1
        ("\\beta", "β"),     // U+03B2
        ("\\Delta", "Δ"),    // U+0394
        ("\\pi", "π"),       // U+03C0
        ("\\Pi", "Π"),       // U+03A0

        // Arrows
        ("\\to", "→"),       // U+2192
        ("\\leftarrow", "←"), // U+2190
        ("\\updownarrow", "↕"), // U+2195

        // Math symbols
        ("\\sqrt", "√"),     // U+221A
        ("\\inf", "∞"),      // U+221E
        ("\\sum", "∑"),      // U+2211
        ("\\product", "∏"),  // U+220F
        ("\\integral", "∫"), // U+222B
        ("\\approx", "≈"),   // U+2248
        ("\\neq", "≠"),      // U+2260
        ("\\leq", "≤"),      // U+2264
        ("\\geq", "≥"),      // U+2265

        // Superscript: multi-char first
        ("^{-1}", "⁻¹"),     // U+207B + U+00B9
        ("^{-2}", "⁻²"),     // U+207B + U+00B2
        ("^{-3}", "⁻³"),     // U+207B + U+00B3
        ("^{-}", "⁻"),       // U+207B
        ("^{+}", "⁺"),       // U+207A
        ("^{*}", "ˣ"),       // U+02E3
        ("^{n}", "ⁿ"),       // U+207F
        ("^{T}", "ᵀ"),       // U+1D40 (transpose)
        ("^{0}", "⁰"),       // U+2070
        ("^{1}", "¹"),       // U+00B9
        ("^{2}", "²"),       // U+00B2
        ("^{3}", "³"),       // U+00B3
        ("^{4}", "⁴"),       // U+2074
        ("^{5}", "⁵"),       // U+2075
        ("^{6}", "⁶"),       // U+2076
        ("^{7}", "⁷"),       // U+2077
        ("^{8}", "⁸"),       // U+2078
        ("^{9}", "⁹"),       // U+2079

        // Subscript: multi-char first
        ("_{-1}", "₋₁"),     // U+2215 + U+2081
        ("_{-}", "₋"),       // U+2215
        ("_{+}", "₊"),       // U+208A
        ("_{0}", "₀"),       // U+2080
        ("_{1}", "₁"),       // U+2081
        ("_{2}", "₂"),       // U+2082
        ("_{3}", "₃"),       // U+2083
        ("_{4}", "₄"),       // U+2084
        ("_{5}", "₅"),       // U+2085
        ("_{6}", "₆"),       // U+2086
        ("_{7}", "₇"),       // U+2087
        ("_{8}", "₈"),       // U+2088
        ("_{9}", "₉"),       // U+2089
        ("_{i}", "ᵢ"),       // U+1D62
        ("_{j}", "ⱼ"),       // U+1D6A
        ("_{a}", "ₐ"),       // U+2090
        ("_{e}", "ₑ"),       // U+2091
        ("_{o}", "ₒ"),       // U+2092
        ("_{x}", "ₓ"),       // U+2093
        ("_{n}", "ₙ"),       // U+2099
        ("_{m}", "ₘ"),       // U+2098
        ("_{k}", "ₖ"),       // U+2096
    ]

    for (token, unicode) in tokens {
        result = result.replacingOccurrences(of: token, with: unicode)
    }

    return result
}

enum TextAlign: String {
    case left
    case center
    case right
}

enum CueCardTemplate: String {
    case cueCard         = "CueCard"
    case magnetCard      = "MagnetCard"
    case solidState      = "SolidStateCard"
    case solidStateGrid  = "SolidStateGridCard"
}

enum CardButtonStyle: String {
    case none    // no button styling
    case button  // draw rectangle border around text
}

struct CueCardContent: Equatable {
    var template: CueCardTemplate = .cueCard
    var title: String = ""
    var banks: (Int?, Int?) = (nil, nil)  // MagnetCard: (left badge, right badge), nil = blank
    var id: String = ""                   // SolidState: right of program-name row
    var idAlign: TextAlign = .left
    var labels: [String] = Array(repeating: "", count: 10)  // [A,B,C,D,E, A′,B′,C′,D′,E′]
    var row1: String = ""
    var row1Align: TextAlign = .center
    var row2: String = ""
    var row2Align: TextAlign = .left
    var row2R: String = ""
    var row2RAlign: TextAlign = .left
    var style: CardButtonStyle = .none

    static let ml01Default: CueCardContent = CueCardContent(
        template: .solidState,
        title: "MASTER LIBRARY DIAGNOSTIC",
        banks: (nil, nil),
        id: "ML-01",
        idAlign: .right,
        labels: Array(repeating: "", count: 10),
        row1: "DIAGNOSTIC: SBR =",
        row1Align: .center,
        row2: "L.R. INIT: SBR CLR",
        row2Align: .left,
        row2R: "PRINT: mm STO 00",
        row2RAlign: .right,
        style: .none
    )

    /// Parse a single cuecard key:value line and update self.
    mutating func parseLine(_ line: String) {
        let parts = line.components(separatedBy: ":")
        guard parts.count >= 2 else { return }
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        switch key {
        case "template":
            if let template = CueCardTemplate(rawValue: value) {
                print("[CueCard] Template parsed: \(value)")
                self.template = template
            } else {
                print("[CueCard ERROR] Unknown template: \(value)")
            }
        case "title":
            self.title = expandMathTokens(value)
            print("[CueCard] Title parsed: \(self.title)")
        case "banks":
            let parts = value.components(separatedBy: ",")
            let left = parts.count > 0 ? Int(parts[0].trimmingCharacters(in: .whitespaces)) : nil
            let right = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            self.banks = (left, right)
        case "id":
            self.id = expandMathTokens(value)
            print("[CueCard] ID parsed: \(self.id)")
        case "row1":
            self.row1 = expandMathTokens(value)
        case "row2":
            self.row2 = expandMathTokens(value)
        case "row2r":
            self.row2R = expandMathTokens(value)
        case "style":
            if let style = CardButtonStyle(rawValue: value.lowercased()) {
                self.style = style
            }
        case "idalign":
            self.idAlign = Self.parseAlignment(value)
        case "row1align":
            self.row1Align = Self.parseAlignment(value)
        case "row2align":
            self.row2Align = Self.parseAlignment(value)
        case "row2ralign":
            self.row2RAlign = Self.parseAlignment(value)
        default:
            // Map label keys to indices: A′–E′ → [0–4], A–E → [5–9]
            let labelMap: [String: Int] = [
                "a": 5, "b": 6, "c": 7, "d": 8, "e": 9,
                "a'": 0, "a′": 0, "b'": 1, "b′": 1, "c'": 2, "c′": 2,
                "d'": 3, "d′": 3, "e'": 4, "e′": 4
            ]
            if let idx = labelMap[key], idx < self.labels.count {
                self.labels[idx] = expandMathTokens(value)
                print("[CueCard] Label[\(idx)] (\(key)) parsed: \(self.labels[idx])")
            } else if !key.isEmpty {
                // Debug: show the actual characters in the key
                let chars = key.map { String(format: "U+%04X", $0.unicodeScalars.first?.value ?? 0) }
                print("[CueCard WARNING] Label key not recognized: '\(key)' chars: \(chars)")
            }
        }
    }

    /// Convert self to lines of text (key: value format).
    /// - Parameter writeTemplate: if provided, writes "Template: X" line first. Only writes "Banks:" for MagnetCard template.
    func encodeToLines(writeTemplate: CueCardTemplate? = nil) -> [String] {
        var lines: [String] = []

        if let tmpl = writeTemplate {
            lines.append("Template: \(tmpl.rawValue)")
        }

        if !title.isEmpty { lines.append("Title: \(title)") }

        // Only write Banks for MagnetCard template
        if writeTemplate == .magnetCard, banks.0 != nil || banks.1 != nil {
            let leftStr = banks.0.map(String.init) ?? ""
            let rightStr = banks.1.map(String.init) ?? ""
            lines.append("Banks: \(leftStr), \(rightStr)")
        }

        if !id.isEmpty { lines.append("ID: \(id)") }

        let primeKeys = ["A'", "B'", "C'", "D'", "E'"]
        for (i, key) in primeKeys.enumerated() {
            if i < labels.count && !labels[i].isEmpty {
                lines.append("\(key): \(labels[i])")
            }
        }

        let plainKeys = ["A", "B", "C", "D", "E"]
        for (i, key) in plainKeys.enumerated() {
            let idx = i + 5
            if idx < labels.count && !labels[idx].isEmpty {
                lines.append("\(key): \(labels[idx])")
            }
        }

        if !row1.isEmpty { lines.append("Row1: \(row1)") }
        if row1Align != .center { lines.append("Row1Align: \(row1Align.rawValue)") }
        if !row2.isEmpty { lines.append("Row2: \(row2)") }
        if row2Align != .left { lines.append("Row2Align: \(row2Align.rawValue)") }
        if !row2R.isEmpty { lines.append("Row2R: \(row2R)") }
        if row2RAlign != .left { lines.append("Row2RAlign: \(row2RAlign.rawValue)") }

        if style != .none { lines.append("Style: \(style.rawValue)") }
        if idAlign != .left { lines.append("IDAlign: \(idAlign.rawValue)") }

        return lines
    }

    private static func parseAlignment(_ value: String) -> TextAlign {
        switch value.lowercased() {
        case "right":
            return .right
        case "center":
            return .center
        default:
            return .left
        }
    }

    static func == (lhs: CueCardContent, rhs: CueCardContent) -> Bool {
        lhs.template == rhs.template &&
        lhs.title == rhs.title &&
        lhs.banks == rhs.banks &&
        lhs.id == rhs.id &&
        lhs.idAlign == rhs.idAlign &&
        lhs.labels == rhs.labels &&
        lhs.row1 == rhs.row1 &&
        lhs.row1Align == rhs.row1Align &&
        lhs.row2 == rhs.row2 &&
        lhs.row2Align == rhs.row2Align &&
        lhs.row2R == rhs.row2R &&
        lhs.row2RAlign == rhs.row2RAlign &&
        lhs.style == rhs.style
    }
}
