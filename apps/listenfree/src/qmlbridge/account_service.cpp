#include "account_service.h"
#include "platform/windows_crypto.h"
#include <QCryptographicHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkCookieJar>
#include <QTimer>
#include <QMap>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QUrlQuery>
#ifdef Q_OS_WIN
#include <windows.h>
#include <wincred.h>
#else
#undef signals
#include <libsecret/secret.h>
#define signals Q_SIGNALS
#endif

namespace listenfree::qmlbridge {
namespace {
constexpr qsizetype MaxCookieBytes = 16 * 1024;
// MinGW still defines the XP limit (512). Windows 10/11 support 5 * 512.
constexpr qsizetype CredentialBlobBytes = 2560;
constexpr qsizetype CredentialAttributeBytes = 256;
constexpr qsizetype MaxCredentialAttributes = 64;
bool supported(const QString& provider) { return QStringList{"netease", "qqmusic", "kugou", "kuwo", "bilibili"}.contains(provider); }

QMap<QByteArray, QByteArray> cookieFields(QString text) {
    QMap<QByteArray, QByteArray> fields;
    // Follow the old project's wyAccountCookie.ts: split at the first '=' only.
    static const QRegularExpression separator("[;\\r\\n]+");
    static const QRegularExpression namePattern("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    const QStringList attributes{"path", "domain", "expires", "max-age", "samesite", "secure", "httponly"};
    for (QString item : text.split(separator, Qt::SkipEmptyParts)) {
        item = item.trimmed();
        if (item.startsWith("Cookie:", Qt::CaseInsensitive)) item = item.mid(7).trimmed();
        if (item.isEmpty()) continue;
        const auto equals = item.indexOf('=');
        if (equals < 0 && attributes.contains(item.toLower())) continue;
        if (equals <= 0) return {};
        const auto name = item.left(equals).trimmed();
        const auto value = item.mid(equals + 1).trimmed();
        if (!namePattern.match(name).hasMatch()) return {};
        for (const QChar ch : value)
            if (ch.unicode() < 0x20 || ch.unicode() == 0x7f) return {};
        if (!attributes.contains(name.toLower())) fields[name.toUtf8()] = value.toUtf8();
    }
    return fields;
}
QByteArray serializeCookie(const QMap<QByteArray, QByteArray>& fields) {
    QByteArray result;
    for (auto it = fields.cbegin(); it != fields.cend(); ++it) {
        if (!result.isEmpty()) result += "; ";
        result += it.key() + '=' + it.value();
    }
    return result;
}
QByteArray neteaseAccountBody(const QByteArray& cookie) {
    const auto fields = cookieFields(QString::fromUtf8(cookie));
    const auto json = QJsonDocument(QJsonObject{{"csrf_token", QString::fromUtf8(fields.value("__csrf"))},
                                              {"e_r", false}}).toJson(QJsonDocument::Compact);
    const QByteArray alphabet("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    QByteArray key(16, Qt::Uninitialized);
    for (auto& ch : key) ch = alphabet[QRandomGenerator::system()->bounded(static_cast<int>(alphabet.size()))];
    const QByteArray iv("0102030405060708");
    const auto first = platform::aesEncryptBytes(json, "0CoJUm6Qyw8W8jud", iv, "aes-128-cbc");
    if (first.isEmpty()) return {};
    const auto encrypted = platform::aesEncryptBytes(first.toBase64(), key, iv, "aes-128-cbc");
    std::reverse(key.begin(), key.end());
    const auto wrappedKey = platform::rsaEncryptBytes(key, QStringLiteral(
        "-----BEGIN PUBLIC KEY-----\n"
        "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB\n"
        "-----END PUBLIC KEY-----"));
    key.fill(0);
    if (encrypted.isEmpty() || wrappedKey.isEmpty()) return {};
    return "params=" + QUrl::toPercentEncoding(QString::fromLatin1(encrypted.toBase64()))
        + "&encSecKey=" + wrappedKey.toHex();
}
#ifdef Q_OS_WIN
bool writeCredential(const QString& target, const QByteArray& cookie) {
    CREDENTIALW credential{};
    credential.Type=CRED_TYPE_GENERIC;
    credential.TargetName=const_cast<wchar_t*>(reinterpret_cast<const wchar_t*>(target.utf16()));
    credential.CredentialBlobSize=static_cast<DWORD>(cookie.size());
    credential.CredentialBlob=reinterpret_cast<LPBYTE>(const_cast<char*>(cookie.data()));
    credential.Persist=CRED_PERSIST_LOCAL_MACHINE;
    QByteArray encrypted;
    std::vector<CREDENTIAL_ATTRIBUTEW> attributes;
    std::vector<std::wstring> names;
    if (cookie.size() > CredentialBlobBytes) {
        // QtKeychain's Windows strategy: DPAPI protects the entire payload before
        // spilling into attributes (attributes themselves are not secret storage).
        DATA_BLOB input{static_cast<DWORD>(cookie.size()), credential.CredentialBlob}, output{};
        if (!CryptProtectData(&input, L"ListenFree Cookie", nullptr, nullptr, nullptr,
                              CRYPTPROTECT_UI_FORBIDDEN, &output)) return false;
        encrypted = QByteArray(reinterpret_cast<char*>(output.pbData), output.cbData);
        LocalFree(output.pbData);
        if (encrypted.size() > CredentialBlobBytes + MaxCredentialAttributes * CredentialAttributeBytes) return false;
        credential.CredentialBlobSize = CredentialBlobBytes;
        credential.CredentialBlob = reinterpret_cast<LPBYTE>(encrypted.data());
        const auto count = (encrypted.size() - CredentialBlobBytes + CredentialAttributeBytes - 1) / CredentialAttributeBytes;
        attributes.resize(count);
        names.reserve(count);
        for (qsizetype i = 0; i < count; ++i) {
            names.push_back(QString("ListenFree_CookiePart_%1").arg(i, 2, 10, QLatin1Char('0')).toStdWString());
            auto& attribute = attributes[i];
            attribute.Keyword = names.back().data();
            const auto offset = CredentialBlobBytes + i * CredentialAttributeBytes;
            attribute.ValueSize = static_cast<DWORD>(std::min(CredentialAttributeBytes, encrypted.size() - offset));
            attribute.Value = reinterpret_cast<LPBYTE>(encrypted.data() + offset);
        }
        credential.AttributeCount = static_cast<DWORD>(count);
        credential.Attributes = attributes.data();
    }
    // One write replaces the complete credential, retaining the prior value on failure.
    return CredWriteW(&credential,0);
}
QByteArray readCredential(const QString& target) {
    PCREDENTIALW credential = nullptr;
    if (!CredReadW(reinterpret_cast<LPCWSTR>(target.utf16()), CRED_TYPE_GENERIC, 0, &credential)) return {};
    const auto freeCredential = qScopeGuard([&] { CredFree(credential); });
    QByteArray bytes(reinterpret_cast<const char*>(credential->CredentialBlob), credential->CredentialBlobSize);
    if (credential->AttributeCount == 0) return bytes; // Existing short credentials remain valid.
    if (credential->AttributeCount > MaxCredentialAttributes) return {};
    QMap<QString, QByteArray> parts;
    for (DWORD i = 0; i < credential->AttributeCount; ++i) {
        const auto& attribute = credential->Attributes[i];
        if (attribute.ValueSize > CredentialAttributeBytes) return {};
        parts[QString::fromWCharArray(attribute.Keyword)] = QByteArray(reinterpret_cast<char*>(attribute.Value), attribute.ValueSize);
    }
    for (DWORD i = 0; i < credential->AttributeCount; ++i) {
        const auto name = QString("ListenFree_CookiePart_%1").arg(i, 2, 10, QLatin1Char('0'));
        if (!parts.contains(name)) return {};
        bytes += parts.value(name);
    }
    DATA_BLOB input{static_cast<DWORD>(bytes.size()), reinterpret_cast<LPBYTE>(bytes.data())}, output{};
    if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) return {};
    const QByteArray cookie(reinterpret_cast<char*>(output.pbData), output.cbData);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return cookie;
}
#else
const SecretSchema* credentialSchema() {
    static const SecretSchema schema = {"org.listenfree.Credentials", SECRET_SCHEMA_NONE,
                                       {{"target", SECRET_SCHEMA_ATTRIBUTE_STRING}, {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING}}};
    return &schema;
}
bool writeCredential(const QString& target, const QByteArray& cookie) {
    GError* error = nullptr;
    const bool ok = secret_password_store_sync(credentialSchema(), SECRET_COLLECTION_DEFAULT,
        "ListenFree account", cookie.constData(), nullptr, &error, "target", target.toUtf8().constData(), nullptr);
    if (error) g_error_free(error);
    return ok;
}
QByteArray readCredential(const QString& target) {
    GError* error = nullptr;
    gchar* value = secret_password_lookup_sync(credentialSchema(), nullptr, &error, "target", target.toUtf8().constData(), nullptr);
    const QByteArray result = value ? QByteArray(value) : QByteArray();
    if (value) secret_password_free(value);
    if (error) g_error_free(error);
    return result;
}
bool deleteCredential(const QString& target) {
    GError* error = nullptr;
    secret_password_clear_sync(credentialSchema(), nullptr, &error, "target", target.toUtf8().constData(), nullptr);
    const bool ok = error == nullptr;
    if (error) g_error_free(error);
    return ok;
}
#endif

}
AccountService::AccountService(const QString& profile,QObject* parent,QNetworkAccessManager* network)
    :QObject(parent),profile_(profile),networkAccess_(network ? network : &network_) {}
QVariantList AccountService::providers() {
    QVariantList result;
    for (const QString& id : {QString("netease"), QString("qqmusic"), QString("kugou"), QString("kuwo"), QString("bilibili")})
        result.append(QVariantMap{{"id", id}, {"name", providerName(id)},
            {"verification", id == "kuwo" || id == "kugou" ? "cookie" : "profile"}});
    return result;
}
QString AccountService::providerName(const QString& provider) {
    return QMap<QString,QString>{{"netease",tr("网易云音乐")}, {"qqmusic",tr("QQ 音乐")},
        {"kugou",tr("酷狗音乐")}, {"kuwo",tr("酷我音乐")}, {"bilibili",tr("哔哩哔哩")}}.value(provider);
}
QUrl AccountService::loginUrl(const QString& provider) {
    return QUrl(QMap<QString,QString>{{"netease","https://music.163.com/#/login"},
        {"qqmusic","https://y.qq.com/portal/profile.html"}, {"kugou","https://www.kugou.com/"},
        {"kuwo","https://www.kuwo.cn/"}, {"bilibili","https://passport.bilibili.com/login"}}.value(provider));
}
bool AccountService::cookieDomainAllowed(const QString& provider, const QString& domain) {
    const auto base = QMap<QString,QString>{{"netease","music.163.com"}, {"qqmusic","qq.com"},
        {"kugou","kugou.com"}, {"kuwo","kuwo.cn"}, {"bilibili","bilibili.com"}}.value(provider);
    QString host = domain.toLower(); if (host.startsWith('.')) host.remove(0,1);
    return !base.isEmpty() && (host == base || host.endsWith('.' + base));
}
bool AccountService::hasLoginCookie(const QString& provider, const QByteArray& cookie) {
    const auto fields = cookieFields(QString::fromUtf8(cookie));
    const auto nonempty = [&](const QByteArray& name) { return !fields.value(name).isEmpty(); };
    if (provider == "netease") return nonempty("MUSIC_U");
    if (provider == "bilibili") return nonempty("SESSDATA");
    if (provider == "qqmusic") return (nonempty("uin") || nonempty("wxuin")) && (nonempty("qm_keyst") || nonempty("qqmusic_key"));
    if (provider == "kuwo") return nonempty("userid") && (nonempty("sid") || nonempty("websid"));
    if (provider == "kugou") {
        const QUrlQuery nested(QString::fromUtf8(fields.value("KuGoo")));
        return (nonempty("KugooID") && (nonempty("t") || nonempty("token"))) ||
            (!nested.queryItemValue("KugooID").isEmpty() && !nested.queryItemValue("t").isEmpty());
    }
    return false;
}
QString AccountService::target(const QString& provider) const {
    // Multiple portable profiles must not share login state unintentionally.
    return "ListenFree/"+QString::fromLatin1(QCryptographicHash::hash(profile_.toUtf8(),QCryptographicHash::Sha256).toHex().left(24))+"/"+provider;
}
QVariantMap AccountService::parseProfile(const QString& provider,const QByteArray& bytes) {
    const auto root=QJsonDocument::fromJson(bytes).object();
    QJsonObject profile;
    if (provider=="netease" && root.value("code")==200) {
        profile=root.value("profile").toObject();
        if (profile.value("userId").toVariant().toLongLong()<=0 || profile.value("nickname").toString().isEmpty()) return {};
        return {{"name",profile.value("nickname").toString()}, {"id",profile.value("userId").toVariant().toString()}, {"avatar",profile.value("avatarUrl").toString()}};
    }
    if (provider=="bilibili" && root.value("code")==0) {
        profile=root.value("data").toObject();
        if (!profile.value("isLogin").toBool() || profile.value("mid").toVariant().toLongLong()<=0 || profile.value("uname").toString().isEmpty()) return {};
        return {{"name",profile.value("uname").toString()}, {"id",profile.value("mid").toVariant().toString()}, {"avatar",profile.value("face").toString()}};
    }
    if (provider == "qqmusic" && root.value("code").toInt(-1) == 0) {
        profile = root.value("data").toObject().value("creator").toObject();
        const auto id = profile.value("uin").toVariant().toString();
        const auto name = profile.value("nick").toString();
        if (id.toULongLong() == 0 || name.isEmpty()) return {};
        return {{"id",id}, {"name",name}, {"avatar",profile.value("headpic").toString()}};
    }
    return {};
}
void AccountService::restore() {
    for (const auto& entry : providers()) {
        const auto provider = entry.toMap().value("id").toString();
        auto cookie = readCredential(target(provider));
        if (cookie.isEmpty()) continue;
        validate(provider,cookie,false); cookie.fill(0);
    }
}
QByteArray AccountService::cookieForRequest(const QString& provider) const {
    if (!supported(provider) || accounts_.value(provider).toMap().value("id").toString().isEmpty()) return {};
    return readCredential(target(provider));
}
void AccountService::login(const QString& provider,const QString& cookie) {
    if (!supported(provider)) return;
    if (cookie.toUtf8().size() > MaxCookieBytes) {
        emit notice(tr("Cookie 超过 16 KB，请只粘贴 Cookie 字段，不要包含其他请求头。")); emit loginFinished(provider,false); return;
    }
    const auto fields = cookieFields(cookie);
    if (fields.isEmpty()) {
        emit notice(tr("Cookie 格式无效，请粘贴 Cookie 请求头的内容（名称=值；多项用分号分隔）。")); emit loginFinished(provider,false); return;
    }
    if (!hasLoginCookie(provider, serializeCookie(fields))) {
        emit notice(tr("Cookie 缺少 %1 的登录字段，请从已登录的平台网页复制完整 Cookie。").arg(providerName(provider))); emit loginFinished(provider,false); return;
    }
    const auto bytes = serializeCookie(fields);
    if (bytes.size() > MaxCookieBytes) {
        emit notice(tr("Cookie 超过 16 KB，请只粘贴 Cookie 字段，不要包含其他请求头。")); emit loginFinished(provider,false); return;
    }
    validate(provider,bytes,true);
}
void AccountService::validate(const QString& provider,const QByteArray& cookie,bool persist) {
    // These two official web clients derive identity from their session cookies.
    // Do not describe an imported cookie as server-validated account identity.
    if (provider == "kuwo" || provider == "kugou") {
        if (!hasLoginCookie(provider,cookie)) return;
        if (persist && !writeCredential(target(provider),cookie)) {
            emit notice(tr("无法保存系统钥匙环凭据，登录未完成。")); emit loginFinished(provider,false); return;
        }
        accounts_[provider] = QVariantMap{{"id",provider}, {"name",tr("已保存登录凭据")}, {"verified",false},
            {"status",tr("登录有效期由平台决定，可重新扫码更新。")}, {"busy",false}};
        emit accountsChanged(); emit loginFinished(provider,true);
        if (persist) emit notice(tr("登录凭据已保存到系统钥匙环。"));
        return;
    }
    const bool netease = provider == "netease";
    const auto body = netease ? neteaseAccountBody(cookie) : QByteArray{};
    if (netease && body.isEmpty()) { emit notice(tr("无法准备账号验证请求，请重试。")); emit loginFinished(provider,false); return; }
    const auto generation=++generations_[provider];
    if (replies_.value(provider)) replies_[provider]->abort();
    auto state=accounts_.value(provider).toMap(); state["busy"]=true; accounts_[provider]=state; emit accountsChanged();
    QUrl endpoint(netease ? "https://music.163.com/weapi/nuser/account/get" : "https://api.bilibili.com/x/web-interface/nav");
    if (provider == "qqmusic") {
        const auto fields = cookieFields(QString::fromUtf8(cookie));
        auto id = QString::fromUtf8(fields.value("uin",fields.value("wxuin"))); id.remove(QRegularExpression("[^0-9]"));
        quint32 hash = 5381;
        for (const unsigned char ch : fields.value("qm_keyst",fields.value("qqmusic_key"))) hash += (hash << 5) + ch;
        endpoint = QUrl("https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg");
        QUrlQuery query; query.addQueryItem("format","json"); query.addQueryItem("cid","205360838");
        query.addQueryItem("reqfrom","1"); query.addQueryItem("userid",id); query.addQueryItem("loginUin",id);
        query.addQueryItem("g_tk",QString::number(hash & 0x7fffffff)); endpoint.setQuery(query);
    }
    QNetworkRequest request(endpoint);
    request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute,QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute,QNetworkRequest::Manual);
    request.setRawHeader("Cookie",cookie);
    const auto origin = netease ? QByteArray("https://music.163.com") : provider == "qqmusic" ? QByteArray("https://y.qq.com") : QByteArray("https://www.bilibili.com");
    request.setRawHeader("Referer",origin + '/');
    request.setRawHeader("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36");
    request.setRawHeader("Accept", "application/json, text/plain, */*");
    request.setRawHeader("Accept-Language", "zh-CN,zh;q=0.9");
    request.setRawHeader("Origin", origin);
    request.setRawHeader("Sec-Fetch-Site", netease ? "same-origin" : "same-site");
    request.setRawHeader("Sec-Fetch-Mode", "cors");
    request.setRawHeader("Sec-Fetch-Dest", "empty");
    if (netease) request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    auto* reply=netease ? networkAccess_->post(request, body) : networkAccess_->get(request); replies_[provider]=reply;
    connect(reply,&QNetworkReply::finished,this,[this,reply,provider,generation,cookie,persist] {
        reply->deleteLater(); if (generation!=generations_.value(provider)) return;
        replies_.remove(provider);
        const bool networkOk=reply->error()==QNetworkReply::NoError;
        auto profile=networkOk?parseProfile(provider,reply->readAll()):QVariantMap{};
        bool accepted=!profile.isEmpty();
        if (!profile.isEmpty() && persist && !writeCredential(target(provider),cookie)) {
            profile={};accepted=false; emit notice(tr("无法保存系统钥匙环凭据，登录未完成。"));
        } else if (profile.isEmpty()) emit notice(networkOk?tr("Cookie 已失效或无法获取账号资料，请重新登录。"):
            tr("账号验证请求失败，请检查网络后重试。"));
        // Keep an already validated account on a failed replacement attempt.
        if (profile.isEmpty() && persist) profile=accounts_.value(provider).toMap();
        profile["busy"]=false; if (accepted) profile["verified"]=true; accounts_[provider]=profile; emit accountsChanged();
        emit loginFinished(provider,accepted);
        if (accepted && persist) emit notice(tr("账号已登录。"));
    });
}
void AccountService::cancelLogin(const QString& provider) {
    ++generations_[provider];
    if (replies_.value(provider)) replies_[provider]->abort();
    replies_.remove(provider);
    auto state = accounts_.value(provider).toMap(); state["busy"] = false;
    accounts_[provider] = state; emit accountsChanged();
}
void AccountService::logout(const QString& provider) {
    if (!supported(provider)) return;
    ++generations_[provider];
    if (replies_.value(provider)) replies_[provider]->abort();
    replies_.remove(provider);
    const auto key=target(provider);
#ifdef Q_OS_WIN
    const bool deleted = CredDeleteW(reinterpret_cast<LPCWSTR>(key.utf16()),CRED_TYPE_GENERIC,0) || GetLastError()==ERROR_NOT_FOUND;
#else
    const bool deleted = deleteCredential(key);
#endif
    if (!deleted) {
        auto state=accounts_.value(provider).toMap();state["busy"]=false;accounts_[provider]=state;emit accountsChanged();
        emit notice(tr("无法删除本地凭据，请重试。")); return;
    }
    accounts_.remove(provider); networkAccess_->clearAccessCache(); emit accountsChanged(); emit notice(tr("已登出并删除本地凭据。"));
}
}
