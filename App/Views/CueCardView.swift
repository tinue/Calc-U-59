import SwiftUI

struct CueCardView: View, Equatable {
    let content: CueCardContent?

    static func == (lhs: CueCardView, rhs: CueCardView) -> Bool {
        lhs.content == rhs.content
    }

    private var card: CueCardContent {
        content ?? CueCardContent.ml01Default
    }

    private let goldColor = Color(red: 0xC4/255, green: 0x92/255, blue: 0x23/255)

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
    }

    private struct SolidStateLayout {
        let fontSize: CGFloat
        let row1YFraction: CGFloat
        let row2YFraction: CGFloat
        let row3YFraction: CGFloat
        let rightXFraction: CGFloat
    }

    // CueCard uses three visible text bands: title (124..227), row0 (227..329), row1 (329..430).
    private static let cueLayout = GridCardLayout(
        titleFontSize: 19, gridFontSize: 14, bankFontSize: 16,
        titleYFraction: 0.399, titleWidthFraction: 0.92,
        gridY0Fraction: 0.632, gridY1Fraction: 0.862,
        xFractions: [0.101, 0.299, 0.494, 0.689, 0.884],
        cellWidthFraction: 0.16
    )

    // Derived from MagnetCard.png separator rows (px on 440px-high asset): separators≈100/223/331.
    private static let magnetLayout = GridCardLayout(
        titleFontSize: 19, gridFontSize: 14, bankFontSize: 16,
        titleYFraction: 0.385, titleWidthFraction: 0.70,
        gridY0Fraction: 0.635, gridY1Fraction: 0.875,
        xFractions: [0.097, 0.289, 0.481, 0.673, 0.874],
        cellWidthFraction: 0.16
    )

    private static let solidLayout = SolidStateLayout(
        fontSize: 12,
        row1YFraction: 0.38, row2YFraction: 0.62, row3YFraction: 0.84,
        rightXFraction: 0.80
    )

    // SolidStateGrid: 5-column layout with dividers, title + 2 rows of labels
    // Column positions and widths extracted by analyzing SolidStateCardAreas.png
    // Uses proportional font at fixed base size (scales with view)
    private static let solidGridLayout = GridCardLayout(
        titleFontSize: 14, gridFontSize: 16, bankFontSize: 14,
        titleYFraction: 0.38, titleWidthFraction: 0.90,
        gridY0Fraction: 0.62, gridY1Fraction: 0.84,
        xFractions: [0.097, 0.288, 0.478, 0.668, 0.859],
        cellWidthFraction: 0.186
    )

    // MARK: - Body

    var body: some View {
        if content != nil {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Use exact view dimensions to keep artwork and overlay coordinates aligned.
                    // SolidStateGrid uses the same image as SolidStateCard (just adds dividers)
                    let imageName = card.template == .solidStateGrid ? "SolidStateCard" : card.template.rawValue
                    Image(imageName)
                        .resizable()
                        .frame(width: w, height: h)

                    switch card.template {
                    case .cueCard:
                        gridCardContent(layout: Self.cueLayout, w: w, h: h)
                    case .magnetCard:
                        gridCardContent(layout: Self.magnetLayout, w: w, h: h)
                    case .solidState:
                        solidStateContent(layout: Self.solidLayout, w: w, h: h)
                    case .solidStateGrid:
                        solidStateGridContent(layout: Self.solidGridLayout, w: w, h: h)
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

    // MARK: - Grid card layout (cueCard + magnetCard)

    @ViewBuilder
    private func gridCardContent(layout: GridCardLayout, w: CGFloat, h: CGFloat) -> some View {
        let titleY = h * layout.titleYFraction
        let gridY0 = h * layout.gridY0Fraction
        let gridY1 = h * layout.gridY1Fraction

        // Title: width-constrained only — no height cap so the band height never shrinks the font.
        let titleAvailW = w * layout.titleWidthFraction
        let titleByWidth = card.title.isEmpty ? layout.titleFontSize
            : titleAvailW / (CGFloat(card.title.count) * 0.64)
        let titleFS = min(layout.titleFontSize, titleByWidth)

        // Bank badges: magnetCard only
        if card.template == .magnetCard {
            if let leftBank = card.banks.0 {
                Text("\(leftBank)")
                    .font(.system(size: layout.bankFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(width: w * 0.12, height: h * 0.15)
                    .clipped()
                    .position(x: w * 0.08, y: h * 0.14)
            }
            if let rightBank = card.banks.1 {
                Text("\(rightBank)")
                    .font(.system(size: layout.bankFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(width: w * 0.12, height: h * 0.15)
                    .clipped()
                    .position(x: w * 0.92, y: h * 0.14)
            }
        }

        Text(card.title)
            .font(.system(size: titleFS, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .frame(width: titleAvailW)
            .position(x: w / 2, y: titleY)

        // Labels are capped at titleFS so they never exceed the title.
        gridRow(row: 0, layout: layout, w: w, y: gridY0, cap: titleFS)
        gridRow(row: 1, layout: layout, w: w, y: gridY1, cap: titleFS)
    }

    @ViewBuilder
    private func gridRow(row: Int, layout: GridCardLayout, w: CGFloat, y: CGFloat, cap: CGFloat) -> some View {
        let base = row * 5
        let onlyFirst = !card.labels[base].isEmpty
            && (1..<5).allSatisfy { card.labels[base + $0].isEmpty }
        if onlyFirst {
            // Single label: span the full grid width, ignoring column dividers
            let fullWidth = w * (layout.xFractions[4] - layout.xFractions[0] + layout.cellWidthFraction)
            let centerX   = w * (layout.xFractions[0] + layout.xFractions[4]) / 2
            let label     = card.labels[base]
            let labelFS   = min(cap, label.isEmpty ? 0
                : min(layout.gridFontSize, fullWidth / (CGFloat(label.count) * 0.64)))
            Text(label)
                .font(.system(size: labelFS, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)
                .frame(width: fullWidth, alignment: .leading)
                .position(x: centerX, y: y)
        } else {
            let fontSize = min(cap, uniformFontSize(row: row, layout: layout, w: w))
            ForEach(0..<5, id: \.self) { col in
                Text(card.labels[base + col])
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .frame(width: w * layout.cellWidthFraction, alignment: .center)
                    .position(x: w * layout.xFractions[col], y: y)
            }
        }
    }

    // Compute the largest font size at which every non-empty label in the row fits its cell.
    // SF Mono Bold advance width ≈ 0.64 × font size (monospaced, so exact per character).
    private func uniformFontSize(row: Int, layout: GridCardLayout, w: CGFloat) -> CGFloat {
        let cellWidth = w * layout.cellWidthFraction
        var size = layout.gridFontSize
        let base = row * 5
        for col in 0..<5 {
            let label = card.labels[base + col]
            guard !label.isEmpty else { continue }
            let fitting = cellWidth / (CGFloat(label.count) * 0.64)
            if fitting < size { size = fitting }
        }
        return max(size, layout.gridFontSize * 0.4)
    }

    // MARK: - SolidStateCard layout

    @ViewBuilder
    private func solidStateContent(layout: SolidStateLayout, w: CGFloat, h: CGFloat) -> some View {
        let row1Y  = h * layout.row1YFraction
        let row2Y  = h * layout.row2YFraction
        let row3Y  = h * layout.row3YFraction
        // Right margin: same for both id and row2R, positioned left of yellow border
        let rightX = w * layout.rightXFraction
        let fs     = layout.fontSize

        // Program name row: title (left) and id (right, aligned with row2R)
        alignedText(card.title, fontSize: fs, align: .left,        x: w * 0.35, y: row1Y, width: w * 0.65)
        alignedText(card.id,    fontSize: fs, align: card.idAlign,  x: rightX,   y: row1Y, width: w * 0.25)

        // Row 1: full width
        alignedText(card.row1,  fontSize: fs, align: card.row1Align, x: w / 2,   y: row2Y, width: w * 0.9)

        // Row 2: left and right (same right margin as id)
        alignedText(card.row2,  fontSize: fs, align: card.row2Align,  x: w * 0.35, y: row3Y, width: w * 0.65)
        alignedText(card.row2R, fontSize: fs, align: card.row2RAlign, x: rightX,   y: row3Y, width: w * 0.25)
    }

    // MARK: - SolidStateGrid layout (grid with vertical dividers)

    private let invisibleMarker = "\u{200B}"  // Zero-width space marks columns as invisible/combined

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

            // Found a non-empty label, find how many columns it spans
            var spanEnd = i
            while spanEnd + 1 < 5 && (card.labels[base + spanEnd + 1].isEmpty) {
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
    private func solidStateGridContent(layout: GridCardLayout, w: CGFloat, h: CGFloat) -> some View {
        let titleY = h * layout.titleYFraction
        let gridY0 = h * layout.gridY0Fraction
        let gridY1 = h * layout.gridY1Fraction

        // Title: width-constrained, centered
        let titleAvailW = w * layout.titleWidthFraction
        let titleByWidth = card.title.isEmpty ? layout.titleFontSize
            : titleAvailW / (CGFloat(card.title.count) * 0.64)
        let titleFS = min(layout.titleFontSize, titleByWidth)

        // Scale font proportionally to view width
        // Reference: 800 pt width (iPad-like) → 16 pt labels, 17 pt title
        // Smaller screens get proportionally smaller fonts, with 10 pt minimum
        let scaleFactor = w / 800
        let fontSize = max(10, layout.gridFontSize * scaleFactor)
        let titleFontSize = max(11, (layout.gridFontSize + 1) * scaleFactor)

        Text(card.title)
            .font(.system(size: titleFontSize, weight: .bold))
            .foregroundColor(goldColor)
            .lineLimit(1)
            .frame(width: titleAvailW)
            .position(x: w / 2, y: titleY)

        // Compute spans before rendering
        let row0Spans = getColumnSpans(row: 0)
        let row1Spans = getColumnSpans(row: 1)

        // Render grid: 5 columns with dividers
        let dividerColor = Color(red: 188/255.0, green: 157/255.0, blue: 96/255.0)  // RGB(188, 157, 96)
        let dividerWidth: CGFloat = 1
        let dividerHeightRow = h * 0.202  // Full height of each row (measured: 89px / 440px)

        // Vertical dividers in top row
        let row0Dividers = dividersToDraw(for: row0Spans)
        ForEach(row0Dividers, id: \.self) { i in
            let x = w * ((layout.xFractions[i] + layout.xFractions[i + 1]) / 2)
            Rectangle()
                .fill(dividerColor)
                .frame(width: dividerWidth, height: dividerHeightRow)
                .position(x: x, y: gridY0)
        }

        // Vertical dividers in bottom row
        let row1Dividers = dividersToDraw(for: row1Spans)
        ForEach(row1Dividers, id: \.self) { i in
            let x = w * ((layout.xFractions[i] + layout.xFractions[i + 1]) / 2)
            Rectangle()
                .fill(dividerColor)
                .frame(width: dividerWidth, height: dividerHeightRow)
                .position(x: x, y: gridY1)
        }

        // Row 0 (labels[0:5]) - render with column spanning support
        ForEach(0..<row0Spans.count, id: \.self) { spanIdx in
            let span = row0Spans[spanIdx]
            let startCol = span.startCol
            let endCol = span.endCol
            let label = span.label

            // Calculate centered position and width for spanned columns
            let startX = w * layout.xFractions[startCol]
            let endX = w * layout.xFractions[endCol]
            let spanCenterX = (startX + endX) / 2
            let spanWidth = w * layout.cellWidthFraction * CGFloat(endCol - startCol + 1)

            Text(label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(goldColor)
                .lineLimit(1)
                .frame(width: spanWidth, alignment: .center)
                .position(x: spanCenterX, y: gridY0)
        }

        // Row 1 (labels[5:10]) - render with column spanning support
        ForEach(0..<row1Spans.count, id: \.self) { spanIdx in
            let span = row1Spans[spanIdx]
            let startCol = span.startCol
            let endCol = span.endCol
            let label = span.label

            // Calculate centered position and width for spanned columns
            let startX = w * layout.xFractions[startCol]
            let endX = w * layout.xFractions[endCol]
            let spanCenterX = (startX + endX) / 2
            let spanWidth = w * layout.cellWidthFraction * CGFloat(endCol - startCol + 1)

            Text(label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(goldColor)
                .lineLimit(1)
                .frame(width: spanWidth, alignment: .center)
                .position(x: spanCenterX, y: gridY1)
        }
    }

    // Compute the largest font size at which every non-empty label in the grid fits its cell.
    private func uniformGridFontSize(layout: GridCardLayout, w: CGFloat) -> CGFloat {
        let cellWidth = w * layout.cellWidthFraction
        var size = layout.gridFontSize
        for idx in 0..<10 {
            let label = card.labels[idx]
            guard !label.isEmpty else { continue }
            let fitting = cellWidth / (CGFloat(label.count) * 0.55)
            if fitting < size { size = fitting }
        }
        return max(size, layout.gridFontSize * 0.4)
    }

    @ViewBuilder
    private func alignedText(_ text: String, fontSize: CGFloat, align: TextAlign, x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        let swiftAlign: Alignment = align == .right ? .trailing : (align == .center ? .center : .leading)

        if card.style == .button {
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(goldColor)
                .lineLimit(1)
                .frame(width: width, alignment: swiftAlign)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .border(goldColor, width: 1)
                .position(x: x, y: y)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(goldColor)
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

        Text("SolidState (ML01)")
            .font(.headline)
        CueCardView(content: .ml01Default)
            .frame(height: 100)

        Text("SolidState (ML02 with math tokens)")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .solidState,
            title: "DETERMINANT, MATRIX, & SIMUL. EQ.",
            id: "ML-02",
            idAlign: .right,
            row1: "i: \u{2192} x\u{1D62} | \u{2192} A⁻¹ | j: \u{2192} a\u{1D62}\u{1D6A}⁻¹ || \u{2192} |A|, A⁻¹",
            row1Align: .center
        ))
        .frame(height: 100)

        Text("SolidStateGrid (ML02)")
            .font(.headline)
        CueCardView(content: CueCardContent(
            template: .solidStateGrid,
            title: "DETERMINANT, MATRIX, & SIMUL. EQ.",
            id: "ML-02",
            idAlign: .right,
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
