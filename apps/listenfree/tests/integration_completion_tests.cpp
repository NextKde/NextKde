#include "qmlbridge/account_service.h"
#include "qmlbridge/duplicate_service.h"
#include "qmlbridge/settings_transfer.h"
#include "infrastructure/database/repositories.h"
#include "infrastructure/library/library_scanner.h"
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QSignalSpy>
#include <QTest>
#include <QCryptographicHash>
#include <QScopeGuard>
#include <QUrlQuery>
#include <windows.h>
#include <wincred.h>

using namespace listenfree;
using namespace listenfree::qmlbridge;
// Exercise the real account flow without sending synthetic credentials to a platform.
class AccountReply final : public QNetworkReply {
public:
    explicit AccountReply(const QNetworkRequest& request, QObject* parent) : QNetworkReply(parent) {
        setRequest(request); setUrl(request.url()); open(QIODevice::ReadOnly);
    }
    void finish(const QByteArray& json) {
        if (isFinished()) return;
        bytes_ = json; setFinished(true); emit readyRead(); emit finished();
    }
    void abort() override {
        if (isFinished()) return;
        setError(OperationCanceledError, "cancelled"); finish({});
    }
protected:
    qint64 readData(char* data, qint64 size) override {
        const auto count = std::min<qint64>(size, bytes_.size() - position_);
        if (count <= 0) return -1;
        memcpy(data, bytes_.constData() + position_, count); position_ += count; return count;
    }
private:
    QByteArray bytes_;
    qsizetype position_ = 0;
};
class AccountNetwork final : public QNetworkAccessManager {
public:
    QNetworkRequest lastRequest;
    Operation lastOperation{};
    QByteArray lastBody;
    QPointer<AccountReply> reply;
    int requests = 0;
protected:
    QNetworkReply* createRequest(Operation operation, const QNetworkRequest& request, QIODevice* outgoing) override {
        ++requests; lastRequest = request; lastOperation = operation;
        lastBody = outgoing ? outgoing->readAll() : QByteArray{};
        reply = new AccountReply(request, this); return reply;
    }
};
class IntegrationCompletionTests final:public QObject {
    Q_OBJECT
    static void write(const QString& path,const QByteArray& bytes) {QFile file(path);QVERIFY(file.open(QIODevice::WriteOnly));QCOMPARE(file.write(bytes),bytes.size());}
private slots:
    void asynchronousMergeAndRecycle() {
        QTemporaryDir dir;const auto a=dir.filePath("a.mp3"),b=dir.filePath("long-name.mp3"),dbPath=dir.filePath("library.sqlite");
        write(a,"test-music-content");write(b,"test-music-content");
        infrastructure::database::Database db;QVERIFY(db.open(dbPath));infrastructure::library::BasicMetadataReader reader;
        for(const auto& file:{a,b})QVERIFY(db.upsertTrack(*reader.read(std::filesystem::path(file.toStdWString()))));
        infrastructure::database::TrackRepository tracks(db);infrastructure::database::LibraryFolderRepository folders(db);
        infrastructure::library::LocalLibraryScannerAdapter scanner;LibraryController library(scanner,tracks,&folders,dbPath);
        DuplicateService service(dbPath,library);QSignalSpy merged(&service,&DuplicateService::merged);
        service.analyze();QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),5000);QCOMPARE(service.groups().size(),1);
        service.merge(false);QTRY_COMPARE_WITH_TIMEOUT(merged.size(),1,5000);
        QCOMPARE(db.loadTracks().size(),size_t(1));QVERIFY(QFileInfo::exists(b));
        // Reintroduce only this disposable test file to exercise the actual recycle path.
        QVERIFY(db.upsertTrack(*reader.read(std::filesystem::path(b.toStdWString()))));
        service.analyze();QTRY_VERIFY_WITH_TIMEOUT(!service.busy(),5000);QCOMPARE(service.groups().size(),1);
        service.merge(true);QTRY_COMPARE_WITH_TIMEOUT(merged.size(),2,5000);
        QCOMPARE(db.loadTracks().size(),size_t(1));QVERIFY(!QFileInfo::exists(b));QVERIFY(QFileInfo::exists(a));
    }
    void duplicateContentAndRevalidation() {
        QTemporaryDir dir;const auto a=dir.filePath("a.mp3"),b=dir.filePath("b.mp3"),c=dir.filePath("c.mp3");
        write(a,"aaaa");write(b,"aaaa");write(c,"bbbb");
        const QVariantList files{QVariantMap{{"id","a"},{"path",a}},QVariantMap{{"id","b"},{"path",b}},QVariantMap{{"id","c"},{"path",c}}};
        const auto cancel=std::make_shared<std::atomic_bool>(false);
        const auto result=DuplicateService::analyzeFiles(files,cancel);const auto groups=result.value("groups").toList();
        QCOMPARE(groups.size(),1);const auto group=groups.first().toMap();QCOMPARE(group.value("duplicates").toList().size(),1);
        QVERIFY(DuplicateService::unchanged(group.value("keeper").toMap(),group.value("hash").toString(),cancel));
        write(a,"cccc");QVERIFY(!DuplicateService::unchanged(group.value("keeper").toMap(),group.value("hash").toString(),cancel));
        cancel->store(true);QVERIFY(DuplicateService::analyzeFiles(files,cancel).isEmpty());
    }
    void aliasRescanAndReferences() {
        QTemporaryDir dir;const auto folder=dir.filePath("music");QVERIFY(QDir().mkpath(folder));
        const auto a=folder+"/a.mp3",b=folder+"/b.mp3";write(a,"same-data");write(b,"same-data");
        infrastructure::database::Database db;const auto dbPath=dir.filePath("library.sqlite");QVERIFY(db.open(dbPath));
        infrastructure::library::BasicMetadataReader reader;
        for(const auto& path:{a,b})QVERIFY(db.upsertTrack(*reader.read(std::filesystem::path(path.toStdWString()))));
        QVariantList files;for(const auto& track:db.loadTracks())files.append(QVariantMap{{"id",QString::fromStdString(track.id.value())},{"path",QString::fromStdString(*track.localPath)}});
        const auto group=DuplicateService::analyzeFiles(files,std::make_shared<std::atomic_bool>(false)).value("groups").toList().first().toMap();
        const auto keep=group.value("keeper").toMap(),dup=group.value("duplicates").toList().first().toMap();
        const QJsonObject row{{"localPath",dup.value("path").toString()},{"trackId",dup.value("id").toString()}};
        QVERIFY(db.setSetting("collections.v1",QString::fromUtf8(QJsonDocument(QJsonArray{QJsonObject{{"tracks",QJsonArray{row}}}}).toJson())));
        QVERIFY(db.mergeDuplicate(dup,keep,group.value("hash").toString(),true));QCOMPARE(db.loadTracks().size(),size_t(1));
        QVERIFY(QFileInfo::exists(b));
        QVERIFY(QString::fromStdString(*db.getSetting("collections.v1")).contains(keep.value("path").toString()));
        infrastructure::database::TrackRepository tracks(db);infrastructure::database::LibraryFolderRepository folders(db);
        infrastructure::library::LocalLibraryScannerAdapter scanner(std::make_unique<infrastructure::library::BasicMetadataReader>());
        LibraryController library(scanner,tracks,&folders,dbPath);library.scan({folder});QTRY_VERIFY_WITH_TIMEOUT(!library.scanning(),5000);
        QCOMPARE(db.loadTracks().size(),size_t(1));
        // A content change invalidates the alias, even if size is unchanged.
        write(b,"different");library.scan({folder});QTRY_VERIFY_WITH_TIMEOUT(!library.scanning(),5000);
        QCOMPARE(db.loadTracks().size(),size_t(2));
    }
    void settingsBackupPreviewAndReset() {
        QTemporaryDir dir;infrastructure::database::Database db;const auto dbPath=dir.filePath("library.sqlite");QVERIFY(db.open(dbPath));
        infrastructure::database::SettingsRepository settingsRepo(db);SettingsController settings(settingsRepo);
        infrastructure::database::TrackRepository tracks(db);infrastructure::database::LibraryFolderRepository folders(db);
        infrastructure::library::LocalLibraryScannerAdapter scanner;LibraryController library(scanner,tracks,&folders,dbPath);
        SettingsTransfer transfer(db,settings,library);
        settings.setValue("ui.language","EnUs");settings.setValue("ui.motionStyle","Bright");settings.setValue("ui.refreshRateLimit",120);
        settings.setValue("download.folder",dir.filePath("private"));settings.setValue("account.netease.cookie","SECRET");
        settings.setValue("portable.queue","DO NOT EXPORT");settings.setValue("lyrics.showRomanization",true);
        settings.setValue("nowPlaying.playerStyle","Overflow");
        settings.setValue("playback.transition.smart",true);
        const auto file=QUrl::fromLocalFile(dir.filePath("settings.json"));QVERIFY(transfer.exportFile(file,{"general","download","appearance","playback"}));
        QFile exported(file.toLocalFile());QVERIFY(exported.open(QIODevice::ReadOnly));const auto bytes=exported.readAll();exported.close();
        QVERIFY(!bytes.contains("SECRET"));QVERIFY(!bytes.contains("DO NOT EXPORT"));QVERIFY(!bytes.contains("private"));
        settings.setValue("ui.language","ZhCn");QVERIFY(transfer.inspectFile(file));QCOMPARE(settings.value("ui.language").toString(),QString("ZhCn"));
        QVERIFY(transfer.applyImport({"general"}));QCOMPARE(settings.value("ui.language").toString(),QString("EnUs"));
        QVERIFY(!transfer.applyImport({"general"}));
        QVERIFY(transfer.resetDefaults({"general"}));QCOMPARE(settings.value("ui.motionStyle").toString(),QString("Elegant"));
        QCOMPARE(settings.value("ui.refreshRateLimit",60).toInt(),60);QVERIFY(settings.value("lyrics.showRomanization",false).toBool());
        settings.setValue("nowPlaying.playerStyle","Classic");
        QVERIFY(transfer.inspectFile(file));QVERIFY(transfer.applyImport({"appearance"}));
        QCOMPARE(settings.value("nowPlaying.playerStyle").toString(),QString("Overflow"));
        QVERIFY(transfer.resetDefaults({"appearance"}));
        QCOMPARE(settings.value("nowPlaying.playerStyle").toString(),QString("Classic"));
        settings.setValue("playback.transition.smart",false);
        QVERIFY(transfer.inspectFile(file));QVERIFY(transfer.applyImport({"playback"}));
        QVERIFY(settings.value("playback.transition.smart").toBool());
        QVERIFY(transfer.resetDefaults({"playback"}));
        QVERIFY(!settings.value("playback.transition.smart").toBool());
        auto doc=QJsonDocument::fromJson(bytes).object();auto values=doc.value("settings").toObject();values["ui.refreshRateLimit"]=999;doc["settings"]=values;
        write(file.toLocalFile(),QJsonDocument(doc).toJson());QVERIFY(!transfer.inspectFile(file));QVERIFY(!transfer.applyImport({"general"}));
        QCOMPARE(settings.value("ui.refreshRateLimit",60).toInt(),60);
        settings.setValue("settingsBackup.includeDevicePaths",true);settings.setValue("download.folder",dir.filePath("new-downloads"));
        QVERIFY(transfer.exportFile(file,{"download"}));settings.setValue("settingsBackup.devicePathHandling","Create");
        QVERIFY(transfer.inspectFile(file));QVERIFY(!QDir(dir.filePath("new-downloads")).exists());QVERIFY(transfer.applyImport({"download"}));QVERIFY(QDir(dir.filePath("new-downloads")).exists());
    }
    void accountProfilesRequireAuthenticatedIdentity() {
        QVERIFY(AccountService::parseProfile("bilibili",R"({"code":0,"data":{"isLogin":false,"mid":1,"uname":"guest"}})").isEmpty());
        QVERIFY(AccountService::parseProfile("netease",R"({"code":200,"profile":null})").isEmpty());
        QCOMPARE(AccountService::parseProfile("netease",R"({"code":200,"profile":{"userId":123,"nickname":"Test"}})").value("name").toString(),QString("Test"));
        QCOMPARE(AccountService::parseProfile("bilibili",R"({"code":0,"data":{"isLogin":true,"mid":123,"uname":"Test"}})").value("name").toString(),QString("Test"));
        AccountService service("isolated-test-profile");QSignalSpy notice(&service,&AccountService::notice);
        service.login("netease","invalid\r\nCookie");QCOMPARE(notice.size(),1);QVERIFY(service.accounts().isEmpty());
    }
    void browserCookiesReachAccountValidation_data() {
        QTest::addColumn<QString>("provider");
        QTest::addColumn<int>("size");
        for (const auto& provider : {QString("netease"), QString("bilibili")})
            for (const int size : {512, 513, 1500, 3000, 8192})
                QTest::newRow(qPrintable(provider + QString::number(size))) << provider << size;
    }
    void browserCookiesReachAccountValidation() {
        QFETCH(QString, provider);
        QFETCH(int, size);
        QTemporaryDir profile;
        AccountNetwork network;
        AccountService service(profile.path(), nullptr, &network);
        QSignalSpy notice(&service, &AccountService::notice);
        const auto prefix = provider == "netease" ? QString("MUSIC_U=") : QString("SESSDATA=");
        service.login(provider, prefix + QString(size - prefix.size(), 'x'));
        // No event-loop turn: this asserts the input gate, without sending test credentials.
        QVERIFY2(service.accounts().value(provider).toMap().value("busy").toBool(),
                 "A complete browser Cookie was rejected before account validation");
        QCOMPARE(notice.size(), 0);
        QCOMPARE(network.requests, 1);
        QVERIFY(network.lastRequest.rawHeader("Cookie") == (prefix + QString(size - prefix.size(), 'x')).toUtf8());
        QVERIFY(!network.lastRequest.url().hasQuery());
        if (provider == "netease") {
            QCOMPARE(network.lastOperation, QNetworkAccessManager::PostOperation);
            QCOMPARE(network.lastRequest.url().path(), QString("/weapi/nuser/account/get"));
            const QUrlQuery form(QString::fromLatin1(network.lastBody));
            QVERIFY(!QByteArray::fromBase64(form.queryItemValue("params", QUrl::FullyDecoded).toLatin1()).isEmpty());
            QCOMPARE(form.queryItemValue("encSecKey").size(), 256);
        } else {
            QCOMPARE(network.lastOperation, QNetworkAccessManager::GetOperation);
            QCOMPARE(network.lastRequest.url().path(), QString("/x/web-interface/nav"));
            QCOMPARE(network.lastRequest.rawHeader("Origin"), QByteArray("https://www.bilibili.com"));
        }
    }
    void accountCookieInputFormats_data() {
        QTest::addColumn<QString>("provider"); QTest::addColumn<QString>("input"); QTest::addColumn<QByteArray>("expected");
        QTest::newRow("header-prefix") << QString("netease") << QString(" Cookie: MUSIC_U=abc==; __csrf=def ") << QByteArray("MUSIC_U=abc==; __csrf=def");
        QTest::newRow("bili-encoded-value") << QString("bilibili") << QString("cookie: SESSDATA=abc%2Cdef==; bili_jct=xyz") << QByteArray("SESSDATA=abc%2Cdef==; bili_jct=xyz");
        QTest::newRow("line-breaks-and-attributes") << QString("netease") << QString("MUSIC_U = abc==; Path=/; HttpOnly\r\n__csrf = xyz") << QByteArray("MUSIC_U=abc==; __csrf=xyz");
        QTest::newRow("duplicate") << QString("netease") << QString("MUSIC_U=old; MUSIC_U=new") << QByteArray("MUSIC_U=new");
        QTest::newRow("substring-is-not-auth") << QString("netease") << QString("other=MUSIC_U=abc") << QByteArray();
        QTest::newRow("empty-auth") << QString("bilibili") << QString("SESSDATA= ; bili_jct=xyz") << QByteArray();
        QTest::newRow("injected-header") << QString("netease") << QString("MUSIC_U=abc\r\nAuthorization: abc=def") << QByteArray();
        QTest::newRow("control-character") << QString("netease") << QString("MUSIC_U=ab\tcd") << QByteArray();
        QTest::newRow("nul") << QString("netease") << (QString("MUSIC_U=abc") + QChar(0)) << QByteArray();
        QTest::newRow("oversized") << QString("netease") << (QString("MUSIC_U=") + QString(16384, 'x')) << QByteArray();
    }
    void accountCookieInputFormats() {
        QFETCH(QString, provider); QFETCH(QString, input); QFETCH(QByteArray, expected);
        QTemporaryDir dir; AccountNetwork network; AccountService service(dir.path(), nullptr, &network);
        QSignalSpy notices(&service, &AccountService::notice);
        service.login(provider, input);
        QCOMPARE(network.requests, expected.isEmpty() ? 0 : 1);
        QCOMPARE(notices.size(), expected.isEmpty() ? 1 : 0);
        if (!expected.isEmpty()) QVERIFY(network.lastRequest.rawHeader("Cookie") == expected);
    }
    void accountCredentialRoundTrip_data() {
        QTest::addColumn<QString>("provider"); QTest::addColumn<int>("size");
        for (const auto& provider : {QString("netease"), QString("bilibili")})
            for (const int size : {512, 513, 2560, 2561, 8192, 16384})
                QTest::newRow(qPrintable(provider + QString::number(size))) << provider << size;
    }
    void accountCredentialRoundTrip() {
        QFETCH(QString, provider); QFETCH(int, size);
        QTemporaryDir dir; AccountNetwork network; AccountService service(dir.path(), nullptr, &network);
        const auto cleanup = qScopeGuard([&] { service.logout(provider); });
        const QByteArray prefix = provider == "netease" ? "MUSIC_U=" : "SESSDATA=";
        const auto cookie = prefix + QByteArray(size - prefix.size(), 'x');
        const QByteArray response = provider == "netease"
            ? R"({"code":200,"profile":{"userId":123,"nickname":"Test"}})"
            : R"({"code":0,"data":{"isLogin":true,"mid":123,"uname":"Test"}})";
        service.login(provider, QString::fromLatin1(cookie));
        QVERIFY(network.reply); network.reply->finish(response);
        QCOMPARE(service.accounts().value(provider).toMap().value("name").toString(), QString("Test"));
        const auto key = "ListenFree/" + QString::fromLatin1(QCryptographicHash::hash(dir.path().toUtf8(), QCryptographicHash::Sha256).toHex().left(24)) + '/' + provider;
        PCREDENTIALW saved = nullptr;
        QVERIFY(CredReadW(reinterpret_cast<LPCWSTR>(key.utf16()), CRED_TYPE_GENERIC, 0, &saved));
        const auto release = qScopeGuard([&] { CredFree(saved); });
        QCOMPARE(saved->AttributeCount > 0, size > 2560);
        if (size > 2560) {
            QByteArray stored(reinterpret_cast<char*>(saved->CredentialBlob), saved->CredentialBlobSize);
            for (DWORD i = 0; i < saved->AttributeCount; ++i)
                stored += QByteArray(reinterpret_cast<char*>(saved->Attributes[i].Value), saved->Attributes[i].ValueSize);
            QVERIFY(!stored.contains(cookie));
            QVERIFY(!stored.contains(QByteArray(64, 'x')));
        }
        // A rejected replacement keeps both the verified UI identity and stored cookie.
        service.login(provider, QString::fromLatin1(prefix + "expired")); network.reply->finish(R"({"code":401})");
        QCOMPARE(service.accounts().value(provider).toMap().value("name").toString(), QString("Test"));
        AccountNetwork restoreNetwork; AccountService restored(dir.path(), nullptr, &restoreNetwork);
        restored.restore(); QCOMPARE(restoreNetwork.requests, 1);
        QVERIFY(restoreNetwork.lastRequest.rawHeader("Cookie") == cookie);
        QVERIFY(restored.accounts().value(provider).toMap().value("name").toString().isEmpty());
        restoreNetwork.reply->finish(response);
        QCOMPARE(restored.accounts().value(provider).toMap().value("name").toString(), QString("Test"));
        // Replacing an extended credential with a short one removes all old fragments.
        const auto replacement = prefix + "replacement";
        restored.login(provider, QString::fromLatin1(replacement)); restoreNetwork.reply->finish(response);
        PCREDENTIALW replaced = nullptr;
        QVERIFY(CredReadW(reinterpret_cast<LPCWSTR>(key.utf16()), CRED_TYPE_GENERIC, 0, &replaced));
        const bool replacedExactly = replaced->AttributeCount == 0
            && QByteArray(reinterpret_cast<char*>(replaced->CredentialBlob), replaced->CredentialBlobSize) == replacement;
        CredFree(replaced); QVERIFY(replacedExactly);
        restored.logout(provider); QVERIFY(restored.accounts().isEmpty());
        PCREDENTIALW removed = nullptr;
        QVERIFY(!CredReadW(reinterpret_cast<LPCWSTR>(key.utf16()), CRED_TYPE_GENERIC, 0, &removed));
        QCOMPARE(GetLastError(), DWORD(ERROR_NOT_FOUND));
        // Cancelling a pending login cannot recreate credentials or the logged-in UI.
        service.login(provider, QString::fromLatin1(cookie));
        const auto pending = network.reply; service.logout(provider); pending->finish(response);
        QVERIFY(service.accounts().isEmpty());
        const int beforeRestore = network.requests; service.restore(); QCOMPARE(network.requests, beforeRestore);
    }
};
QTEST_GUILESS_MAIN(IntegrationCompletionTests)
#include "integration_completion_tests.moc"
