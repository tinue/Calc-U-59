import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PrinterView: View {
    @Environment(EmulatorViewModel.self) var viewModel
    @State private var dotMode = true
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            header
            paperStrip
            buttonBar
        }
        .background(Color(white: 0.12))
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("Copied to clipboard")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 48)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Text("PC-100C")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            // Dot / text toggle
            Button {
                dotMode.toggle()
            } label: {
                Image(systemName: dotMode ? "circle.grid.3x3.fill" : "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.trailing, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .background(Color(white: 0.08))
    }

    // MARK: - Paper strip

    private var paperStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if dotMode {
                    dotStrip
                } else {
                    textStrip
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .scrollIndicators(.hidden)
            .background(Color(red: 0.96, green: 0.94, blue: 0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color(white: 0.7), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .onChange(of: viewModel.printerLines.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Dot strip

    private var dotStrip: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.printerLines.indices, id: \.self) { i in
                if viewModel.printerLines[i].isEmpty {
                    // PRT_FEED: one blank line pitch
                    Color.clear.aspectRatio(PrinterDotLine.aspectRatio, contentMode: .fit)
                } else {
                    PrinterDotLine(
                        codes: i < viewModel.printerCodeLines.count
                            ? [UInt8](viewModel.printerCodeLines[i])
                            : [UInt8](repeating: 0, count: 20)
                    )
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Text strip (fallback / copy-paste mode)

    private var textStrip: some View {
        Text(viewModel.printerLines.isEmpty ? " " : viewModel.printerLines.joined(separator: "\n"))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Color(white: 0.15))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .textSelection(.enabled)
            .id(viewModel.printerClearID)
    }

    // MARK: - Hardware button bar

    private var buttonBar: some View {
        HStack(spacing: 12) {
            printerButton("PRINT") {
                viewModel.pressPrinterPrint(true)
            } onRelease: {
                viewModel.pressPrinterPrint(false)
            }

            Button {
                viewModel.togglePrinterTrace()
            } label: {
                HStack(spacing: 4) {
                    Text("T")
                    Circle()
                        .fill(viewModel.printerTrace ? Color.red : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(minWidth: 36)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            printerButton("ADV") {
                viewModel.pressPrinterAdv(true)
            } onRelease: {
                viewModel.pressPrinterAdv(false)
            }

            Spacer(minLength: 0)

            Button { copyBoth() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption.bold())
                    .frame(width: 16)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.printerLines.isEmpty)

            Button { copyBoth(); viewModel.cutPaper() } label: {
                Image(systemName: "scissors")
                    .font(.caption.bold())
                    .frame(width: 16)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.printerLines.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }

    // MARK: - Copy helper

    private func copyBoth() {
        let text = viewModel.printerLines.joined(separator: "\n")

        // Render bitmap at physical PC-100C size: dotPitchMM → points at 72 DPI.
        let dotPitchPt = PrinterDotLine.dotPitchMM * 72.0 / 25.4
        let lineW = PrinterDotLine.widthUnits  * dotPitchPt
        let lineH = PrinterDotLine.heightUnits * dotPitchPt
        let lines     = viewModel.printerLines
        let codeLines = viewModel.printerCodeLines
        let strip = VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                Group {
                    if lines[i].isEmpty {
                        Color.white
                    } else {
                        PrinterDotLine(
                            codes: i < codeLines.count
                                ? [UInt8](codeLines[i])
                                : [UInt8](repeating: 0, count: 20),
                            dotColor: .black
                        )
                        .background(Color.white)
                    }
                }
                .frame(width: lineW, height: lineH)
            }
        }
        .background(Color.white)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 600.0 / 72.0  // 600 DPI — crisp on a laser printer, physical size preserved

        #if os(macOS)
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        NSPasteboard.general.writeObjects([item])
        #else
        var pbItem: [String: Any] = [UTType.utf8PlainText.identifier: text]
        if let image = renderer.uiImage, let png = image.pngData() {
            pbItem[UTType.png.identifier] = png
        }
        UIPasteboard.general.items = [pbItem]
        #endif

        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            showCopiedToast = false
        }
    }

    // MARK: - Press-and-hold button helper

    @ViewBuilder
    private func printerButton(
        _ label: String,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(minWidth: 36)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.28))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded   { _ in onRelease() }
            )
    }
}

// MARK: - Dot line renderer

struct PrinterDotLine: View {
    let codes: [UInt8]  // 20 raw character codes (0–63)

    // Physical model — derived from measured PC-100C print head:
    //   total span (first dot centre → last dot centre) = 55 mm
    //   5-dot character span (col 0 → col 4 centre)     = 1.9 mm  → 4 × dotPitch
    //   inter-char gap (col 4 centre → col 0 centre)    = 1.2 mm  → (1 + charGap) × dotPitch
    //
    //   Raw: dotPitch = 1.9/4 = 0.475 mm, charGap = 1.2/0.475 − 1 = 1.526
    //   Local measurements give total = 60.8 mm; scale dotPitch down to match 55 mm:
    //   dotPitchMM = 55 / (99 + 19 × 1.526) = 0.430 mm  (charGap ratio preserved)
    //
    //   widthUnits: canvas width expressed in dotPitch units (includes half-pitch margins)
    //   The rightmost dot centre is at (99 + 19×charGap) × dotPitch; canvas adds 0.5 dp margin
    //   each side → widthUnits = 100 + 19 × charGap.
    //
    //   Vertical pitch — from 10-line measurement top-pixel to bottom-pixel = 42.3 mm:
    //   lineHeight_mm = (6.88 − 0.12) × dotPitchMM = 2.906 mm  (first/last dot outer edges)
    //   linePitch_mm  = (42.3 − 2.906) / 9 = 4.377 mm = 10.18 × dotPitchMM
    //   heightUnits   = 10.18  (7 dot rows + 3.18 dp inter-line gap baked in below)
    static let charGap     = 1.53
    static let dotPitchMM  = 55.0 / (99.0 + 19.0 * charGap)   // 0.430 mm — for physical-size copy
    static let widthUnits  = 100.0 + 19.0 * charGap            // ≈ 129.1 dp
    static let heightUnits = 10.18                              // 7 dot rows + inter-line gap
    static let aspectRatio = widthUnits / heightUnits

    var dotColor: Color = Color(white: 0.12)
    private static let dotRadiusFraction = 0.38  // dot radius as fraction of dotPitch

    var body: some View {
        Canvas { ctx, size in
            let dotPitch  = size.width / Self.widthUnits
            let dotR      = dotPitch * Self.dotRadiusFraction
            let charStep  = (5.0 + Self.charGap) * dotPitch  // first-col to first-col of next char

            for charIdx in 0..<min(codes.count, 20) {
                let fontRows = pc100cFont[Int(codes[charIdx])]
                let charX    = Double(charIdx) * charStep

                for rowIdx in 0..<7 {
                    let bits = fontRows[rowIdx]
                    let dotY = (Double(rowIdx) + 0.5) * dotPitch

                    for colIdx in 0..<5 {
                        guard bits & (0x10 >> colIdx) != 0 else { continue }
                        let dotX = charX + (Double(colIdx) + 0.5) * dotPitch
                        let rect = CGRect(x: dotX - dotR, y: dotY - dotR,
                                          width: 2 * dotR, height: 2 * dotR)
                        ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }
}

// MARK: - Preview

#Preview {
    let vm = EmulatorViewModel()
    vm.printerLines = [
        "  -3.1415926536",
        "   1.2345678901",
        "",
        "   SIN",
        "   0.",
    ]
    // Provide zero-filled code lines so the preview renders blank dot rows
    // (good enough to check layout; real codes come from the emulator).
    vm.printerCodeLines = vm.printerLines.map { _ in Data(count: 20) }
    return PrinterView()
        .environment(vm)
        .frame(width: 220, height: 400)
}
