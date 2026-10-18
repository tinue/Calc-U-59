#include "KeyboardWidget.hpp"
#include "AppSettings.hpp"
#include "CueCardRenderer.hpp"
#include "EmulatorController.hpp"
#include "KeyboardLayout.hpp"
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
        update();
    };
    reload();
    connect(&m_controller, &EmulatorController::modelChanged, this, reload);
    for (auto sig : {&EmulatorController::displayChanged, &EmulatorController::cueCardChanged,
                     &EmulatorController::heldKeyChanged})
        connect(&m_controller, sig, this, qOverload<>(&QWidget::update));
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

void KeyboardWidget::paintEvent(QPaintEvent*) {
    QPainter p(this);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    QRectF c = canvasRect();
    p.drawPixmap(c, m_base, QRectF());

    auto style = static_cast<cu59::LedStyle>(AppSettings::value<int>(AppSettings::kLedFontStyle, cu59::settings::kDefaultLedFontStyle));
    LedRenderer::paint(p, norm(c, cu59::kDisplayRect), m_controller.display(), m_controller.calcIndicatorOpacity(), style);
    if (const auto& card = m_controller.cueCard()) CueCardRenderer::paint(p, norm(c, cu59::kCardRect), *card);

    // Pressed key (pointer or physical keyboard): black out the key and draw
    // its artwork shifted 3 px down-right.
    int pk = m_pressedKey >= 0 ? m_pressedKey : m_controller.keyboardHeldKey();
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
    if (e->button() == Qt::LeftButton) releasePointer();
}

void KeyboardWidget::pointer(const QPointF& pos) {
    QRectF c = canvasRect();
    double nx = (pos.x() - c.left()) / c.width(), ny = (pos.y() - c.top()) / c.height();
    // Holding the display runs the emulator at full speed.
    const cu59::NRect& d = cu59::kDisplayRect;
    if (nx >= d.x && nx <= d.x + d.w && ny >= d.y && ny <= d.y + d.h) {
        if (!m_displayPressed) {
            m_displayPressed = true;
            m_controller.setFullSpeed(true);
            if (m_pressedKey >= 0) {
                m_controller.releaseKey(m_pressedKey / 5, m_pressedKey % 5);
                m_pressedKey = -1;
                update();
            }
        }
        return;
    }
    if (m_displayPressed) {
        m_displayPressed = false;
        m_controller.setFullSpeed(false);
    }
    double kbNy = (ny - cu59::kKeyboardYStart) / cu59::kKeyboardYScale;
    const double margin = 0.025;  // room for the vertical hit expansion
    if (kbNy < -margin || kbNy > 1 + margin) {
        if (m_pressedKey >= 0) {
            m_controller.releaseKey(m_pressedKey / 5, m_pressedKey % 5);
            m_pressedKey = -1;
            update();
        }
        return;
    }
    cu59::KeyHit hit{};
    if (!cu59::keyAt(nx, kbNy, hit)) return;
    int id = hit.row * 5 + hit.col;
    if (id == m_pressedKey) return;
    if (m_pressedKey >= 0) m_controller.releaseKey(m_pressedKey / 5, m_pressedKey % 5);  // one key at a time
    m_pressedKey = id;
    m_controller.pressKey(hit.row, hit.col);
    update();
}

void KeyboardWidget::releasePointer() {
    if (m_displayPressed) {
        m_displayPressed = false;
        m_controller.setFullSpeed(false);
    }
    if (m_pressedKey >= 0) {
        m_controller.releaseKey(m_pressedKey / 5, m_pressedKey % 5);
        m_pressedKey = -1;
        update();
    }
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
    releasePointer();
    m_controller.keyboardRelease();
    QWidget::hideEvent(e);
}
