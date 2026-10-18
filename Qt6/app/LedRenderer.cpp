#include "LedRenderer.hpp"
#include "SevenSegment.hpp"
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QPolygonF>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace LedRenderer {

namespace {

/// Three box-blur passes in each direction ≈ a Gaussian of the given radius,
/// on a premultiplied ARGB32 image (what SwiftUI's .blur(radius:) does).
void blur(QImage& img, double radius) {
    int r = std::max(1, static_cast<int>(std::lround(radius / 1.7)));
    const int w = img.width(), h = img.height();
    std::vector<uint32_t> tmp(static_cast<size_t>(std::max(w, h)));
    auto pass = [&](uint32_t* line, int n, int stride) {
        for (int i = 0; i < n; ++i) tmp[static_cast<size_t>(i)] = line[i * stride];
        uint32_t acc[4] = {0, 0, 0, 0};
        auto add = [&](uint32_t px, int sign) {
            for (int c = 0; c < 4; ++c) acc[c] += static_cast<uint32_t>(sign) * ((px >> (c * 8)) & 0xFF);
        };
        int window = 2 * r + 1;
        for (int i = -r; i <= r; ++i) add(tmp[static_cast<size_t>(std::clamp(i, 0, n - 1))], 1);
        for (int i = 0; i < n; ++i) {
            uint32_t out = 0;
            for (int c = 0; c < 4; ++c) out |= ((acc[c] / static_cast<uint32_t>(window)) & 0xFF) << (c * 8);
            line[i * stride] = out;
            add(tmp[static_cast<size_t>(std::clamp(i - r, 0, n - 1))], -1);
            add(tmp[static_cast<size_t>(std::clamp(i + r + 1, 0, n - 1))], 1);
        }
    };
    for (int k = 0; k < 3; ++k) {
        for (int y = 0; y < h; ++y) pass(reinterpret_cast<uint32_t*>(img.scanLine(y)), w, 1);
        auto* base = reinterpret_cast<uint32_t*>(img.bits());
        int stride = img.bytesPerLine() / 4;
        for (int x = 0; x < w; ++x) pass(base + x, h, stride);
    }
}

QColor rgba(double r, double g, double b, double a) { return QColor::fromRgbF(r, g, b, a); }

/// One lit shape with its opacity (the "C" annunciator fades).
struct Lit { QPainterPath path; double opacity; };

} // namespace

namespace {

void render(QPainter& p, const QRectF& rect, const DisplaySnapshot& d, double calcOpacity, cu59::LedStyle style) {
    const cu59::LedStyleParams& sp = cu59::ledStyleParams(style);
    p.fillRect(rect, rgba(cu59::kLedBackgroundR, cu59::kLedBackgroundG, cu59::kLedBackgroundB, 1));
    const double w = rect.width() / 12.0, h = rect.height();
    const QColor active = rgba(sp.activeR, sp.activeG, sp.activeB, 1);
    const QColor inactive = rgba(sp.inactiveR, sp.inactiveG, sp.inactiveB, sp.inactiveAlpha);

    std::vector<Lit> lit;          // segments to glow and draw lit
    QPainterPath dark;             // unlit segments
    std::vector<QRectF> dps;       // decimal points (unsheared)
    double glowRadius = 0;

    const auto modern = cu59::modernizedSegments(w, h);
    const auto classic = cu59::classicSegments(w, h);
    for (int i = 0; i < 12; ++i) {
        const double x = rect.left() + (11 - i) * w;
        uint8_t segs;
        double opacity = 1.0;
        if (i == 11 && calcOpacity > 0) {
            segs = cu59::kSegmentsC;
            opacity = calcOpacity;
        } else {
            segs = cu59::segmentsFor(d.digits[i], d.ctrl[i], ((d.suppressedMask >> i) & 1) != 0);
        }
        // Shear x' = x + slant × (h − y): the bottom stays put.
        QTransform t(1, 0, -sp.slant, 1, x + h * sp.slant, rect.top());
        for (int bit = 0; bit < 7; ++bit) {
            QPainterPath path;
            if (style == cu59::LedStyle::Modernized) {
                QPolygonF poly;
                for (const auto& pt : modern[static_cast<size_t>(bit)]) poly << QPointF(pt.x, pt.y);
                path.addPolygon(poly);
                path.closeSubpath();
                glowRadius = cu59::modernizedSegmentWidth(w);
            } else {
                const auto& seg = classic[static_cast<size_t>(bit)];
                for (const auto& c : seg.centres) path.addEllipse(QPointF(c.x, c.y), seg.radius, seg.radius);
                glowRadius = std::max(glowRadius, seg.radius);
            }
            path = t.map(path);
            if ((segs >> bit) & 1) lit.push_back({path, opacity});
            else dark.addPath(path);
        }
        if ((d.dpAfterglowMask >> i) & 1) {
            cu59::LedDot dot = cu59::decimalPoint(w, h);
            dps.emplace_back(x + dot.cx - dot.diameter / 2, rect.top() + dot.cy - dot.diameter / 2, dot.diameter, dot.diameter);
        }
    }

    p.save();
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(Qt::NoPen);
    p.fillPath(dark, inactive);

    // Glow layers, rendered offscreen at device resolution and blurred.
    const qreal dpr = p.device() ? p.device()->devicePixelRatioF() : 1.0;
    auto glowLayer = [&](double blurRadius, double layerOpacity, bool decimalPoints) {
        QImage img((rect.size() * dpr).toSize(), QImage::Format_ARGB32_Premultiplied);
        if (img.isNull()) return;
        img.setDevicePixelRatio(dpr);
        img.fill(Qt::transparent);
        QPainter g(&img);
        g.setRenderHint(QPainter::Antialiasing);
        g.setPen(Qt::NoPen);
        g.translate(-rect.topLeft());
        if (decimalPoints) {
            for (const auto& r : dps) g.setBrush(active), g.drawEllipse(r);
        } else {
            for (const auto& l : lit) {
                QColor c = active;
                c.setAlphaF(l.opacity);
                g.fillPath(l.path, c);
            }
        }
        g.end();
        blur(img, blurRadius * dpr);
        p.setOpacity(layerOpacity);
        p.drawImage(rect.topLeft(), img);
        p.setOpacity(1.0);
    };
    if (!lit.empty()) {
        if (style == cu59::LedStyle::Modernized) {
            glowLayer(glowRadius * sp.glowBlurPerWidth, sp.glowOpacity, false);
            glowLayer(glowRadius * sp.bloomBlurPerWidth, 1.0, false);
        } else {
            glowLayer(glowRadius * sp.glowBlurPerWidth, sp.glowOpacity, false);
        }
    }
    if (!dps.empty()) glowLayer(dps.front().width() * cu59::kDecimalGlowBlurPerDiameter, cu59::kDecimalGlowOpacity, true);

    for (const auto& l : lit) {
        QColor c = active;
        c.setAlphaF(l.opacity);
        p.fillPath(l.path, c);
    }
    p.setBrush(active);
    for (const auto& r : dps) p.drawEllipse(r);
    p.restore();
}

/// Rendered displays by everything they depend on. The blurred glow is the
/// costly part; a static display, or a running program's C indicator cycling
/// through its opacities, comes from here.
struct CacheKey {
    DisplaySnapshot display;
    int opacityStep;   ///< C indicator opacity in 1/64 steps
    int style;
    QSize pixels;
    bool operator==(const CacheKey& o) const {
        return std::memcmp(&display.digits, &o.display.digits, sizeof display.digits) == 0 &&
               std::memcmp(&display.ctrl, &o.display.ctrl, sizeof display.ctrl) == 0 &&
               display.suppressedMask == o.display.suppressedMask && display.dpAfterglowMask == o.display.dpAfterglowMask &&
               opacityStep == o.opacityStep && style == o.style && pixels == o.pixels;
    }
};

struct CacheEntry { CacheKey key; QImage image; };

std::vector<CacheEntry>& cache() {
    static std::vector<CacheEntry> entries;  // most recently used last
    return entries;
}

constexpr size_t kCacheSize = 24;

} // namespace

void paint(QPainter& p, const QRectF& rect, const DisplaySnapshot& d, double calcOpacity, cu59::LedStyle style) {
    const qreal dpr = p.device() ? p.device()->devicePixelRatioF() : 1.0;
    CacheKey key{d, static_cast<int>(std::lround(calcOpacity * 64)), static_cast<int>(style), (rect.size() * dpr).toSize()};
    auto& entries = cache();
    auto it = std::find_if(entries.begin(), entries.end(), [&](const CacheEntry& e) { return e.key == key; });
    if (it == entries.end()) {
        QImage img(key.pixels, QImage::Format_ARGB32_Premultiplied);
        if (img.isNull()) return;
        img.setDevicePixelRatio(dpr);
        img.fill(Qt::transparent);
        QPainter ip(&img);
        render(ip, QRectF(QPointF(0, 0), rect.size()), d, key.opacityStep / 64.0, style);
        ip.end();
        if (entries.size() >= kCacheSize) entries.erase(entries.begin());
        entries.push_back({key, std::move(img)});
    } else if (it + 1 != entries.end()) {
        std::rotate(it, it + 1, entries.end());  // most recently used last
    }
    p.drawImage(rect.topLeft(), entries.back().image);
}

} // namespace LedRenderer
