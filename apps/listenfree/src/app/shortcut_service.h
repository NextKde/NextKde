#pragma once
#include "qmlbridge/controllers.h"
#include <QAbstractNativeEventFilter>
#include <QMap>
#include <QPointer>
#include <QShortcut>
#include <QWindow>

namespace listenfree {
// Qt local shortcuts and the Qmmp-style Windows hotkey boundary share one
// configuration owner. UI capture never sends playback commands.
class ShortcutService final : public QObject, public QAbstractNativeEventFilter {
    Q_OBJECT
    Q_PROPERTY(QString recordingKey READ recordingKey NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString conflictKey READ conflictKey NOTIFY changed)
    Q_PROPERTY(int revision READ revision NOTIFY changed)
public:
    explicit ShortcutService(qmlbridge::SettingsController& settings, QObject* parent = nullptr);
    ~ShortcutService() override;
    void setWindow(QWindow* window);
    QString recordingKey() const { return recording_; }
    QString error() const { return error_; }
    QString conflictKey() const { return conflict_; }
    int revision() const { return revision_; }
    Q_INVOKABLE QString binding(const QString& key) const { return bindings_.value(key); }
    Q_INVOKABLE bool enabled(const QString& group) const;
    Q_INVOKABLE void beginCapture(const QString& key);
    Q_INVOKABLE void cancelCapture();
    Q_INVOKABLE bool setBinding(const QString& key, const QString& sequence);
    Q_INVOKABLE bool setEnabled(const QString& group, bool enabled);
    Q_INVOKABLE bool resetGroup(const QString& group);
    static QMap<QString, QString> defaults();
signals:
    void changed();
    void activated(const QString& action);
protected:
    bool eventFilter(QObject* watched, QEvent* event) override;
    bool nativeEventFilter(const QByteArray&, void* message, qintptr* result) override;
private:
    friend struct ShortcutServiceTestAccess;
    struct NativeKey { unsigned int key = 0, modifiers = 0; QString identity() const; };
    struct Registration { int id = 0; QString action, sequence; };
    qmlbridge::SettingsController& settings_;
    QPointer<QWindow> window_;
    QMap<QString, QString> bindings_;
    QMap<QString, Registration> registered_;
    QList<QPointer<QShortcut>> local_;
    QString recording_, error_, conflict_;
    bool applicationEnabled_ = true, globalEnabled_ = false, writing_ = false;
    int revision_ = 0, nextId_ = 1;
    void* receiver_ = nullptr;
    QWindow receiverWindow_;
    static NativeKey nativeKey(const QKeySequence& sequence);
    static QString validate(const QString& text, bool global);
    bool commit(const QMap<QString, QString>& desired, bool application, bool global);
    bool fail(const QString& message, const QString& conflict = {});
    void rebuildLocal();
    void dispatch(const QString& action);
};
}
