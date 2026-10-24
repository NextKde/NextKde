#include "account_browser.h"
#include "qmlbridge/account_service.h"
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QMessageBox>
#include <QPushButton>
#include <QStandardPaths>

namespace listenfree {
AccountBrowser::AccountBrowser(qmlbridge::AccountService& accounts, QObject* parent)
    : QObject(parent), accounts_(accounts) {
    // The child owns its login UI and secret storage; no credential IPC is used.
    process_.setStandardOutputFile(QProcess::nullDevice());
    process_.setStandardErrorFile(QProcess::nullDevice());
    timeout_.setSingleShot(true);
    timeout_.setInterval(10 * 60 * 1000);
    connect(&timeout_, &QTimer::timeout, this, [this] {
        timedOut_ = true;
        process_.kill();
        emit notice(tr("网页登录已超时，请重试。"));
    });
    connect(&process_, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            timeout_.stop();
            emit notice(tr("网页登录组件无法启动，请检查安装或使用 Cookie 登录。"));
        }
    });
    connect(&process_, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        timeout_.stop();
        if (status == QProcess::NormalExit && code == 0) accounts_.restore();
        else if (!timedOut_ && (status == QProcess::CrashExit || code != 1))
            emit notice(tr("网页登录组件异常退出，请重试或使用 Cookie 登录。"));
    });
}
AccountBrowser::~AccountBrowser() {
    delete installDialog_.data();
    process_.disconnect(this);
    if (process_.state() != QProcess::NotRunning) {
        process_.terminate();
        if (!process_.waitForFinished(1000)) { process_.kill(); process_.waitForFinished(1000); }
    }
}
void AccountBrowser::open(const QString& provider) {
    if (qmlbridge::AccountService::loginUrl(provider).isEmpty()) return;
    if (process_.state() != QProcess::NotRunning) {
        emit notice(tr("请先完成或关闭已有的网页登录窗口。"));
        return;
    }
    const auto directory = QCoreApplication::applicationDirPath();
    auto helper = directory + "/listenfree-web-login";
    if (!QFileInfo(helper).isExecutable()) helper = QStandardPaths::findExecutable("listenfree-web-login");
    if (helper.isEmpty()) {
        if (installDialog_) { installDialog_->show(); installDialog_->raise(); return; }
        auto* dialog = new QMessageBox(QMessageBox::Information, tr("安装网页登录组件"),
            tr("扫码登录需要可选组件 listenfree-web-login。安装后即可使用，无需重装播放器。也可以直接使用 Cookie 登录。"),
            QMessageBox::Close);
        installDialog_ = dialog;
        dialog->setObjectName("webLoginInstallDialog");
        dialog->setAttribute(Qt::WA_DeleteOnClose);
        auto* instructions = dialog->addButton(tr("查看安装说明"), QMessageBox::ActionRole);
        connect(instructions, &QPushButton::clicked, dialog, [directory] {
            QDesktopServices::openUrl(QUrl::fromLocalFile(directory + "/web-login-install.txt"));
        });
        dialog->open();
        return;
    }
    if (installDialog_) installDialog_->close();
    timedOut_ = false;
    process_.start(helper, {"--provider", provider, "--profile", QCoreApplication::instance()->property("listenfreeDataDir").toString()});
    timeout_.start();
}
}
