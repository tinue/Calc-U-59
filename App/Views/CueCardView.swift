import SwiftUI

struct CueCardView: View {
    let content: CueCardContent?

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
        titleFontSize: 16, gridFontSize: 9.5, bankFontSize: 16,
        titleYFraction: 0.399, gridY0Fraction: 0.632, gridY1Fraction: 0.862,
        xFractions: [0.101, 0.299, 0.494, 0.689, 0.884],
        cellWidthFraction: 0.16
    )

    // Derived from MagnetCard.png separator rows (px on 440px-high asset): separators≈100/223/331.
    private static let magnetLayout = GridCardLayout(
        titleFontSize: 12, gridFontSize: 10, bankFontSize: 16,
        titleYFraction: 0.385, gridY0Fraction: 0.635, gridY1Fraction: 0.875,
        xFractions: [0.097, 0.289, 0.481, 0.673, 0.874],
        cellWidthFraction: 0.16
    )

    private static let solidLayout = SolidStateLayout(
        fontSize: 12,
        row1YFraction: 0.38, row2YFraction: 0.62, row3YFraction: 0.84,
        rightXFraction: 0.80
    )

    // MARK: - Body

    var body: some View {
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
                    gridCardContent(layout: Self.cueLayout, w: w, h: h)
                case .magnetCard:
                    gridCardContent(layout: Self.magnetLayout, w: w, h: h)
                case .solidState:
                    solidStateContent(layout: Self.solidLayout, w: w, h: h)
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

    // MARK: - Grid card layout (cueCard + magnetCard)

    @ViewBuilder
    private func gridCardContent(layout: GridCardLayout, w: CGFloat, h: CGFloat) -> some View {
        let titleY   = h * layout.titleYFraction
        let gridY0   = h * layout.gridY0Fraction
        let gridY1   = h * layout.gridY1Fraction
        let cellWidth = w * layout.cellWidthFraction

        // Bank badges (magnetCard only — cueCard has nil banks)
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

        Text(card.title)
            .font(.system(size: layout.titleFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .position(x: w / 2, y: titleY)

        ForEach(0..<2, id: \.self) { row in
            ForEach(0..<5, id: \.self) { col in
                Text(card.labels[row * 5 + col])
                    .font(.system(size: layout.gridFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .frame(width: cellWidth, alignment: .center)
                    .position(x: w * layout.xFractions[col], y: row == 0 ? gridY0 : gridY1)
            }
        }
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

    @ViewBuilder
    private func alignedText(_ text: String, fontSize: CGFloat, align: TextAlign, x: CGFloat, y: CGFloat, width: CGFloat) -> some View {
        let swiftAlign: Alignment = align == .right ? .trailing : (align == .center ? .center : .leading)

        if card.style == .button {
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(goldColor)
                .lineLimit(1)
                .frame(width: width, alignment: swiftAlign)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .border(goldColor, width: 1)
                .position(x: x, y: y)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
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

        Text("Default (nil)")
            .font(.headline)
        CueCardView(content: nil)
            .frame(height: 100)
    }
    .padding()
}
