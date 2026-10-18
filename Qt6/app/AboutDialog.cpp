#include "AboutDialog.hpp"
#include "Version.h"
#include <QDialogButtonBox>
#include <QLabel>
#include <QVBoxLayout>

AboutDialog::AboutDialog(QWidget* parent) : QDialog(parent) {
    setWindowTitle(QStringLiteral("About Calc-U-59"));
    auto* col = new QVBoxLayout(this);
    auto* icon = new QLabel(this);
    icon->setPixmap(QPixmap(QStringLiteral(":/app/icon.png")).scaled(96, 96, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    icon->setAlignment(Qt::AlignCenter);
    col->addWidget(icon);
    // Texts and links mirror App/AppInfo.swift.
    auto* text = new QLabel(this);
    text->setTextFormat(Qt::RichText);
    text->setOpenExternalLinks(true);
    text->setAlignment(Qt::AlignCenter);
    text->setText(QStringLiteral(
        "<h2>Calc-U-59</h2>"
        "<p>Version " APP_VERSION " (" APP_BUILD_ID ")</p>"
        "<p><b>Calc-U-59 Calculator Emulation</b></p>"
        "<p>Cycle-accurate TI-59, TI-58, and TI-58C emulation with magnetic cards,<br>"
        "paper tape printer, preset state files, and debugger tools.</p>"
        "<p><a href='https://github.com/tinue/Calc-U-59'>GitHub</a> &nbsp;·&nbsp; "
        "<a href='https://github.com/tinue/Calc-U-59/issues'>Support</a> &nbsp;·&nbsp; "
        "<a href='https://github.com/tinue/Calc-U-59/blob/main/PRIVACY.md'>Privacy</a></p>"
        "<p style='color:gray; font-size:small'>Built with Qt (LGPL-3.0).</p>"));
    col->addWidget(text);
    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok, this);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    col->addWidget(buttons);
}
