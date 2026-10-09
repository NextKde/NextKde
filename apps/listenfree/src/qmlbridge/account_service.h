#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QNetworkReply>
#include <QVariantMap>

namespace listenfree::qmlbridge {
class AccountService final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap accounts READ accounts NOTIFY accountsChanged)
public:
    explicit AccountService(const QString& profile, QObject* parent = nullptr,
                            QNetworkAccessManager* network = nullptr);
    QVariantMap accounts() const { return accounts_; }
    // Native request code only; credentials never enter the QML account model.
    QByteArray cookieForRequest(const QString& provider) const;
    Q_INVOKABLE void login(const QString& provider, const QString& cookie);
    Q_INVOKABLE void logout(const QString& provider);
    void restore();
    static QVariantMap parseProfile(const QString& provider, const QByteArray& json);
signals:
    void accountsChanged();
    void notice(const QString& message);
private:
    QString target(const QString& provider) const;
    void validate(const QString& provider, const QByteArray& cookie, bool persist);
    QString profile_;
    QVariantMap accounts_;
    QNetworkAccessManager network_;
    QNetworkAccessManager* networkAccess_;
    QHash<QString,QPointer<QNetworkReply>> replies_;
    QHash<QString,quint64> generations_;
};
}
