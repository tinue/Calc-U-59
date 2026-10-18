#include "CueCardRenderer.hpp"
#include <QFont>
#include <QFontMetricsF>
#include <QHash>
#include <QPainter>
#include <QPixmap>
#include <algorithm>

namespace CueCardRenderer {

namespace {

const QColor kGold(0xC4, 0x92, 0x23);       // printed SolidState ink
const QColor kDivider(188, 157, 96);
const QColor kSharpie(112, 42, 72);         // alternate inks (PencilColor:), distinct from
const QColor kPencil(0x4A, 0x47, 0x44);     // the template's near-black divider lines

QColor inkColor(cu59::CueCardInkColor c) {
    switch (c) {
    case cu59::CueCardInkColor::Pencil: return kPencil;
    case cu59::CueCardInkColor::Sharpie: return kSharpie;
    default: return Qt::black;
    }
}

const QPixmap& artwork(cu59::CueCardTemplate t) {
    static QHash<int, QPixmap> cache;
    int key = static_cast<int>(t);
    if (!cache.contains(key)) cache.insert(key, QPixmap(QStringLiteral(":/img/%1.png").arg(cu59::toString(t))));
    return cache[key];
}

QFont boldFont(double pixelSize) {
    QFont f;
    f.setBold(true);
    f.setPixelSize(std::max(1, static_cast<int>(std::lround(pixelSize))));
    return f;
}

/// One line of text in a frame `width` wide centred at (cx, cy), elided like
/// SwiftUI's lineLimit(1).
void text(QPainter& p, const QString& s, double size, Qt::Alignment align, double cx, double cy, double width,
          const QColor& color, bool boxed = false) {
    QFont f = boldFont(size);
    p.setFont(f);
    p.setPen(color);
    QFontMetricsF fm(f);
    QString shown = fm.elidedText(s, Qt::ElideRight, width);
    QRectF r(cx - width / 2, cy - fm.height() / 2, width, fm.height());
    p.drawText(r, align | Qt::AlignVCenter, shown);
    if (boxed) {
        p.setBrush(Qt::NoBrush);
        p.drawRect(r.adjusted(-4, -2, 4, 2));
    }
}

Qt::Alignment qtAlign(cu59::TextAlign a) {
    return a == cu59::TextAlign::Right ? Qt::AlignRight : a == cu59::TextAlign::Center ? Qt::AlignHCenter : Qt::AlignLeft;
}

} // namespace

void paint(QPainter& p, const QRectF& rect, const cu59::CueCardContent& card) {
    p.save();
    p.setClipRect(rect);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    p.drawPixmap(rect, artwork(card.template_), QRectF());

    const double w = rect.width(), h = rect.height();
    p.translate(rect.topLeft());
    const cu59::CueCardLayout& L = cu59::cueCardLayout(card.template_);
    const double titleY = h * L.titleYFraction, gridY0 = h * L.gridY0Fraction, gridY1 = h * L.gridY1Fraction;
    const double scale = w / L.referenceWidth;
    const double gridFS = L.gridFontSize * scale, titleFS0 = L.titleFontSize * scale, bankFS = L.bankFontSize * scale;

    const QString title = QString::fromStdString(card.title);
    const double titleAvailW = w * L.titleWidthFraction;
    const double titleFS = card.title.empty()
        ? titleFS0
        : std::min(titleFS0, titleAvailW / (cu59::displayLength(card.title) * 0.64));

    // Content rows: geometry from the grid font size, independent of the title.
    const double charW = gridFS * 0.64;
    const double gridLeft = w * (L.xFractions[0] - L.cellWidthFraction / 2) + charW * 0.5;
    const double gridRight = w * (L.xFractions[4] + L.cellWidthFraction / 2) - charW * 1.0;
    const double gridWidth = gridRight - gridLeft, gridCenter = (gridLeft + gridRight) / 2;

    // SolidState cards are printed (gold); CueCard/MagnetCard ink follows PencilColor:.
    const QColor ink = L.drawsDividers ? kGold : inkColor(card.color);
    const bool boxed = card.style == cu59::CardButtonStyle::Button;

    if (L.hasId) {
        text(p, title, titleFS, Qt::AlignLeft, gridCenter, titleY, gridWidth, ink);
        if (!card.id.empty()) text(p, QString::fromStdString(card.id), titleFS, Qt::AlignRight, gridCenter, titleY, gridWidth, ink);
    } else {
        text(p, title, titleFS, Qt::AlignHCenter, w / 2, titleY, titleAvailW, ink);
    }

    if (card.template_ == cu59::CueCardTemplate::MagnetCard) {
        if (card.bankLeft) text(p, QString::number(*card.bankLeft), bankFS, Qt::AlignHCenter, w * 0.08, h * 0.14, w * 0.12, Qt::black);
        if (card.bankRight) text(p, QString::number(*card.bankRight), bankFS, Qt::AlignHCenter, w * 0.92, h * 0.14, w * 0.12, Qt::black);
    }

    auto gridRow = [&](int row, double y) {
        auto spans = cu59::labelSpans(card, row);
        if (spans.empty()) return;
        double fs = cu59::cellFittingFontSize(spans, L, w, gridFS);
        if (L.drawsDividers) {
            for (int i : cu59::dividersBetween(spans)) {
                double x = w * (L.xFractions[i] + L.xFractions[i + 1]) / 2;
                p.fillRect(QRectF(x - 0.5, y - h * 0.101, 1, h * 0.202), kDivider);
            }
        }
        for (const auto& s : spans) {
            double cx = w * (L.xFractions[s.startCol] + L.xFractions[s.endCol]) / 2;
            double spanW = w * L.cellWidthFraction * (s.endCol - s.startCol + 1);
            text(p, QString::fromStdString(s.label), fs, Qt::AlignHCenter, cx, y, spanW, ink);
        }
    };

    // Top row: Row1 text, or the A′–E′ grid.
    if (!card.row1.empty()) text(p, QString::fromStdString(card.row1), gridFS, qtAlign(card.row1Align), gridCenter, gridY0, gridWidth, ink, boxed);
    else gridRow(0, gridY0);

    // Bottom row: Row2 / Row2R text, or the A–E grid.
    if (!card.row2.empty() || !card.row2R.empty()) {
        if (card.row2R.empty()) {
            text(p, QString::fromStdString(card.row2), gridFS, qtAlign(card.row2Align), gridCenter, gridY1, gridWidth, ink, boxed);
        } else {
            double leftW = gridWidth * 0.70, rightW = gridWidth * 0.30;
            text(p, QString::fromStdString(card.row2), gridFS, qtAlign(card.row2Align), gridLeft + leftW / 2, gridY1, leftW, ink, boxed);
            text(p, QString::fromStdString(card.row2R), gridFS, qtAlign(card.row2RAlign), gridRight - rightW / 2, gridY1, rightW, ink, boxed);
        }
    } else {
        gridRow(1, gridY1);
    }

    // Top wash: 28 % of the card height.
    p.fillRect(QRectF(0, 0, w, h * 0.28), QColor::fromRgbF(0.1, 0.02, 0.02, 0.4));
    p.restore();
}

} // namespace CueCardRenderer
