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

    // MARK: - Layout
    // Per-template geometry, span merging, dividers and shrink-to-fit come from
    // Shared/CueCard (TIViewRules), shared with the Qt6 app; colours stay here.

    private var layout: TICueCardLayout { TIViewRules.cueCardLayout(for: card.templateIndex) }

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

                    cardContent(layout: layout, w: w, h: h)

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

    /// Label spans of one grid row (0 = A′–E′, 1 = A–E): Shared/CueCard labelSpans.
    private func getColumnSpans(row: Int) -> [TILabelSpan] {
        TIViewRules.labelSpans(of: card.bridged, row: row)
    }

    @ViewBuilder
    private func dividerLine(dividerIndices: [Int], yPosition: CGFloat, dividerColor: Color, dividerWidth: CGFloat, dividerHeight: CGFloat, layout: TICueCardLayout, w: CGFloat) -> some View {
        ForEach(dividerIndices, id: \.self) { i in
            let x = w * ((layout.xFractions[i].doubleValue + layout.xFractions[i + 1].doubleValue) / 2)
            Rectangle()
                .fill(dividerColor)
                .frame(width: dividerWidth, height: dividerHeight)
                .position(x: x, y: yPosition)
        }
    }

    @ViewBuilder
    private func gridRowLabels(spans: [TILabelSpan], fontSize: CGFloat, yPosition: CGFloat, layout: TICueCardLayout, w: CGFloat, color: Color) -> some View {
        ForEach(0..<spans.count, id: \.self) { spanIdx in
            let span = spans[spanIdx]
            let startX = w * layout.xFractions[span.startCol].doubleValue
            let endX = w * layout.xFractions[span.endCol].doubleValue
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
    private func cardContent(layout: TICueCardLayout, w: CGFloat, h: CGFloat) -> some View {
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
            : titleAvailW / (CGFloat(TIViewRules.displayLength(card.title)) * 0.64)
        let titleFS = min(scaledTitleFS, titleByWidth)

        // Divider-based geometry for content rows: calculated from grid font size, not title.
        // This decouples grid sizing from title sizing, ensuring consistent grid rendering
        // regardless of how much the title gets shrunk.
        let charW = scaledGridFS * 0.64
        let gridLeftX  = w * (layout.xFractions[0].doubleValue - layout.cellWidthFraction / 2) + charW * 0.5
        let gridRightX = w * (layout.xFractions[4].doubleValue + layout.cellWidthFraction / 2) - charW * 1.0
        let gridWidth  = gridRightX - gridLeftX
        let gridCenterX = (gridLeftX + gridRightX) / 2

        // Ink color: SolidState cards are printed (fixed gold); CueCard/MagnetCard are
        // user-labeled, so their ink follows the CUECARD "PencilColor:" field (default black).
        let inkColor = layout.drawsDividers ? Self.goldColor : Self.inkColor(for: card.color)

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
                let fontSize0 = TIViewRules.cellFittingFontSize(row0Spans, templateKind: card.templateIndex,
                                                                cardWidth: w, scaledGridFontSize: scaledGridFS)
                if layout.drawsDividers {
                    let row0Dividers = TIViewRules.dividers(between: row0Spans).map(\.intValue)
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
                let fontSize1 = TIViewRules.cellFittingFontSize(row1Spans, templateKind: card.templateIndex,
                                                                cardWidth: w, scaledGridFontSize: scaledGridFS)
                if layout.drawsDividers {
                    let row1Dividers = TIViewRules.dividers(between: row1Spans).map(\.intValue)
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
