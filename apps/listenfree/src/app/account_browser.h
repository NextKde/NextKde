#pragma once
#include <QObject>
#include <QPointer>
class QDialog;
namespace listenfree {
namespace qmlbridge { class AccountService; }
class AccountBrowser final : public QObject {
    Q_OBJECT
public:
    explicit AccountBrowser(qmlbridge::AccountService& accounts, QObject* parent = nullptr);
    ~AccountBrowser() override;
    Q_INVOKABLE void open(const QString& provider);
private:
    qmlbridge::AccountService& accounts_;
    QPointer<QDialog> dialog_;
};
}
