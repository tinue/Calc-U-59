import SwiftUI

struct CueCardView: View {
    let content: CueCardContent?

    private var card: CueCardContent {
        content ?? CueCardContent.ml01Default
    }

    private let goldColor = Color(red: 0xC4/255, green: 0x92/255, blue: 0x23/255)

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
                    cueCardContent(w: w, h: h)
                case .magnetCard:
                    magnetCardContent(w: w, h: h)
                case .solidState:
                    solidStateContent(w: w, h: h)
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

    // MARK: - CueCard layout

    @ViewBuilder
    private func cueCardContent(w: CGFloat, h: CGFloat) -> some View {
        // CueCard uses three visible text bands in this order:
        // title (124..227), row1 (227..329), row2 (329..430).
        // Keep anchors at each band's center to avoid per-device drift.
        let titleY = h * 0.399
        let gridY0 = h * 0.632
        let gridY1 = h * 0.862
        let titleFontSize: CGFloat = 16
        let gridFontSize: CGFloat = 9.5
        let cellWidth = w * 0.16

        // Title row
        Text(card.title)
            .font(.system(size: titleFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .position(x: w / 2, y: titleY)

        // CueCard template column centers.
        let xPositions = [0.101, 0.299, 0.494, 0.689, 0.884]
        ForEach(0..<5, id: \.self) { i in
            Text(card.labels[i])
                .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(width: cellWidth, alignment: .center)
                .position(x: w * xPositions[i], y: gridY0)
        }

        // Grid row 1: A'–E'
        ForEach(0..<5, id: \.self) { i in
            Text(card.labels[5 + i])
                .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(width: cellWidth, alignment: .center)
                .position(x: w * xPositions[i], y: gridY1)
        }
    }

    // MARK: - MagnetCard layout

    @ViewBuilder
    private func magnetCardContent(w: CGFloat, h: CGFloat) -> some View {
        let bankFontSize: CGFloat = 16
        // Derived from MagnetCard.png separator rows (px on 440px-high asset):
        // separators≈100/223/331. Place text at each row band's center.
        let titleY = h * 0.385
        let gridY0 = h * 0.635
        let gridY1 = h * 0.875
        let titleFontSize: CGFloat = 12
        let gridFontSize: CGFloat = 10
        let cellWidth = w * 0.16

        // Left bank badge
        if let leftBank = card.banks.0 {
            Text("\(leftBank)")
                .font(.system(size: bankFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: w * 0.12, height: h * 0.15)
                .clipped()
                .position(x: w * 0.08, y: h * 0.14)
        }

        // Right bank badge
        if let rightBank = card.banks.1 {
            Text("\(rightBank)")
                .font(.system(size: bankFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: w * 0.12, height: h * 0.15)
                .clipped()
                .position(x: w * 0.92, y: h * 0.14)
        }

        // Title row
        Text(card.title)
            .font(.system(size: titleFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .position(x: w / 2, y: titleY)

        // MagnetCard template column centers (measured from its own divider lines).
        // (x px approx: 0, 399, 796, 1191, 1587, 2022 on 2064px asset).
        let xPositions = [0.097, 0.289, 0.481, 0.673, 0.874]
        ForEach(0..<5, id: \.self) { i in
            Text(card.labels[i])
                .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(width: cellWidth, alignment: .center)
                .position(x: w * xPositions[i], y: gridY0)
        }

        // Grid row 1: A'–E'
        ForEach(0..<5, id: \.self) { i in
            Text(card.labels[5 + i])
                .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(width: cellWidth, alignment: .center)
                .position(x: w * xPositions[i], y: gridY1)
        }
    }

    // MARK: - SolidStateCard layout

    @ViewBuilder
    private func solidStateContent(w: CGFloat, h: CGFloat) -> some View {
        let fontSize: CGFloat = 12
        let row1Y = h * 0.38
        let row2Y = h * 0.62
        let row3Y = h * 0.84
        // Right margin: same for both id and row2R, positioned left of yellow border
        let rightX = w * 0.80

        // Program name row: title (left) and id (right, aligned with row2R)
        alignedText(card.title, fontSize: fontSize, align: .left, x: w * 0.35, y: row1Y, width: w * 0.65)

        alignedText(card.id, fontSize: fontSize, align: card.idAlign, x: rightX, y: row1Y, width: w * 0.25)

        // Row 1: full width
        alignedText(card.row1, fontSize: fontSize, align: card.row1Align, x: w / 2, y: row2Y, width: w * 0.9)

        // Row 2: left and right (same right margin as id)
        alignedText(card.row2, fontSize: fontSize, align: card.row2Align, x: w * 0.35, y: row3Y, width: w * 0.65)

        alignedText(card.row2R, fontSize: fontSize, align: card.row2RAlign, x: rightX, y: row3Y, width: w * 0.25)
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
