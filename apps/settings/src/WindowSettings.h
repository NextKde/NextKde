#pragma once
#include <QObject>
#include <QJsonValue>
#include <QVariantMap>

class WindowSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
public:
    explicit WindowSettings(QObject *parent = nullptr) : QObject(parent) {}
    QVariantMap state() const;
    QString error() const { return m_error; }
    Q_INVOKABLE void refresh() { emit changed(); }
    Q_INVOKABLE bool setRadius(int radius);
    Q_INVOKABLE bool setShadow(bool enabled);
    Q_INVOKABLE bool setTakeover(bool enabled);
    Q_INVOKABLE bool setAnimation(const QString &kind, const QString &style);
    bool installDefaults();
signals:
    void changed();
private:
    bool patchAppearance(const QString &section, const QString &key, const QJsonValue &value);
    QString m_error;
};
