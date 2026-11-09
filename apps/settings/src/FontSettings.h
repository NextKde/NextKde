#pragma once

#include <QFont>
#include <QObject>
#include <QStringList>
#include <QVariant>

class QQmlEngine;
class KQuickConfigModule;

// Native Settings form over Plasma's font KCM backend. KDE remains responsible
// for KConfig, fontconfig, GTK/X11 exports and notifying running applications.
class FontSettings final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool previewAvailable READ previewAvailable CONSTANT)
    Q_PROPERTY(bool dpiAvailable READ dpiAvailable NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool needsSave READ needsSave NOTIFY changed)
    Q_PROPERTY(QObject *module READ module NOTIFY changed)
    Q_PROPERTY(QObject *fonts READ fonts NOTIFY changed)
    Q_PROPERTY(QObject *rendering READ rendering NOTIFY changed)
    Q_PROPERTY(QStringList subPixelOptions READ subPixelOptions NOTIFY changed)
    Q_PROPERTY(QStringList hintingOptions READ hintingOptions NOTIFY changed)

public:
    explicit FontSettings(QQmlEngine *engine, QObject *parent = nullptr);
    bool available() const { return m_module != nullptr; }
    bool previewAvailable() const;
    bool dpiAvailable() const;
    QString error() const { return m_error; }
    bool needsSave() const;
    QObject *module() const;
    QObject *fonts() const;
    QObject *rendering() const;
    QStringList subPixelOptions() const;
    QStringList hintingOptions() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void reset();
    Q_INVOKABLE void defaults();
    Q_INVOKABLE bool apply();
    Q_INVOKABLE bool fontEditable(const QString &category) const;
    Q_INVOKABLE bool renderingEditable(const QString &setting) const;
    Q_INVOKABLE void setFont(const QString &category, QFont font);
    Q_INVOKABLE void adjustAllFonts(const QFont &font, bool family, bool style, bool size);
    Q_INVOKABLE void setRendering(const QString &setting, const QVariant &value);
    Q_INVOKABLE void setSubPixel(int index);
    Q_INVOKABLE void setHinting(int index);

signals:
    void changed();

private:
    QQmlEngine *m_engine;
    KQuickConfigModule *m_module = nullptr;
    QString m_error;
};
