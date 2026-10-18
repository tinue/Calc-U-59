#include "CardPickerDialog.hpp"
#include <QDir>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QVBoxLayout>

CardPickerDialog::CardPickerDialog(Mode mode, const QString& directory, const QString& defaultFileName, QWidget* parent)
    : QDialog(parent), m_mode(mode), m_dir(directory) {
    setWindowTitle(mode == Mode::Load ? QStringLiteral("Load Card") : QStringLiteral("Save Card"));
    setMinimumSize(320, 300);
    auto* col = new QVBoxLayout(this);

    if (mode == Mode::Save) {
        m_name = new QLineEdit(defaultFileName, this);
        m_name->setPlaceholderText(QStringLiteral("Filename"));
        col->addWidget(m_name);
    }

    m_list = new QListWidget(this);
    col->addWidget(m_list, 1);
    connect(m_list, &QListWidget::itemClicked, this, [this](QListWidgetItem* item) {
        if (m_mode == Mode::Save) m_name->setText(item->text());
    });
    connect(m_list, &QListWidget::itemActivated, this, [this](QListWidgetItem* item) {
        if (m_mode == Mode::Save) m_name->setText(item->text());
        accept();
    });

    auto* footer = new QHBoxLayout;
    auto* path = new QLabel(QDir::toNativeSeparators(directory), this);
    path->setStyleSheet(QStringLiteral("color: gray; font-size: 10px;"));
    path->setTextInteractionFlags(Qt::TextSelectableByMouse);
    footer->addWidget(path, 1);
    auto* cancel = new QPushButton(QStringLiteral("Cancel"), this);
    connect(cancel, &QPushButton::clicked, this, &QDialog::reject);
    footer->addWidget(cancel);
    if (mode == Mode::Save) {
        m_save = new QPushButton(QStringLiteral("Save"), this);
        m_save->setDefault(true);
        connect(m_save, &QPushButton::clicked, this, &CardPickerDialog::accept);
        connect(m_name, &QLineEdit::textChanged, this, [this](const QString& t) { m_save->setEnabled(!t.trimmed().isEmpty()); });
        footer->addWidget(m_save);
    }
    col->addLayout(footer);
    reload();
}

void CardPickerDialog::reload() {
    QDir().mkpath(m_dir);
    QStringList files = QDir(m_dir).entryList({QStringLiteral("*.u59"), QStringLiteral("*.U59"), QStringLiteral("*.bin")},
                                              QDir::Files | QDir::NoDotAndDotDot, QDir::Name);
    m_list->clear();
    if (files.isEmpty()) {
        auto* item = new QListWidgetItem(m_mode == Mode::Load ? QStringLiteral("No cards found") : QStringLiteral("No existing cards"));
        item->setFlags(Qt::NoItemFlags);
        m_list->addItem(item);
        return;
    }
    m_list->addItems(files);
}

void CardPickerDialog::accept() {
    if (m_mode == Mode::Save) {
        QString name = m_name->text().trimmed();
        if (name.isEmpty()) return;
        if (!name.contains(QLatin1Char('.'))) name += QStringLiteral(".U59");
        m_selected = QDir(m_dir).filePath(name);
    } else {
        QListWidgetItem* item = m_list->currentItem();
        if (!item || !(item->flags() & Qt::ItemIsEnabled)) return;
        m_selected = QDir(m_dir).filePath(item->text());
    }
    QDialog::accept();
}
