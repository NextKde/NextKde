#pragma once
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QPointer>
class QMessageBox;
namespace listenfree {
namespace qmlbridge { class AccountService; }
// Launches the optional component. Credentials stay in the system keyring.
class AccountBrowser final : public QObject {
    Q_OBJECT
public:
    explicit AccountBrowser(qmlbridge::AccountService& accounts, QObject* parent = nullptr);
    ~AccountBrowser() override;
    Q_INVOKABLE void open(const QString& provider);
signals:
    void notice(const QString& message);
private:
    qmlbridge::AccountService& accounts_;
    QProcess process_;
    QTimer timeout_;
    QPointer<QMessageBox> installDialog_;
    bool timedOut_ = false;
};
}
