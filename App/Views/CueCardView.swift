import SwiftUI

struct CueCardView: View, Equatable {
    let content: CueCardContent?

    static func == (lhs: CueCardView, rhs: CueCardView) -> Bool {
        lhs.content == rhs.content
    }

    private var card: CueCardContent {
        content ?? CueCardContent.ml01Default
    }

    private static let dividerColor = Color(rgb: TIViewRules.cueCardDividerColor)

    // MARK: - Layout
    // Geometry, inks, span merging, dividers and shrink-to-fit come from
    // Shared/CueCard (TIViewRules), shared with the Qt6 app.

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

                    let bridged = card.bridged
                    let g = TIViewRules.cueCardGeometry(bridged, width: w, height: h)
                    cardContent(bridged, g: g, w: w)

                    // Top wash over the card's upper part.
                    Rectangle()
                        .fill(Color(rgb: TIViewRules.cueCardWashColor).opacity(TIViewRules.cueCardWashAlpha))
                        .frame(height: g.washHeight)
                        .position(x: w / 2, y: g.washHeight / 2)
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

    @ViewBuilder
    private func dividerLine(dividerIndices: [Int], yPosition: CGFloat, height: CGFloat, w: CGFloat) -> some View {
        ForEach(dividerIndices, id: \.self) { i in
            Rectangle()
                .fill(Self.dividerColor)
                .frame(width: 1, height: height)
                .position(x: TIViewRules.cueCardDividerX(i, templateKind: card.templateIndex, width: w), y: yPosition)
        }
    }

    @ViewBuilder
    private func gridRowLabels(spans: [TILabelSpan], fontSize: CGFloat, yPosition: CGFloat, w: CGFloat, color: Color) -> some View {
        ForEach(0..<spans.count, id: \.self) { spanIdx in
            let frame = TIViewRules.cueCardSpanFrame(spans[spanIdx], templateKind: card.templateIndex, y: yPosition, width: w)
            Text(spans[spanIdx].label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: frame.width, alignment: .center)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// One grid row (0 = A′–E′, 1 = A–E): dividers (SolidState) and shrink-to-fit labels.
    @ViewBuilder
    private func gridRow(_ row: Int, of bridged: TICueCard, y: CGFloat, g: TICueCardGeometry, w: CGFloat, color: Color) -> some View {
        let spans = TIViewRules.labelSpans(of: bridged, row: row)
        if !spans.isEmpty {
            let fontSize = TIViewRules.cellFittingFontSize(spans, templateKind: card.templateIndex,
                                                           cardWidth: w, scaledGridFontSize: g.gridFontSize)
            if g.drawsDividers {
                dividerLine(dividerIndices: TIViewRules.dividers(between: spans).map(\.intValue),
                            yPosition: y, height: g.dividerHeight, w: w)
            }
            gridRowLabels(spans: spans, fontSize: fontSize, yPosition: y, w: w, color: color)
        }
    }

    @ViewBuilder
    private func cardContent(_ bridged: TICueCard, g: TICueCardGeometry, w: CGFloat) -> some View {
        let inkColor = Color(rgb: TIViewRules.cueCardInk(bridged))

        // TITLE ROW: Title (and ID if present)
        if g.hasId {
            titleAndIdRow(title: card.title, id: card.id, fontSize: g.titleFontSize, x: g.gridCenter, y: g.titleY,
                          width: g.gridWidth, color: inkColor)
        } else {
            Text(card.title)
                .font(.system(size: g.titleFontSize, weight: .bold))
                .foregroundColor(inkColor)
                .lineLimit(1)
                .frame(width: g.titleWidth)
                .position(x: w / 2, y: g.titleY)
        }

        // BANK BADGES (MagnetCard only)
        if card.template == .magnetCard {
            if let leftBank = card.banks.0 { bankBadge(leftBank, frame: g.bankLeft, fontSize: g.bankFontSize) }
            if let rightBank = card.banks.1 { bankBadge(rightBank, frame: g.bankRight, fontSize: g.bankFontSize) }
        }

        // TOP ROW (gridY0): Row1 text OR label grid (A'-E')
        if !card.row1.isEmpty {
            alignedText(card.row1, fontSize: g.gridFontSize, align: card.row1Align,
                        x: g.gridCenter, y: g.gridY0, width: g.gridWidth, color: inkColor, g: g)
        } else {
            gridRow(0, of: bridged, y: g.gridY0, g: g, w: w, color: inkColor)
        }

        // BOTTOM ROW (gridY1): Row2/Row2R text OR label grid (A-E)
        if !card.row2.isEmpty || !card.row2R.isEmpty {
            if card.row2R.isEmpty {
                alignedText(card.row2, fontSize: g.gridFontSize, align: card.row2Align,
                            x: g.gridCenter, y: g.gridY1, width: g.gridWidth, color: inkColor, g: g)
            } else {
                alignedText(card.row2, fontSize: g.gridFontSize, align: card.row2Align,
                            x: g.row2Left.midX, y: g.row2Left.midY, width: g.row2Left.width, color: inkColor, g: g)
                alignedText(card.row2R, fontSize: g.gridFontSize, align: card.row2RAlign,
                            x: g.row2Right.midX, y: g.row2Right.midY, width: g.row2Right.width, color: inkColor, g: g)
            }
        } else {
            gridRow(1, of: bridged, y: g.gridY1, g: g, w: w, color: inkColor)
        }
    }

    private func bankBadge(_ bank: Int, frame: CGRect, fontSize: CGFloat) -> some View {
        Text("\(bank)")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.black)
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .position(x: frame.midX, y: frame.midY)
    }

    @ViewBuilder
    private func alignedText(_ text: String, fontSize: CGFloat, align: TextAlign, x: CGFloat, y: CGFloat, width: CGFloat,
                             color: Color, g: TICueCardGeometry) -> some View {
        let swiftAlign: Alignment = align == .right ? .trailing : (align == .center ? .center : .leading)

        if card.style == .button {
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .frame(width: width, alignment: swiftAlign)
                .padding(.horizontal, g.buttonPadX)
                .padding(.vertical, g.buttonPadY)
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
