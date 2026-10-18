#include "CueCardRenderer.hpp"
#include "ChromeStyle.hpp"
#include <QFont>
#include <QFontMetricsF>
#include <QHash>
#include <QPainter>
#include <QPixmap>
#include <algorithm>

namespace CueCardRenderer {

namespace {

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
          const QColor& color, const cu59::CueCardGeometry* boxedBy = nullptr) {
    QFont f = boldFont(size);
    p.setFont(f);
    p.setPen(color);
    QFontMetricsF fm(f);
    QString shown = fm.elidedText(s, Qt::ElideRight, width);
    QRectF r(cx - width / 2, cy - fm.height() / 2, width, fm.height());
    p.drawText(r, align | Qt::AlignVCenter, shown);
    if (boxedBy) {
        p.setBrush(Qt::NoBrush);
        p.drawRect(r.adjusted(-boxedBy->buttonPadX, -boxedBy->buttonPadY, boxedBy->buttonPadX, boxedBy->buttonPadY));
    }
}

/// A MagnetCard bank number, clipped to its badge frame.
void badge(QPainter& p, int bank, const cu59::CueCardFrame& f, double size) {
    QRectF r(f.cx - f.width / 2, f.cy - f.height / 2, f.width, f.height);
    p.save();
    p.setClipRect(r, Qt::IntersectClip);
    p.setFont(boldFont(size));
    p.setPen(Qt::black);
    p.drawText(r, Qt::AlignCenter, QString::number(bank));
    p.restore();
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
    const cu59::CueCardGeometry g = cu59::cueCardGeometry(card, w, h);
    const QColor ink = ChromeStyle::fromRgb(cu59::cueCardInk(card));
    const cu59::CueCardGeometry* boxed = card.style == cu59::CardButtonStyle::Button ? &g : nullptr;

    const QString title = QString::fromStdString(card.title);
    if (L.hasId) {
        text(p, title, g.titleFontSize, Qt::AlignLeft, g.gridCenter, g.titleY, g.gridWidth, ink);
        if (!card.id.empty())
            text(p, QString::fromStdString(card.id), g.titleFontSize, Qt::AlignRight, g.gridCenter, g.titleY, g.gridWidth, ink);
    } else {
        text(p, title, g.titleFontSize, Qt::AlignHCenter, w / 2, g.titleY, g.titleWidth, ink);
    }

    if (card.template_ == cu59::CueCardTemplate::MagnetCard) {
        if (card.bankLeft) badge(p, *card.bankLeft, g.bankLeft, g.bankFontSize);
        if (card.bankRight) badge(p, *card.bankRight, g.bankRight, g.bankFontSize);
    }

    auto gridRow = [&](int row, double y) {
        auto spans = cu59::labelSpans(card, row);
        if (spans.empty()) return;
        double fs = cu59::cellFittingFontSize(spans, L, w, g.gridFontSize);
        if (L.drawsDividers) {
            for (int i : cu59::dividersBetween(spans)) {
                double x = cu59::cueCardDividerX(L, i, w);
                p.fillRect(QRectF(x - 0.5, y - g.dividerHeight / 2, 1, g.dividerHeight), ChromeStyle::fromRgb(cu59::kCueCardDividerColor));
            }
        }
        for (const auto& s : spans) {
            cu59::CueCardFrame f = cu59::cueCardSpanFrame(L, s, y, w);
            text(p, QString::fromStdString(s.label), fs, Qt::AlignHCenter, f.cx, f.cy, f.width, ink);
        }
    };

    // Top row: Row1 text, or the A′–E′ grid.
    if (!card.row1.empty())
        text(p, QString::fromStdString(card.row1), g.gridFontSize, qtAlign(card.row1Align), g.gridCenter, g.gridY0, g.gridWidth, ink, boxed);
    else gridRow(0, g.gridY0);

    // Bottom row: Row2 / Row2R text, or the A–E grid.
    if (!card.row2.empty() || !card.row2R.empty()) {
        if (card.row2R.empty()) {
            text(p, QString::fromStdString(card.row2), g.gridFontSize, qtAlign(card.row2Align), g.gridCenter, g.gridY1, g.gridWidth, ink, boxed);
        } else {
            text(p, QString::fromStdString(card.row2), g.gridFontSize, qtAlign(card.row2Align), g.row2Left.cx, g.row2Left.cy,
                 g.row2Left.width, ink, boxed);
            text(p, QString::fromStdString(card.row2R), g.gridFontSize, qtAlign(card.row2RAlign), g.row2Right.cx, g.row2Right.cy,
                 g.row2Right.width, ink, boxed);
        }
    } else {
        gridRow(1, g.gridY1);
    }

    p.fillRect(QRectF(0, 0, w, g.washHeight), ChromeStyle::fromRgb(cu59::kCueCardWashColor, cu59::kCueCardWashAlpha));
    p.restore();
}

} // namespace CueCardRenderer
