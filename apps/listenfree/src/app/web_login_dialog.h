#pragma once
#include <QObject>
#include <QPointer>
class QDialog;
namespace listenfree {
namespace qmlbridge { class AccountService; }
class WebLoginDialog final : public QObject {
    Q_OBJECT
public:
    explicit WebLoginDialog(qmlbridge::AccountService& accounts, QObject* parent = nullptr);
    ~WebLoginDialog() override;
    Q_INVOKABLE void open(const QString& provider);
signals:
    void finished(bool accepted);
private:
    qmlbridge::AccountService& accounts_;
    QPointer<QDialog> dialog_;
};
}
