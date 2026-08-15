import SwiftUI

struct CueCardView: View, Equatable {
    let content: CueCardContent?

    static func == (lhs: CueCardView, rhs: CueCardView) -> Bool {
        lhs.content == rhs.content
    }

    private var card: CueCardContent {
        content ?? CueCardContent.ml01Default
    }

    private static let goldColor = Color(red: 0xC4/255, green: 0x92/255, blue: 0x23/255)
    private static let dividerColor = Color(red: 188/255.0, green: 157/255.0, blue: 96/255.0)

    // Alternate inks for CueCard/MagnetCard, selectable via the CUECARD "PencilColor:" field.
    // Chosen to read as a distinct hue against the template's near-black divider lines,
    // rather than a flat black-on-black merge, where labels cross those dividers.
    private static let sharpieColor = Color(red: 112/255.0, green: 42/255.0, blue: 72/255.0)
    private static let pencilColor = Color(red: 0x4A/255, green: 0x47/255, blue: 0x44/255)

    private static func inkColor(for color: CueCardInkColor) -> Color {
        switch color {
        case .black: return .black
        case .pencil: return pencilColor
        case .sharpie: return sharpieColor
        }
    }

    // MARK: - Layout constants

    private struct GridCardLayout {
        let titleFontSize: CGFloat
        let gridFontSize: CGFloat
        let bankFontSize: CGFloat
        let titleYFraction: CGFloat
        let titleWidthFraction: CGFloat
        let gridY0Fraction: CGFloat
        let gridY1Fraction: CGFloat
        let xFractions: [CGFloat]
        let cellWidthFraction: CGFloat
        let drawsDividers: Bool
        let textColor: Color
        let hasId: Bool
        let referenceWidth: CGFloat
    }

    // Shared Y positions for SolidState template (uses the same card image)
    private static let solidStateTitleYFraction: CGFloat = 0.355
    private static let solidStateRow1YFraction: CGFloat = 0.60
    private static let solidStateRow2YFraction: CGFloat = 0.84

    // CueCard: same font sizes and cellWidthFraction as SolidStateCard/MagnetCard.
    // Keeps its own Y-axis coordinates; only background image differs from MagnetCard.
    private static let cueLayout = GridCardLayout(
        titleFontSize: 22, gridFontSize: 21, bankFontSize: 20,
        titleYFraction: 0.399, titleWidthFraction: 0.90,
        gridY0Fraction: 0.632, gridY1Fraction: 0.862,
        xFractions: [0.099, 0.293, 0.487, 0.681, 0.879],
        cellWidthFraction: 0.186,
        drawsDividers: false, textColor: .black, hasId: false, referenceWidth: 800
    )

    // MagnetCard uses same font sizes as SolidStateCard for consistency.
    // Different card background (image) but matching font rendering and x-axis coordinates.
    private static let magnetLayout = GridCardLayout(
        titleFontSize: 22, gridFontSize: 21, bankFontSize: 20,
        titleYFraction: 0.385, titleWidthFraction: 0.90,
        gridY0Fraction: 0.635, gridY1Fraction: 0.875,
        xFractions: [0.097, 0.288, 0.478, 0.668, 0.859],
        cellWidthFraction: 0.186,
        drawsDividers: false, textColor: .black, hasId: false, referenceWidth: 800
    )

    // SolidState: unified layout for both free-text rows and label grids.
    private static let solidLayout = GridCardLayout(
        titleFontSize: 22, gridFontSize: 21, bankFontSize: 14,
        titleYFraction: solidStateTitleYFraction, titleWidthFraction: 0.90,
        gridY0Fraction: solidStateRow1YFraction, gridY1Fraction: solidStateRow2YFraction,
        xFractions: [0.097, 0.288, 0.478, 0.668, 0.859],
        cellWidthFraction: 0.186,
        drawsDividers: true, textColor: Self.goldColor, hasId: true, referenceWidth: 800
    )

    // MARK: - Body

    var body: some View {
        if content != nil {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Use exact view dimensions to keep artwork and overlay coordinates aligned.
                    Image(card.template.rawValue)
                        .resizable()
                        .frame(width: w, height: h)

                    switch card.template {
                    case .cueCard:
                        cardContent(layout: Self.cueLayout, w: w, h: h)
                    case .magnetCard:
                        cardContent(layout: Self.magnetLayout, w: w, h: h)
                    case .solidState:
                        cardContent(layout: Self.solidLayout, w: w, h: h)
                    }

                    // Top-wash overlay: exactly 28% of card height, same as original
                    Rectangle()
                        .fill(Color(red: 0.1, green: 0.02, blue: 0.02).opacity(0.4))
                        .frame(height: h * 0.28)
                        .position(x: w / 2, y: h * 0.14)
                }
            }
            .clipped()
        }
    }

    // MARK: - Unified card rendering

    // MARK: - Helper: compute largest font where labels fit in cells

    // Character width multiplier: 0.64 × fontSize for SwiftUI system fonts at .bold weight
    // This is used consistently throughout font sizing and positioning calculations
    private func cellFittingFontSize(spans: [(startCol: Int, endCol: Int, label: String)], layout: GridCardLayout, w: CGFloat) -> CGFloat {
        var size = layout.gridFontSize
        for span in spans {
            let spanWidth = w * layout.cellWidthFraction * CGFloat(span.endCol - span.startCol + 1)
            let fitting = spanWidth / (CGFloat(span.label.count) * 0.64)
            if fitting < size { size = fitting }
        }
        return max(size, layout.gridFontSize * 0.4)
    }

    // MARK: - Title and ID row helper

    @ViewBuilder
    private func titleAndIdRow(title: String, id: String, fontSize: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat, color: Color) -> some View {
        Text(title)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .position(x: x, y: y)
        if !id.isEmpty {
            Text(id)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: width, alignment: .trailing)
                .position(x: x, y: y)
        }
    }

    private let invisibleMarker = cueCardInvisibleMarker

    // Helper: detect column spans (combined columns)
    private func getColumnSpans(row: Int) -> [(startCol: Int, endCol: Int, label: String)] {
        var spans: [(Int, Int, String)] = []
        var i = 0
        let base = row * 5

        while i < 5 {
            let label = card.labels[base + i]

            // Skip empty and invisible markers
            if label.isEmpty || label == invisibleMarker {
                i += 1
                continue
            }

            // Found a non-empty label, find how many columns it spans.
            // Only extend into columns explicitly blanked with \blank (invisibleMarker);
            // trailing empty columns do not span — they leave the label in its own cell.
            var spanEnd = i
            while spanEnd + 1 < 5 && (card.labels[base + spanEnd + 1] == invisibleMarker) {
                spanEnd += 1
            }

            spans.append((i, spanEnd, label))
            i = spanEnd + 1
        }

        return spans
    }

    // Helper: compute which dividers to draw (skip dividers within spans)
    private func dividersToDraw(for spans: [(startCol: Int, endCol: Int, label: String)]) -> [Int] {
        var dividers: [Int] = []
        for i in 0..<4 {
            var skipDivider = false
            for span in spans {
                if i >= span.startCol && i < span.endCol {
                    skipDivider = true
                    break
                }
            }
            if !skipDivider {
                dividers.append(i)
            }
        }
        return dividers
    }

    @ViewBuilder
    private func dividerLine(dividerIndices: [Int], yPosition: CGFloat, dividerColor: Color, dividerWidth: CGFloat, dividerHeight: CGFloat, layout: GridCardLayout, w: CGFloat) -> some View {
        ForEach(dividerIndices, id: \.self) { i in
            let x = w * ((layout.xFractions[i] + layout.xFractions[i + 1]) / 2)
            Rectangle()
                .fill(dividerColor)
                .frame(width: dividerWidth, height: dividerHeight)
                .position(x: x, y: yPosition)
        }
    }

    @ViewBuilder
    private func gridRowLabels(spans: [(startCol: Int, endCol: Int, label: String)], fontSize: CGFloat, yPosition: CGFloat, layout: GridCardLayout, w: CGFloat, color: Color) -> some View {
        ForEach(0..<spans.count, id: \.self) { spanIdx in
            let span = spans[spanIdx]
            let startX = w * layout.xFractions[span.startCol]
            let endX = w * layout.xFractions[span.endCol]
            let spanCenterX = (startX + endX) / 2
            let spanWidth = w * layout.cellWidthFraction * CGFloat(span.endCol - span.startCol + 1)

            Text(span.label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: spanWidth, alignment: .center)
                .position(x: spanCenterX, y: yPosition)
        }
    }

    @ViewBuilder
    private func cardContent(layout: GridCardLayout, w: CGFloat, h: CGFloat) -> some View {
        let titleY = h * layout.titleYFraction
        let gridY0 = h * layout.gridY0Fraction
        let gridY1 = h * layout.gridY1Fraction

        let scaleFactor = w / layout.referenceWidth
        let scaledGridFS = layout.gridFontSize * scaleFactor
        let scaledTitleFS = layout.titleFontSize * scaleFactor
        let scaledBankFS = layout.bankFontSize * scaleFactor

        // Title row: shrink if title is too wide
        let titleAvailW = w * layout.titleWidthFraction
        let titleByWidth = card.title.isEmpty ? scaledTitleFS
            : titleAvailW / (CGFloat(card.title.count) * 0.64)
        let titleFS = min(scaledTitleFS, titleByWidth)

        // Divider-based geometry for content rows: calculated from grid font size, not title.
        // This decouples grid sizing from title sizing, ensuring consistent grid rendering
        // regardless of how much the title gets shrunk.
        let charW = scaledGridFS * 0.64
        let gridLeftX  = w * (layout.xFractions[0] - layout.cellWidthFraction / 2) + charW * 0.5
        let gridRightX = w * (layout.xFractions[4] + layout.cellWidthFraction / 2) - charW * 1.0
        let gridWidth  = gridRightX - gridLeftX
        let gridCenterX = (gridLeftX + gridRightX) / 2

        // Ink color: SolidState cards are printed (fixed gold); CueCard/MagnetCard are
        // user-labeled, so their ink follows the CUECARD "PencilColor:" field (default black).
        let inkColor = layout.drawsDividers ? layout.textColor : Self.inkColor(for: card.color)

        // TITLE ROW: Title (and ID if present)
        if layout.hasId {
            titleAndIdRow(title: card.title, id: card.id, fontSize: titleFS, x: gridCenterX, y: titleY, width: gridWidth, color: inkColor)
        } else {
            Text(card.title)
                .font(.system(size: titleFS, weight: .bold))
                .foregroundColor(inkColor)
                .lineLimit(1)
                .frame(width: titleAvailW)
                .position(x: w / 2, y: titleY)
        }

        // BANK BADGES (MagnetCard only)
        if card.template == .magnetCard {
            if let leftBank = card.banks.0 {
                Text("\(leftBank)")
                    .font(.system(size: scaledBankFS, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: w * 0.12, height: h * 0.15)
                    .clipped()
                    .position(x: w * 0.08, y: h * 0.14)
            }
            if let rightBank = card.banks.1 {
                Text("\(rightBank)")
                    .font(.system(size: scaledBankFS, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: w * 0.12, height: h * 0.15)
                    .clipped()
                    .position(x: w * 0.92, y: h * 0.14)
            }
        }

        // TOP ROW (gridY0): Row1 text OR label grid (A'-E')
        if !card.row1.isEmpty {
            alignedText(card.row1, fontSize: scaledGridFS, align: card.row1Align,
                        x: gridCenterX, y: gridY0, width: gridWidth, color: inkColor)
        } else {
            let row0Spans = getColumnSpans(row: 0)
            if !row0Spans.isEmpty {
                let fontSize0 = min(scaledGridFS, cellFittingFontSize(spans: row0Spans, layout: layout, w: w))
                if layout.drawsDividers {
                    let row0Dividers = dividersToDraw(for: row0Spans)
                    dividerLine(dividerIndices: row0Dividers, yPosition: gridY0, dividerColor: Self.dividerColor, dividerWidth: 1, dividerHeight: h * 0.202, layout: layout, w: w)
                }
                gridRowLabels(spans: row0Spans, fontSize: fontSize0, yPosition: gridY0, layout: layout, w: w, color: inkColor)
            }
        }

        // BOTTOM ROW (gridY1): Row2/Row2R text OR label grid (A-E)
        if !card.row2.isEmpty || !card.row2R.isEmpty {
            if card.row2R.isEmpty {
                alignedText(card.row2, fontSize: scaledGridFS, align: card.row2Align,
                            x: gridCenterX, y: gridY1, width: gridWidth, color: inkColor)
            } else {
                let leftWidth = gridWidth * 0.70
                let rightWidth = gridWidth * 0.30
                let leftCenterX = gridLeftX + leftWidth / 2
                let rightCenterX = gridRightX - rightWidth / 2
                alignedText(card.row2, fontSize: scaledGridFS, align: card.row2Align,
                            x: leftCenterX, y: gridY1, width: leftWidth, color: inkColor)
                alignedText(card.row2R, fontSize: scaledGridFS, align: card.row2RAlign,
                            x: rightCenterX, y: gridY1, width: rightWidth, color: inkColor)
            }
        } else {
            let row1Spans = getColumnSpans(row: 1)
            if !row1Spans.isEmpty {
                let fontSize1 = min(scaledGridFS, cellFittingFontSize(spans: row1Spans, layout: layout, w: w))
                if layout.drawsDividers {
                    let row1Dividers = dividersToDraw(for: row1Spans)
                    dividerLine(dividerIndices: row1Dividers, yPosition: gridY1, dividerColor: Self.dividerColor, dividerWidth: 1, dividerHeight: h * 0.202, layout: layout, w: w)
                }
                gridRowLabels(spans: row1Spans, fontSize: fontSize1, yPosition: gridY1, layout: layout, w: w, color: inkColor)
            }
        }
    }

    @ViewBuilder
    private func alignedText(_ text: String, fontSize: CGFloat, align: TextAlign, x: CGFloat, y: CGFloat, width: CGFloat, color: Color) -> some View {
        let swiftAlign: Alignment = align == .right ? .trailing : (align == .center ? .center : .leading)

        if card.style == .button {
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: width, alignment: swiftAlign)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .border(color, width: 1)
                .position(x: x, y: y)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: width, alignment: swiftAlign)
                .position(x: x, y: y)
        }
    }
}

#Preview {
    VStack {
        Text("CueCard")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .cueCard,
            title: "Quadratic",
            labels: ["solve ax²+bx+c", "roots", "discriminant", "", "", "area", "perimeter", "volume", "", ""]
        ))
        .frame(height: 100)

        Text("MagnetCard")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .magnetCard,
            title: "Interest",
            banks: (1, 2),
            labels: ["A", "B", "C", "D", "E", "A'", "B'", "C'", "D'", "E'"]
        ))
        .frame(height: 100)

        Text("SolidState (LE07)")
            .font(.headline)
        CueCardView(content: .ml01Default)
            .frame(height: 100)

        Text("SolidState (ML02 with math tokens and free-text row1)")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .solidState,
            title: "DETERMINANT, MATRIX, & SIMUL. EQ.",
            id: "ML-02",
            row1: "i: \u{2192} x\u{1D62} | \u{2192} A⁻¹ | j: \u{2192} a\u{1D62}\u{1D6A}⁻¹ || \u{2192} |A|, A⁻¹",
            row1Align: .center
        ))
        .frame(height: 100)

        Text("SolidState (ML02 with label grid)")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .solidState,
            title: "DETERMINANT, MATRIX, & SIMUL. EQ.",
            id: "ML-02",
            labels: [
                "i; \u{2192} x\u{1D62}", "\u{2192} A⁻¹", "j; \u{2192} a\u{1D62}\u{1D6A}⁻¹", "", "\u{2192} |A|, A⁻¹",
                "n", "j: a\u{1D62}\u{1D6A}", "\u{2192} |A|", "i: b\u{1D62}", "\u{2192} x"
            ]
        ))
        .frame(height: 100)

        Text("Default (nil)")
            .font(.headline)
        CueCardView(content: nil)
            .frame(height: 100)
    }
    .padding()
}
