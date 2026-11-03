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
    var portraitTopInset: CGFloat = 0

    var body: some View {
        ZStack {
            Color(red: 29/255, green: 29/255, blue: 28/255)

            VStack(spacing: 0) {
                header
                paperStrip
                Spacer()
                buttonBar
                    .frame(height: 50)
            }
            .background(Color(white: 29.0/255.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
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
        HStack(spacing: 12) {
            Spacer()
            // Printer toggle button
            Button {
                viewModel.togglePrinterConnection()
            } label: {
                HStack(spacing: 6) {
                    Text("PC-100C")
                    Circle()
                        .fill(viewModel.printerConnected ? Color.red : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("PC-100C")
            .accessibilityValue(viewModel.printerConnected ? "On" : "Off")
            Spacer()
            // Dot / text toggle
            Button {
                dotMode.toggle()
            } label: {
                Image(systemName: dotMode ? "circle.grid.3x3.fill" : "text.alignleft")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8 + portraitTopInset).padding(.bottom, 8)
        .background(Color(white: 0.08))
    }

    // MARK: - Paper strip

    private var paperStrip: some View {
        ScrollView {
            if dotMode {
                dotStrip
            } else {
                textStrip
            }
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
        .background(Color(red: 0.96, green: 0.94, blue: 0.88))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color(white: 0.7), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    // MARK: - Dot strip

    private var dotStrip: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.printerLines.indices, id: \.self) { i in
                if viewModel.printerLines[i].isEmpty {
                    // PRT_FEED: manual says "half print line", but measured hardware spacing
                    // needs 2 dp more than the naive half-pitch — see feedHeightUnits.
                    Color.clear.aspectRatio(PrinterDotLine.widthUnits / PrinterDotLine.feedHeightUnits, contentMode: .fit)
                } else {
                    PrinterDotLine(line: i < viewModel.printerCodeLines.count ? viewModel.printerCodeLines[i] : .blank)
                }
            }
        }
        .padding(.horizontal, TIViewRules.printerPaperPaddingX)
        .padding(.vertical, TIViewRules.printerPaperPaddingY)
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
        GeometryReader { geo in
            // The narrow tape beside the debugger (iPhone Duo).
            let compact = TIViewRules.compactPrinterBar(geo.size.width)
            let printLabel = compact ? "PRN" : "PRINT"
            HStack(spacing: compact ? 6 : 12) {
                printerButton(printLabel, compact: compact) {
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
                    .printerButtonChrome(compact: compact, shade: 0.25)
                }
                .buttonStyle(.plain)

                printerButton("ADV", compact: compact) {
                    viewModel.pressPrinterAdv(true)
                } onRelease: {
                    viewModel.pressPrinterAdv(false)
                }

                Spacer(minLength: 0)

                Button { copyBoth() } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.printerLines.isEmpty)

                Button { copyBoth(); viewModel.cutPaper() } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.printerLines.isEmpty)
            }
            .buttonStyle(ChromeButtonStyle())
            .padding(.horizontal, compact ? 6 : 12)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(white: 0.15))
        }
    }

    // MARK: - Copy helper

    private func copyBoth() {
        let text = viewModel.printerLines.joined(separator: "\n")

        // Render bitmap at physical PC-100C size: dotPitchMM → points at 72 DPI.
        let dotPitchPt = PrinterDotLine.dotPitchMM * 72.0 / 25.4
        let lineW = PrinterDotLine.widthUnits  * dotPitchPt
        let feedH = PrinterDotLine.feedHeightUnits * dotPitchPt
        let lines     = viewModel.printerLines
        let codeLines = viewModel.printerCodeLines
        let strip = VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                if lines[i].isEmpty {
                    Color.white.frame(width: lineW, height: feedH)
                } else {
                    PrinterDotLine(line: i < codeLines.count ? codeLines[i] : .blank, dotColor: .black)
                    .background(Color.white)
                    .frame(width: lineW)
                }
            }
        }
        .background(Color.white)

        // 600 dpi, backed off for long tapes so the image fits the GPU texture limit
        // (Shared/PrinterFont.hpp copyPixelsPerUnit); cut-short lines count their rows only.
        let renderer = ImageRenderer(content: strip)
        renderer.scale = TIViewRules.printerCopyPixelsPerUnit(viewModel.printerStripHeightUnits) / dotPitchPt

        #if os(macOS)
        NSPasteboard.general.clearContents()
        var objects: [NSPasteboardWriting] = [text as NSString]
        if let nsImage = renderer.nsImage {
            objects.insert(nsImage, at: 0)  // image first so it is the primary item
        }
        NSPasteboard.general.writeObjects(objects)
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
        compact: Bool,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> some View {
        Text(label)
            .printerButtonChrome(compact: compact, shade: 0.28)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded   { _ in onRelease() }
            )
    }
}

// MARK: - Dot line renderer

/// One printed line's dot codes (Bridge TIPrinterLine).
struct PrinterCodeLine: Equatable {
    var codes: [UInt8]         // 20 raw character codes (0–63)
    var complete: Bool         // all 7 rows printed, followed by the paper advance
    var drawnRows: Int         // dot rows on paper (1–7)
    var inkedColumns: [UInt8]  // per row: font columns that got ink (Shared PrinterGeometry)
    var faintColumns: [UInt8]  // per row: faint dots, heating cut short
    var faintAlpha: Double     // ink of the faint dots

    static let blank = PrinterCodeLine(codes: Array(repeating: 0, count: 20), complete: true, drawnRows: 7,
                                       inkedColumns: Array(repeating: 0x1F, count: 7),
                                       faintColumns: Array(repeating: 0, count: 7), faintAlpha: 1)
}

extension PrinterCodeLine {
    init(_ t: TIPrinterLine) {
        self.init(codes: [UInt8](t.codes), complete: t.complete, drawnRows: t.drawnRows,
                  inkedColumns: [UInt8](t.inkedColumns), faintColumns: [UInt8](t.faintColumns),
                  faintAlpha: Double(t.faintAlpha))
    }
}

struct PrinterDotLine: View {
    let line: PrinterCodeLine
    private var codes: [UInt8] { line.codes }

    // Physical model of the PC-100C print head (measured; derivation in
    // Shared/PrinterFont.hpp PrinterGeometry, shared with the Qt6 app). Units
    // are dot pitches (dp): widthUnits includes ½ dp margins each side;
    // heightUnits is the full line pitch (7 dot rows + the stepper gap).
    static let charGap     = TIViewRules.printerCharGap
    static let dotPitchMM  = TIViewRules.printerDotPitchMM   // ≈ 0.430 mm — for physical-size copy
    static let widthUnits  = TIViewRules.printerWidthUnits   // ≈ 129.1 dp
    static let heightUnits = TIViewRules.printerHeightUnits  // 10.18 dp
    static let aspectRatio = widthUnits / heightUnits

    // A PRT_FEED blank line (one ROM-level ADV; the physical key issues two):
    // half a line plus 2 dp, as measured on a laser-printed copy.
    static let feedHeightUnits = TIViewRules.printerFeedHeightUnits

    var dotColor: Color = Color(white: 0.12)
    private static let dotRadiusFraction = TIViewRules.printerDotRadiusFraction  // of the dot pitch
    private static let interLineGap      = TIViewRules.printerInterLineGap       // ≈ 3.18 dp stepper advance


    // Dot-row model: each row is a separate Canvas with aspect ratio widthUnits:1
    // (one dot-pitch tall, full line width). This gives SwiftUI a concrete height per
    // row regardless of scroll context, avoiding the unreliable aspectRatio-on-Canvas
    // behaviour in an unconstrained LazyVStack.
    //
    // Complete lines append an inter-line gap spacer (3.18 dp) after row 6, matching
    // the stepper's paper advance. Partial lines have no spacer — the motor stopped hard.
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<line.drawnRows, id: \.self) { rowIdx in
                singleRow(rowIdx)
            }
            if line.complete {
                Color.clear
                    .aspectRatio(Self.widthUnits / Self.interLineGap, contentMode: .fit)
            }
        }
    }

    private func singleRow(_ rowIdx: Int) -> some View {
        Canvas { ctx, size in
            let dotPitch = size.width / Self.widthUnits
            let dotR     = dotPitch * Self.dotRadiusFraction
            let charStep = (5.0 + Self.charGap) * dotPitch
            let dotY     = size.height * 0.5  // vertically centred in the one-row canvas

            // A line cut short by the printer interrupt: the row in progress has
            // only its rightmost columns, the last of them possibly faint.
            let inked = line.inkedColumns[rowIdx], faint = line.faintColumns[rowIdx]
            for charIdx in 0..<min(codes.count, 20) {
                let bits = TISharedTables.printerFontRow(forCode: codes[charIdx], row: rowIdx) & inked
                let charX = Double(charIdx) * charStep
                for colIdx in 0..<5 {
                    let mask = UInt8(0x10 >> colIdx)
                    guard bits & mask != 0 else { continue }
                    let dotX = charX + (Double(colIdx) + 0.5) * dotPitch
                    let rect = CGRect(x: dotX - dotR, y: dotY - dotR,
                                      width: 2 * dotR, height: 2 * dotR)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(faint & mask != 0 ? dotColor.opacity(line.faintAlpha) : dotColor))
                }
            }
        }
        .aspectRatio(Self.widthUnits, contentMode: .fit)  // width:height = widthUnits:1
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
    vm.printerCodeLines = vm.printerLines.map { _ in .blank }
    return PrinterView()
        .environment(vm)
        .frame(width: 220, height: 400)
}

private extension View {
    /// The printer bar's button look; `compact` on the narrow tape.
    func printerButtonChrome(compact: Bool, shade: Double) -> some View {
        font(.caption.bold())
            .foregroundStyle(.white)
            .frame(minWidth: compact ? 30 : 36)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, 6)
            .background(Color(white: shade))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
