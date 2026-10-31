#pragma once
#include <QObject>
#include <QJsonValue>
#include <QVariantMap>

class WindowSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(bool animationBusy READ animationBusy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
public:
    explicit WindowSettings(QObject *parent = nullptr);
    QVariantMap state() const;
    bool animationBusy() const { return m_animationBusy; }
    Q_INVOKABLE bool requestAnimation(const QString &kind, const QString &style);
    QString error() const { return m_error; }
    Q_INVOKABLE void refresh() { emit changed(); }
    Q_INVOKABLE bool setRadius(int radius);
    Q_INVOKABLE bool setShadow(bool enabled);
    Q_INVOKABLE bool setTakeover(bool enabled);
    bool setAnimation(const QString &kind, const QString &style);
    Q_INVOKABLE bool setButtonGlyphMode(const QString &mode);
    bool installDefaults();
    bool restoreAnimationDefaults();
signals:
    void changed();
private:
    bool patchAppearance(const QString &section, const QString &key, const QJsonValue &value);
    QString m_error;
    bool m_animationBusy = false;
};
