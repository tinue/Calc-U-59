import Foundation

/// Zero-width space marking a grid cell as merged into the preceding label's span.
/// Written to `\blank` on disk (see Shared/CueCard.hpp) since the raw character
/// does not survive whitespace-trimming on a round trip through a file.
let cueCardInvisibleMarker = TICueCard.invisibleMarker()

// Cue card parsing, encoding and the math-token table live in Shared/CueCard.cpp;
// this file holds the SwiftUI-facing value type and its bridge conversion.

enum TextAlign: String {
    case left
    case center
    case right
}

enum CueCardTemplate: String {
    case cueCard         = "CueCard"
    case magnetCard      = "MagnetCard"
    case solidState      = "SolidStateCard"
}

enum CardButtonStyle: String {
    case none    // no button styling
    case button  // draw rectangle border around text
}

enum CueCardInkColor: String {
    case black
    case pencil
    case sharpie
}

struct CueCardContent: Equatable {
    var template: CueCardTemplate = .cueCard
    var title: String = ""
    var banks: (Int?, Int?) = (nil, nil)  // MagnetCard: (left badge, right badge), nil = blank
    var id: String = ""                   // SolidState: right of program-name row
    var labels: [String] = Array(repeating: "", count: 10)  // [A,B,C,D,E, A′,B′,C′,D′,E′]
    var row1: String = ""
    var row1Align: TextAlign = .center
    var row2: String = ""
    var row2Align: TextAlign = .left
    var row2R: String = ""
    var row2RAlign: TextAlign = .left
    var style: CardButtonStyle = .none
    var color: CueCardInkColor = .black

    static let ml01Default = CueCardContent(TICueCard.ml01Default())

    static func == (lhs: CueCardContent, rhs: CueCardContent) -> Bool {
        lhs.template == rhs.template &&
        lhs.title == rhs.title &&
        lhs.banks == rhs.banks &&
        lhs.id == rhs.id &&
        lhs.labels == rhs.labels &&
        lhs.row1 == rhs.row1 &&
        lhs.row1Align == rhs.row1Align &&
        lhs.row2 == rhs.row2 &&
        lhs.row2Align == rhs.row2Align &&
        lhs.row2R == rhs.row2R &&
        lhs.row2RAlign == rhs.row2RAlign &&
        lhs.style == rhs.style &&
        lhs.color == rhs.color
    }
}

// MARK: - Bridge conversion (TICueCard enum values follow the C++ enumerator order)

private let templates: [CueCardTemplate] = [.cueCard, .magnetCard, .solidState]
private let aligns: [TextAlign] = [.left, .center, .right]
private let styles: [CardButtonStyle] = [.none, .button]
private let colors: [CueCardInkColor] = [.black, .pencil, .sharpie]

extension CueCardContent {
    init(_ t: TICueCard) {
        self.init()
        template = templates[t.templateKind]
        title = t.title
        banks = (t.bankLeft?.intValue, t.bankRight?.intValue)
        id = t.cardID
        labels = t.labels
        row1 = t.row1
        row1Align = aligns[t.row1Align]
        row2 = t.row2
        row2Align = aligns[t.row2Align]
        row2R = t.row2R
        row2RAlign = aligns[t.row2RAlign]
        style = styles[t.style]
        color = colors[t.color]
    }

    var bridged: TICueCard {
        let t = TICueCard()
        t.templateKind = templates.firstIndex(of: template)!
        t.title = title
        t.bankLeft = banks.0.map { NSNumber(value: $0) }
        t.bankRight = banks.1.map { NSNumber(value: $0) }
        t.cardID = id
        t.labels = labels
        t.row1 = row1
        t.row1Align = aligns.firstIndex(of: row1Align)!
        t.row2 = row2
        t.row2Align = aligns.firstIndex(of: row2Align)!
        t.row2R = row2R
        t.row2RAlign = aligns.firstIndex(of: row2RAlign)!
        t.style = styles.firstIndex(of: style)!
        t.color = colors.firstIndex(of: color)!
        return t
    }
}

extension Optional where Wrapped == TICueCard {
    var swiftValue: CueCardContent? { map(CueCardContent.init) }
}
