import SwiftUI

struct CueCardView: View {
    let content: CueCardContent?

    private var card: CueCardContent {
        content ?? CueCardContent.ml01Default
    }

    private let goldColor = Color(red: 0xC4/255, green: 0x92/255, blue: 0x23/255)

    var body: some View {
        ZStack {
            // Template background
            Image(card.template.rawValue)
                .resizable()
                .scaledToFill()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

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
        let titleY = h * 0.18
        let gridY0 = h * 0.50
        let gridY1 = h * 0.75
        let titleFontSize: CGFloat = 16
        let gridFontSize: CGFloat = 9.5

        // Title row
        Text(card.title)
            .font(.system(size: titleFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .position(x: w / 2, y: titleY)

        // Grid row 0: A–E
        let xPositions = [0.10, 0.30, 0.50, 0.70, 0.90]
        ForEach(0..<5, id: \.self) { i in
            VStack(spacing: 0) {
                Text(card.labels[i])
                    .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: w * 0.15, height: h * 0.09)
            .clipped()
            .position(x: w * xPositions[i], y: gridY0)
        }

        // Grid row 1: A'–E'
        ForEach(0..<5, id: \.self) { i in
            VStack(spacing: 0) {
                Text(card.labels[5 + i])
                    .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: w * 0.15, height: h * 0.09)
            .clipped()
            .position(x: w * xPositions[i], y: gridY1)
        }
    }

    // MARK: - MagnetCard layout

    @ViewBuilder
    private func magnetCardContent(w: CGFloat, h: CGFloat) -> some View {
        let bankFontSize: CGFloat = 16
        let titleY = h * 0.32
        let gridY0 = h * 0.53
        let gridY1 = h * 0.75
        let titleFontSize: CGFloat = 12
        let gridFontSize: CGFloat = 10

        // Left bank badge
        if let leftBank = card.banks.0 {
            Text("\(leftBank)")
                .font(.system(size: bankFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: w * 0.12, height: h * 0.15)
                .clipped()
                .position(x: w * 0.08, y: h * 0.12)
        }

        // Right bank badge
        if let rightBank = card.banks.1 {
            Text("\(rightBank)")
                .font(.system(size: bankFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: w * 0.12, height: h * 0.15)
                .clipped()
                .position(x: w * 0.92, y: h * 0.12)
        }

        // Title row
        Text(card.title)
            .font(.system(size: titleFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
            .lineLimit(1)
            .position(x: w / 2, y: titleY)

        // Grid row 0: A–E
        let xPositions = [0.10, 0.30, 0.50, 0.70, 0.90]
        ForEach(0..<5, id: \.self) { i in
            VStack(spacing: 0) {
                Text(card.labels[i])
                    .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: w * 0.15, height: h * 0.09)
            .clipped()
            .position(x: w * xPositions[i], y: gridY0)
        }

        // Grid row 1: A'–E'
        ForEach(0..<5, id: \.self) { i in
            VStack(spacing: 0) {
                Text(card.labels[5 + i])
                    .font(.system(size: gridFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: w * 0.15, height: h * 0.09)
            .clipped()
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
