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
}
