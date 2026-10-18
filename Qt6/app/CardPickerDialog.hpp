#pragma once
#include <QDialog>

class QLineEdit;
class QListWidget;
class QPushButton;

// Load / save sheet for magnetic card files (.u59 / .bin) in the documents
// folder. The counterpart of App/Views/CardPickerView.swift.
class CardPickerDialog : public QDialog {
    Q_OBJECT
public:
    enum class Mode { Load, Save };
    CardPickerDialog(Mode mode, const QString& directory, const QString& defaultFileName, QWidget* parent = nullptr);

    /// The chosen file's full path (empty if cancelled).
    QString selectedPath() const { return m_selected; }

private:
    void reload();
    void accept() override;

    Mode m_mode;
    QString m_dir;
    QString m_selected;
    QLineEdit* m_name = nullptr;
    QListWidget* m_list;
    QPushButton* m_save = nullptr;
};
