#include "KeyboardWidget.hpp"
#include "AppSettings.hpp"
#include "CueCardRenderer.hpp"
#include "EmulatorController.hpp"
#include "KeyboardMap.hpp"
#include "LedRenderer.hpp"
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>

namespace {
QRectF norm(const QRectF& canvas, const cu59::NRect& r) {
    return QRectF(canvas.left() + r.x * canvas.width(), canvas.top() + r.y * canvas.height(), r.w * canvas.width(),
                  r.h * canvas.height());
}
} // namespace

KeyboardWidget::KeyboardWidget(EmulatorController& controller, QWidget* parent)
    : QWidget(parent), m_controller(controller) {
    setFocusPolicy(Qt::StrongFocus);
    setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Preferred);
    auto reload = [this] {
        bool ti59 = m_controller.model() == cu59::Model::TI59;
        m_base = QPixmap(ti59 ? QStringLiteral(":/img/ti59_base.png") : QStringLiteral(":/img/ti58_base.png"));
        m_scaled = QPixmap();
        update();
    };
    reload();
    reloadSettings();
    connect(&m_controller, &EmulatorController::modelChanged, this, reload);
    // The display changes up to 60 times a second: repaint just the display.
    connect(&m_controller, &EmulatorController::displayChanged, this,
            [this] { update(norm(canvasRect(), cu59::kDisplayRect).toAlignedRect()); });
    for (auto sig : {&EmulatorController::cueCardChanged, &EmulatorController::runStateChanged})
        connect(&m_controller, sig, this, qOverload<>(&QWidget::update));
}

void KeyboardWidget::reloadSettings() {
    m_ledStyle = static_cast<cu59::LedStyle>(
        AppSettings::value<int>(AppSettings::kLedFontStyle, cu59::settings::kDefaultLedFontStyle));
    update();
}

int KeyboardWidget::heightForWidth(int w) const { return static_cast<int>(w / cu59::kCanvasAspect); }

QSize KeyboardWidget::sizeHint() const { return QSize(420, heightForWidth(420)); }

QRectF KeyboardWidget::canvasRect() const {
    // Keep the artwork's aspect, centred.
    double w = width(), h = height();
    if (w / h > cu59::kCanvasAspect) w = h * cu59::kCanvasAspect;
    else h = w / cu59::kCanvasAspect;
    return QRectF((width() - w) / 2, (height() - h) / 2, w, h);
}

void KeyboardWidget::paintEvent(QPaintEvent* e) {
    QPainter p(this);
    QRectF c = canvasRect();
    // The artwork scaled once per size (smooth scaling the 2064×4075 image is costly).
    const qreal dpr = devicePixelRatioF();
    const QSize pixels = (c.size() * dpr).toSize();
    if (m_scaled.size() != pixels) {
        m_scaled = m_base.scaled(pixels, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        m_scaled.setDevicePixelRatio(dpr);
    }
    p.drawPixmap(c, m_scaled, QRectF());

    QRectF display = norm(c, cu59::kDisplayRect);
    if (e->rect().intersects(display.toAlignedRect()))
        LedRenderer::paint(p, display, m_controller.display(), m_controller.calcIndicatorOpacity(), m_ledStyle);
    QRectF cardRect = norm(c, cu59::kCardRect);
    if (const auto& card = m_controller.cueCard(); card && e->rect().intersects(cardRect.toAlignedRect()))
        CueCardRenderer::paint(p, cardRect, *card);

    // Pressed key (pointer or physical keyboard): black out the key and draw
    // its artwork shifted 3 px down-right.
    int pk = m_pointer.key() >= 0 ? m_pointer.key() : m_controller.keyboardHeldKey();
    if (pk >= 0) {
        const cu59::NRect& r = cu59::kKeyRects[pk / 5][pk % 5];
        QRectF key(c.left() + r.x * c.width(), c.top() + (cu59::kKeyboardYStart + r.y * cu59::kKeyboardYScale) * c.height(),
                   r.w * c.width(), r.h * cu59::kKeyboardYScale * c.height());
        p.fillRect(key, Qt::black);
        QRectF src((key.left() - c.left()) / c.width() * m_base.width(), (key.top() - c.top()) / c.height() * m_base.height(),
                   key.width() / c.width() * m_base.width(), key.height() / c.height() * m_base.height());
        p.drawPixmap(key.translated(3, 3), m_base, src);
    }
}

void KeyboardWidget::mousePressEvent(QMouseEvent* e) {
    if (e->button() != Qt::LeftButton) return;
    setFocus();  // a click on the calculator claims the physical keyboard
    pointer(e->position());
}

void KeyboardWidget::mouseMoveEvent(QMouseEvent* e) {
    if (e->buttons() & Qt::LeftButton) pointer(e->position());
}

void KeyboardWidget::mouseReleaseEvent(QMouseEvent* e) {
    if (e->button() == Qt::LeftButton) apply(m_pointer.up());
}

void KeyboardWidget::pointer(const QPointF& pos) {
    QRectF c = canvasRect();
    apply(m_pointer.move((pos.x() - c.left()) / c.width(), (pos.y() - c.top()) / c.height()));
}

void KeyboardWidget::apply(const cu59::PointerTracker::Change& c) {
    if (c.fullSpeed) m_controller.setFullSpeed(*c.fullSpeed);
    if (c.release >= 0) m_controller.releaseKey(c.release / 5, c.release % 5);
    if (c.press >= 0) m_controller.pressKey(c.press / 5, c.press % 5);
    if (c.release >= 0 || c.press >= 0) update();
}

std::vector<uint8_t> KeyboardWidget::matrixCodes(const QKeyEvent* e) const {
    cu59::KeyPress k;
    Qt::KeyboardModifiers mods = e->modifiers();
    // Command / Control / Option(Alt) chords belong to menus and the system.
    k.command = mods & (Qt::ControlModifier | Qt::MetaModifier | Qt::AltModifier);
    k.shift = mods & Qt::ShiftModifier;
    switch (e->key()) {
    case Qt::Key_Escape: k.key = cu59::kKeyEscape; break;
    case Qt::Key_Return: k.key = cu59::kKeyReturn; break;
    case Qt::Key_Enter: k.key = cu59::kKeyEnter; break;
    default:
        if (e->key() >= Qt::Key_A && e->key() <= Qt::Key_Z) {
            k.key = static_cast<char32_t>('a' + (e->key() - Qt::Key_A));
            k.isLetter = true;
        } else {
            QString t = e->text();
            if (!t.isEmpty()) k.key = t.toUcs4().value(0);
        }
    }
    QString t = e->text();
    if (!t.isEmpty()) k.produced = t.toUcs4().value(0);
    return cu59::matrixCodesFor(k);
}

void KeyboardWidget::keyPressEvent(QKeyEvent* e) {
    // Auto-repeat is ignored: the matrix bit is a level; repeats would only
    // produce spurious releases.
    if (e->isAutoRepeat()) return;
    auto codes = matrixCodes(e);
    if (codes.empty()) {
        QWidget::keyPressEvent(e);
        return;
    }
    m_controller.keyboardDown(codes);
}

void KeyboardWidget::keyReleaseEvent(QKeyEvent* e) {
    if (e->isAutoRepeat()) return;
    if (matrixCodes(e).empty()) {
        QWidget::keyReleaseEvent(e);
        return;
    }
    m_controller.keyboardUp();
}

void KeyboardWidget::focusOutEvent(QFocusEvent* e) {
    // Losing focus mid-press would otherwise leave the matrix bit set.
    m_controller.keyboardRelease();
    QWidget::focusOutEvent(e);
}

void KeyboardWidget::hideEvent(QHideEvent* e) {
    apply(m_pointer.up());
    m_controller.keyboardRelease();
    QWidget::hideEvent(e);
}
