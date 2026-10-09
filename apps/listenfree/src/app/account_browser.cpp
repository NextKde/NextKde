#include "account_browser.h"
#include "qmlbridge/account_service.h"
#include <QDialog>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QNetworkCookie>
#include <QWebEngineView>
#include <QWebEnginePage>
#include <QWebEngineProfile>
#include <QWebEngineCookieStore>
#include <QWebEngineSettings>
#include <QWebEngineDownloadRequest>
#include <QTimer>
#include <QMap>
#include <QApplication>

namespace listenfree {
namespace {
// Each login gets a fresh, memory-only profile. No web page receives a native
// bridge, previously saved credential, filesystem access, or TLS exception.
class LoginPage final : public QWebEnginePage {
public:
    LoginPage(QWebEngineProfile* profile, QWidget* owner) : QWebEnginePage(profile, owner), owner_(owner) {}
protected:
    bool acceptNavigationRequest(const QUrl& url, NavigationType, bool) override {
        return url.scheme() == "https" || url == QUrl("about:blank");
    }
    void javaScriptConsoleMessage(JavaScriptConsoleMessageLevel, const QString&, int, const QString&) override {}
    QWebEnginePage* createWindow(WebWindowType) override {
        auto* popup = new QDialog(owner_);
        popup->setAttribute(Qt::WA_DeleteOnClose);
        popup->resize(800, 650);
        auto* layout = new QVBoxLayout(popup);
        auto* view = new QWebEngineView(popup);
        auto* page = new LoginPage(profile(), popup);
        view->setPage(page); layout->addWidget(view);
        connect(page, &QWebEnginePage::windowCloseRequested, popup, &QDialog::close);
        popup->show();
        return page;
    }
private:
    QWidget* owner_;
};
}
AccountBrowser::AccountBrowser(qmlbridge::AccountService& accounts, QObject* parent) : QObject(parent), accounts_(accounts) {}
AccountBrowser::~AccountBrowser() {
    if (dialog_) dialog_->close(); // Finish the session before destroying its WebEngine profile.
    delete dialog_.data();
}
void AccountBrowser::open(const QString& provider) {
    const auto url = qmlbridge::AccountService::loginUrl(provider);
    if (url.isEmpty()) return;
    if (dialog_) { dialog_->close(); delete dialog_.data(); }
    auto* dialog = new QDialog;
    dialog_ = dialog;
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setWindowTitle(tr("%1 · 扫码登录").arg(qmlbridge::AccountService::providerName(provider)));
    dialog->setWindowIcon(qApp->windowIcon());
    dialog->resize(1000, 760);
    auto* layout = new QVBoxLayout(dialog);
    auto* hint = new QLabel(tr("在平台官方页面选择登录 / 扫码登录，用手机确认。成功后自动保存；也可点击“完成并验证”。"), dialog);
    hint->setWordWrap(true); layout->addWidget(hint);
    auto* address = new QLabel(url.host(), dialog); address->setTextFormat(Qt::PlainText); layout->addWidget(address);
    auto* profile = new QWebEngineProfile(dialog);
    profile->setHttpAcceptLanguage("zh-CN,zh;q=0.9");
    profile->setPersistentCookiesPolicy(QWebEngineProfile::NoPersistentCookies);
    profile->settings()->setAttribute(QWebEngineSettings::JavascriptCanAccessClipboard, false);
    profile->settings()->setAttribute(QWebEngineSettings::LocalContentCanAccessFileUrls, false);
    connect(profile, &QWebEngineProfile::downloadRequested, dialog, [](QWebEngineDownloadRequest* request) { request->cancel(); });
    auto* view = new QWebEngineView(dialog);
    auto* page = new LoginPage(profile, dialog);
    view->setPage(page); view->setContextMenuPolicy(Qt::NoContextMenu); layout->addWidget(view, 1);
    view->setZoomFactor(.82);
    // QWebEngine requires the profile to outlive all its pages, including OAuth popups.
    connect(dialog, &QDialog::finished, this, [this, provider] { accounts_.cancelLogin(provider); });
    auto cookies = std::make_shared<QMap<QByteArray,QNetworkCookie>>();
    auto lastAttempt = std::make_shared<QByteArray>();
    auto* settle = new QTimer(dialog); settle->setSingleShot(true); settle->setInterval(1200);
    const auto serialized = [cookies] {
        QMap<QByteArray,QByteArray> fields;
        for (const auto& cookie : *cookies) fields[cookie.name()] = cookie.value();
        QByteArray result;
        for (auto it=fields.cbegin();it!=fields.cend();++it) { if (!result.isEmpty()) result += "; "; result += it.key() + '=' + it.value(); }
        return result;
    };
    const auto attempt = [this, provider, serialized, lastAttempt, hint](bool automatic) {
        const auto cookie = serialized();
        if (!qmlbridge::AccountService::hasLoginCookie(provider,cookie)) {
            if (!automatic) hint->setText(tr("尚未取得平台登录凭据。请先完成手机扫码确认，或改用 Cookie 登录。"));
            return;
        }
        if (automatic && cookie == *lastAttempt) return;
        *lastAttempt = cookie;
        hint->setText(tr("正在保存并检查登录状态…"));
        accounts_.login(provider,QString::fromUtf8(cookie));
    };
    connect(settle, &QTimer::timeout, dialog, [attempt] { attempt(true); });
    connect(profile->cookieStore(), &QWebEngineCookieStore::cookieAdded, dialog,
        [provider,cookies,settle](const QNetworkCookie& cookie) {
            if (!qmlbridge::AccountService::cookieDomainAllowed(provider,cookie.domain())) return;
            (*cookies)[cookie.domain().toUtf8() + cookie.path().toUtf8() + '/' + cookie.name()] = cookie;
            settle->start();
        });
    connect(profile->cookieStore(), &QWebEngineCookieStore::cookieRemoved, dialog, [cookies](const QNetworkCookie& cookie) {
        cookies->remove(cookie.domain().toUtf8() + cookie.path().toUtf8() + '/' + cookie.name());
    });
    connect(&accounts_, &qmlbridge::AccountService::loginFinished, dialog, [dialog,hint,provider](const QString& id,bool accepted) {
        if (id != provider) return;
        if (accepted) dialog->accept(); else hint->setText(tr("平台验证未成功。可重试、重新扫码，或使用 Cookie 登录。"));
    });
    connect(view, &QWebEngineView::urlChanged, address, [address](const QUrl& current) { address->setText(current.host()); });
    connect(view, &QWebEngineView::loadFinished, hint, [hint](bool ok) {
        if (!ok) hint->setText(tr("官方页面暂时未能载入。可刷新重试，或关闭此窗口使用 Cookie 登录。"));
    });
    connect(view, &QWebEngineView::loadFinished, page, [page,provider,url](bool ok) {
        if (!ok || page->url().host() != url.host()) return;
        // Open only the official site's login dialog. Consent and phone
        // confirmation remain user actions; no credentials are read via JS.
        const auto selector = QMap<QString,QString>{{"qqmusic",".top_login__link"},
            {"kugou","._login"}, {"kuwo",".reg_text"}}.value(provider);
        if (selector.isEmpty()) return;
        QTimer::singleShot(1800,page,[page,selector] {
            page->runJavaScript("{ const button = document.querySelector('" + selector + "'); if (button) button.click(); }");
        });
    });
    auto* buttons = new QHBoxLayout;
    auto* reload = new QPushButton(tr("刷新二维码 / 页面"),dialog);
    auto* done = new QPushButton(tr("完成并验证"),dialog);
    auto* cancel = new QPushButton(tr("取消"),dialog);
    buttons->addWidget(reload); buttons->addStretch(); buttons->addWidget(done); buttons->addWidget(cancel); layout->addLayout(buttons);
    connect(reload,&QPushButton::clicked,view,&QWebEngineView::reload);
    connect(done,&QPushButton::clicked,dialog,[attempt] { attempt(false); });
    connect(cancel,&QPushButton::clicked,dialog,&QDialog::reject);
    // Destroy pages before the profile even when the window is closed mid-login.
    connect(dialog, &QDialog::finished, dialog, [dialog,profile] {
        const auto pages = dialog->findChildren<QWebEnginePage*>();
        for (auto* child : pages) delete child;
        delete profile;
    });
    view->load(url); dialog->show();
}
}
