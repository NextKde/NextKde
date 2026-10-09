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
#include <windows.h>
#include <wincred.h>

namespace listenfree::qmlbridge {
namespace {
constexpr qsizetype MaxCookieBytes = 16 * 1024;
// MinGW still defines the XP limit (512). Windows 10/11 support 5 * 512.
constexpr qsizetype CredentialBlobBytes = 2560;
constexpr qsizetype CredentialAttributeBytes = 256;
constexpr qsizetype MaxCredentialAttributes = 64;
bool supported(const QString& provider) { return provider=="netease" || provider=="bilibili"; }

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
}
AccountService::AccountService(const QString& profile,QObject* parent,QNetworkAccessManager* network)
    :QObject(parent),profile_(profile),networkAccess_(network ? network : &network_) {}
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
    return {};
}
void AccountService::restore() {
    for (const auto& provider:{QString("netease"),QString("bilibili")}) {
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
        emit notice(tr("Cookie 超过 16 KB，请只粘贴 Cookie 字段，不要包含其他请求头。")); return;
    }
    const auto fields = cookieFields(cookie);
    if (fields.isEmpty()) {
        emit notice(tr("Cookie 格式无效，请粘贴 Cookie 请求头的内容（名称=值；多项用分号分隔）。")); return;
    }
    const QByteArray required = provider == "netease" ? "MUSIC_U" : "SESSDATA";
    if (fields.value(required).isEmpty()) {
        emit notice(tr("Cookie 缺少有效的 %1，请从已登录的平台页面复制完整 Cookie。").arg(QString::fromLatin1(required))); return;
    }
    const auto bytes = serializeCookie(fields);
    if (bytes.size() > MaxCookieBytes) {
        emit notice(tr("Cookie 超过 16 KB，请只粘贴 Cookie 字段，不要包含其他请求头。")); return;
    }
    validate(provider,bytes,true);
}
void AccountService::validate(const QString& provider,const QByteArray& cookie,bool persist) {
    const bool netease = provider == "netease";
    const auto body = netease ? neteaseAccountBody(cookie) : QByteArray{};
    if (netease && body.isEmpty()) { emit notice(tr("无法准备账号验证请求，请重试。")); return; }
    const auto generation=++generations_[provider];
    if (replies_.value(provider)) replies_[provider]->abort();
    auto state=accounts_.value(provider).toMap(); state["busy"]=true; accounts_[provider]=state; emit accountsChanged();
    QNetworkRequest request(QUrl(netease?"https://music.163.com/weapi/nuser/account/get":"https://api.bilibili.com/x/web-interface/nav"));
    request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute,QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute,QNetworkRequest::Manual);
    request.setRawHeader("Cookie",cookie);
    request.setRawHeader("Referer",provider=="netease"?"https://music.163.com/":"https://www.bilibili.com/");
    request.setRawHeader("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36");
    request.setRawHeader("Accept", "application/json, text/plain, */*");
    request.setRawHeader("Accept-Language", "zh-CN,zh;q=0.9");
    request.setRawHeader("Origin", netease ? "https://music.163.com" : "https://www.bilibili.com");
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
            profile={};accepted=false; emit notice(tr("无法保存 Windows 凭据，登录未完成。"));
        } else if (profile.isEmpty()) emit notice(networkOk?tr("Cookie 已失效或无法获取账号资料，请重新登录。"):
            tr("账号验证请求失败，请检查网络后重试。"));
        // Keep an already validated account on a failed replacement attempt.
        if (profile.isEmpty() && persist) profile=accounts_.value(provider).toMap();
        profile["busy"]=false; accounts_[provider]=profile; emit accountsChanged();
        if (accepted && persist) emit notice(tr("账号已登录。"));
    });
}
void AccountService::logout(const QString& provider) {
    if (!supported(provider)) return;
    ++generations_[provider];
    if (replies_.value(provider)) replies_[provider]->abort();
    replies_.remove(provider);
    const auto key=target(provider);
    if (!CredDeleteW(reinterpret_cast<LPCWSTR>(key.utf16()),CRED_TYPE_GENERIC,0) && GetLastError()!=ERROR_NOT_FOUND) {
        auto state=accounts_.value(provider).toMap();state["busy"]=false;accounts_[provider]=state;emit accountsChanged();
        emit notice(tr("无法删除本地凭据，请重试。")); return;
    }
    accounts_.remove(provider); networkAccess_->clearAccessCache(); emit accountsChanged(); emit notice(tr("已登出并删除本地凭据。"));
}
}
