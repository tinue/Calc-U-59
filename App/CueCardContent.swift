import Foundation

enum TextAlign: String {
    case left
    case center
    case right
}

enum CueCardTemplate: String {
    case cueCard      = "CueCard"
    case magnetCard   = "MagnetCard"
    case solidState   = "SolidStateCard"
}

enum CardButtonStyle: String {
    case none    // no button styling
    case button  // draw rectangle border around text
}

struct CueCardContent {
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
                self.template = template
            }
        case "title":
            self.title = value
        case "banks":
            let parts = value.components(separatedBy: ",")
            let left = parts.count > 0 ? Int(parts[0].trimmingCharacters(in: .whitespaces)) : nil
            let right = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            self.banks = (left, right)
        case "id":
            self.id = value
        case "row1":
            self.row1 = value
        case "row2":
            self.row2 = value
        case "row2r":
            self.row2R = value
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
                self.labels[idx] = value
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
}
