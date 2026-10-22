#include "AppStore.h"

#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <KIO/ApplicationLauncherJob>
#include <KJob>
#include <KService>
#include <csignal>
#include <unistd.h>

namespace {
const QString appId = QStringLiteral("org.nextkde.KMusic");
const QString repository = QStringLiteral("https://github.com/NextKde/KMusic");
const QStringList installerFiles{QStringLiteral("install.sh"), QStringLiteral("packaging/installer.py")};
constexpr qsizetype maximumOutput = 1024 * 1024;
}

AppStore::AppStore(const QString& directory, QObject* parent)
    : QObject(parent)
{
    m_state = {{"busy", false}, {"installed", false}, {"available", false}, {"code", ""},
               {"stage", ""}, {"message", ""}, {"logPath", ""}, {"dependencies", QVariantList{}}};
    QFile catalog(directory + QStringLiteral("/app-store/catalog.json"));
    if (catalog.open(QIODevice::ReadOnly)) {
        const auto document = QJsonDocument::fromJson(catalog.readAll()).object();
        const auto entry = document.value(QStringLiteral("kmusic")).toObject();
        m_release = entry.value(QStringLiteral("release")).toObject();
        const auto hashes = m_release.value(QStringLiteral("sha256")).toObject();
        const QRegularExpression revision(QStringLiteral("^[0-9a-f]{40}$"));
        const QRegularExpression digest(QStringLiteral("^[0-9a-f]{64}$"));
        m_published = document.value("schemaVersion").toInt() == 1
            && entry.value("appId").toString() == appId
            && entry.value("repository").toString() == repository
            && revision.match(m_release.value("revision").toString()).hasMatch();
        for (const auto& file : installerFiles)
            m_published = m_published && digest.match(hashes.value(file).toString()).hasMatch();
    }
    m_state["available"] = m_published;
    // Keep all compiler/git descendants in our own session. Cancellation and
    // window closure must not leave an installation running in the background.
    m_process.setChildProcessModifier([] { if (::setsid() < 0) ::_exit(126); });
    connect(&m_process, &QProcess::started, this, [this] { m_processGroup = m_process.processId(); });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &AppStore::consumeOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        const auto diagnostics = m_process.readAllStandardError();
        appendLog(diagnostics);
        m_state["diagnostics"] = (m_state.value("diagnostics").toString()
            + QString::fromUtf8(diagnostics)).right(16384);
    });
    connect(&m_process, &QProcess::finished, this, &AppStore::finish);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            fail(QStringLiteral("START_FAILED"), m_process.errorString());
    });
    m_killTimer.setSingleShot(true);
    connect(&m_killTimer, &QTimer::timeout, this, [this] { stopProcess(SIGKILL); });
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        const bool downloading = m_reply || m_state.value("stage") == "download";
        m_timeoutCode = downloading ? QStringLiteral("DOWNLOAD_TIMEOUT") : QStringLiteral("OPERATION_TIMEOUT");
        appendLog(("Timeout at stage " + m_state.value("stage").toString() + '\n').toUtf8());
        if (m_reply) { m_reply->abort(); return; }
        stopProcess(SIGTERM);
        m_killTimer.start(10000);
    });
    m_retryTimer.setSingleShot(true);
    connect(&m_retryTimer, &QTimer::timeout, this, [this] {
        if (m_cancelled || !m_state.value("busy").toBool()) return;
        if (m_retryIndex >= 0) downloadNext(m_retryIndex, m_retryAttempt);
        else run(QStringLiteral("install"));
    });
    m_elapsedTimer.setInterval(1000);
    connect(&m_elapsedTimer, &QTimer::timeout, this, [this] {
        m_state["elapsedSeconds"] = m_elapsed.elapsed() / 1000;
        emit changed();
    });
    refresh();
}

AppStore::~AppStore()
{
    if (m_reply) { m_reply->disconnect(this); m_reply->abort(); }
    // This is a forced interruption, never recorded as successful by the UI.
    stopProcess(SIGKILL);
    m_process.waitForFinished(1000);
}

QString AppStore::dataDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/kmusic-app");
}

QString AppStore::installerDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/installers/KMusic/") + m_release.value("revision").toString();
}

void AppStore::refresh()
{
    if (m_state.value("busy").toBool()) return;
    QFile manifest(dataDirectory() + QStringLiteral("/manifest.json"));
    QJsonObject record;
    if (manifest.open(QIODevice::ReadOnly))
        record = QJsonDocument::fromJson(manifest.readAll()).object();
    const bool installed = record.value("appId").toString() == appId
        && QFileInfo(dataDirectory() + QStringLiteral("/current/bin/kmusic")).isExecutable();
    m_state["installed"] = installed;
    m_state["version"] = installed ? record.value("version").toString() : QString();
    emit changed();
}

void AppStore::setStage(const QString& stage)
{
    m_state["stage"] = stage;
    emit changed();
}

void AppStore::fail(const QString& code, const QString& message)
{
    m_killTimer.stop();
    m_deadline.stop();
    m_retryTimer.stop();
    m_elapsedTimer.stop();
    appendLog((code + ": " + message + '\n').toUtf8());
    m_log.close();
    m_state["busy"] = false;
    m_state["code"] = code;
    m_state["message"] = message;
    m_state["stage"] = "";
    refresh();
}

bool AppStore::validFile(const QString& relative) const
{
    QFile file(installerDirectory() + '/' + relative);
    if (!file.open(QIODevice::ReadOnly) || file.size() > maximumOutput) return false;
    const auto expected = m_release.value("sha256").toObject().value(relative).toString();
    return QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex()) == expected;
}

void AppStore::install() { begin(QStringLiteral("install")); }
void AppStore::uninstall() { begin(QStringLiteral("uninstall")); }

void AppStore::begin(const QString& action)
{
    if (m_state.value("busy").toBool()) return;
    if (!m_published) { fail(QStringLiteral("RELEASE_UNAVAILABLE")); return; }
    m_requestedAction = action;
    m_cancelled = false;
    m_sourceAttempt = 1;
    m_timeoutCode.clear();
    m_elapsed.start();
    m_elapsedTimer.start();
    m_state["elapsedSeconds"] = 0;
    m_state["attempt"] = 1;
    m_state["maxAttempts"] = 3;
    m_state["busy"] = true;
    m_state["code"] = "";
    m_state["message"] = "";
    m_state["diagnostics"] = "";
    m_state["dependencies"] = QVariantList{};
    m_state["logPath"] = "";
    const auto logRoot = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + QStringLiteral("/.local/state"))
        + QStringLiteral("/kos-settings/app-store");
    if (!QDir::isAbsolutePath(logRoot) || !QDir().mkpath(logRoot)) {
        fail(QStringLiteral("PERMISSION_DENIED")); return;
    }
    m_log.close();
    m_log.setFileName(logRoot + '/' + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".log");
    if (!m_log.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
        fail(QStringLiteral("PERMISSION_DENIED")); return;
    }
    m_log.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    m_state["logPath"] = m_log.fileName();
    setStage(QStringLiteral("bootstrap"));
    downloadNext(0);
}

void AppStore::downloadNext(int index, int attempt)
{
    if (index == installerFiles.size()) {
        run(m_requestedAction == "install" ? QStringLiteral("check") : m_requestedAction);
        return;
    }
    const QString relative = installerFiles.at(index);
    if (validFile(relative)) { downloadNext(index + 1); return; }
    const QString url = m_downloadBaseUrl
        + m_release.value("revision").toString() + '/' + relative;
    QNetworkRequest request{QUrl(url)};
    request.setTransferTimeout(m_bootstrapTimeout);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
    m_timeoutCode.clear();
    m_state["attempt"] = attempt;
    m_state["maxAttempts"] = 3;
    setStage(QStringLiteral("bootstrap"));
    m_deadline.start(m_bootstrapTimeout);
    auto* reply = m_network.get(request);
    m_reply = reply;
    connect(reply, &QNetworkReply::downloadProgress, this, [reply](qint64 received, qint64 total) {
        if (received > maximumOutput || total > maximumOutput) {
            reply->setProperty("tooLarge", true);
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, relative, index, attempt] {
        m_deadline.stop();
        m_reply = nullptr;
        reply->deleteLater();
        if (m_cancelled) { fail(QStringLiteral("CANCELLED")); return; }
        if (reply->property("tooLarge").toBool()) { fail(QStringLiteral("INTEGRITY_FAILED")); return; }
        if (reply->error() != QNetworkReply::NoError) {
            const auto error = reply->error();
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const bool timedOut = !m_timeoutCode.isEmpty() || error == QNetworkReply::TimeoutError;
            const bool transient = timedOut || error == QNetworkReply::ConnectionRefusedError
                || error == QNetworkReply::RemoteHostClosedError || error == QNetworkReply::HostNotFoundError
                || error == QNetworkReply::TemporaryNetworkFailureError || error == QNetworkReply::NetworkSessionFailedError
                || status == 408 || status == 429 || status >= 500;
            appendLog((relative + ": " + reply->errorString() + '\n').toUtf8());
            if (transient && attempt < 3) { scheduleRetry(index, attempt + 1); return; }
            fail(timedOut ? QStringLiteral("DOWNLOAD_TIMEOUT") : QStringLiteral("DOWNLOAD_FAILED"), reply->errorString());
            return;
        }
        const auto bytes = reply->readAll();
        const auto expected = m_release.value("sha256").toObject().value(relative).toString();
        if (bytes.size() > maximumOutput || QString::fromLatin1(
                QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex()) != expected) {
            fail(QStringLiteral("INTEGRITY_FAILED")); return;
        }
        const auto path = installerDirectory() + '/' + relative;
        if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
            fail(QStringLiteral("PERMISSION_DENIED")); return;
        }
        QSaveFile out(path);
        if (!out.open(QIODevice::WriteOnly) || out.write(bytes) != bytes.size() || !out.commit()) {
            fail(QStringLiteral("PERMISSION_DENIED")); return;
        }
        downloadNext(index + 1);
    });
}

void AppStore::scheduleRetry(int index, int attempt)
{
    m_deadline.stop();
    m_retryIndex = index;
    m_retryAttempt = attempt;
    m_state["attempt"] = attempt;
    m_state["maxAttempts"] = index >= 0 ? 3 : 5;
    appendLog((QStringLiteral("Retrying download, attempt %1/%2\n")
        .arg(attempt).arg(m_state.value("maxAttempts").toInt())).toUtf8());
    setStage(index >= 0 ? QStringLiteral("retry-bootstrap") : QStringLiteral("retry-download"));
    m_retryTimer.start(m_retryDelay * (attempt - 1));
}

void AppStore::processStage(const QString& stage)
{
    if (stage == "build" || stage == "install") m_leftDownload = true;
    if (m_cancelled || !m_timeoutCode.isEmpty()) return;
    if (stage != "check" && stage != "download" && stage != "build"
        && stage != "install" && stage != "uninstall" && stage != "status") return;
    if (m_state.value("stage") == stage) return; // Repeated progress cannot extend the deadline.
    m_state["attempt"] = m_sourceAttempt;
    m_state["maxAttempts"] = 5;
    const int timeout = stage == "download" ? m_downloadTimeout
        : stage == "build" ? 30 * 60 * 1000
        : (stage == "install" || stage == "uninstall") ? 5 * 60 * 1000 : 60000;
    m_deadline.start(timeout);
    setStage(stage);
}

void AppStore::run(const QString& action)
{
    // Recheck both files immediately before every invocation, including status.
    for (const auto& file : installerFiles) {
        if (!validFile(file)) { fail(QStringLiteral("INTEGRITY_FAILED")); return; }
    }
    m_action = action;
    m_output.clear();
    m_result = {};
    m_resultCount = 0;
    m_protocolError = false;
    m_timeoutCode.clear();
    m_leftDownload = false;
    // The install command first performs dependency checks, before it emits download/build.
    setStage(QString());
    processStage(action == "install" ? QStringLiteral("check") : action);
    QStringList args{installerDirectory() + QStringLiteral("/install.sh"), action};
    if (action == "install") args << QStringLiteral("--version") << m_release.value("revision").toString();
    m_process.setProgram(QStringLiteral("/bin/sh"));
    m_process.setArguments(args);
    m_process.start();
}

void AppStore::consumeLine(const QByteArray& line)
{
    if (line.trimmed().isEmpty()) return;
    QJsonParseError error;
    const auto event = QJsonDocument::fromJson(line, &error).object();
    const bool bootstrapFailure = event.value("type").toString() == "result"
        && event.value("success").isBool() && !event.value("success").toBool()
        && event.value("action").toString() == "unknown" && event.value("stage").toString() == "bootstrap";
    if (error.error != QJsonParseError::NoError || event.value("schemaVersion").toInt() != 1
        || event.value("appId").toString() != appId
        || (event.value("action").toString() != m_action && !bootstrapFailure)) {
        m_protocolError = true; return;
    }
    if (event.value("type").toString() == "progress" && m_resultCount == 0) {
        processStage(event.value("stage").toString());
    } else if (event.value("type").toString() == "result") {
        ++m_resultCount;
        m_result = event;
    } else {
        m_protocolError = true;
    }
}

void AppStore::appendLog(const QByteArray& bytes)
{
    if (m_log.isOpen()) {
        m_log.write(bytes.left(qMax<qint64>(0, maximumOutput - m_log.size())));
        m_log.flush();
    }
}

void AppStore::consumeOutput()
{
    const auto bytes = m_process.readAllStandardOutput();
    appendLog(bytes);
    m_output += bytes;
    if (m_output.size() > maximumOutput) {
        m_protocolError = true;
        m_output.clear();
        stopProcess(SIGTERM);
        m_killTimer.start(10000);
        return;
    }
    qsizetype newline;
    while ((newline = m_output.indexOf('\n')) >= 0) {
        consumeLine(m_output.left(newline));
        m_output.remove(0, newline + 1);
    }
}

void AppStore::finish(int exitCode, QProcess::ExitStatus status)
{
    m_killTimer.stop();
    stopProcess(SIGKILL);
    m_processGroup = 0;
    consumeOutput();
    if (!m_output.isEmpty()) consumeLine(m_output);
    m_output.clear();
    m_deadline.stop();
    const bool downloadFailed = !m_protocolError && m_resultCount == 1
        && m_result.value("success").isBool() && !m_result.value("success").toBool()
        && m_result.value("code").toString() == "DOWNLOAD_FAILED";
    // Only restart the disposable source-download phase. Never replay a build or installation.
    const bool retryable = !m_protocolError && !m_leftDownload && m_action == "install"
        && m_state.value("stage") == "download"
        && (m_timeoutCode == "DOWNLOAD_TIMEOUT" || downloadFailed);
    if (!m_cancelled && retryable && m_sourceAttempt < 5) {
        scheduleRetry(-1, ++m_sourceAttempt);
        return;
    }
    if (m_cancelled && !m_leftDownload) { fail(QStringLiteral("CANCELLED")); return; }
    if (!m_timeoutCode.isEmpty()) { fail(m_timeoutCode); return; }
    if (m_protocolError || m_resultCount != 1 || !m_result.value("success").isBool()) {
        fail(QStringLiteral("RESULT_UNKNOWN")); return;
    }
    if (m_action != "status" && !m_result.value("logPath").toString().isEmpty())
        m_state["logPath"] = m_result.value("logPath").toString();
    m_state["dependencies"] = m_result.value("details").toObject().value("dependencies").toArray().toVariantList();
    const auto code = m_result.value("code").toString();
    if (code.isEmpty()) { fail(QStringLiteral("RESULT_UNKNOWN")); return; }
    if (!m_result.value("success").toBool() || exitCode != 0 || status != QProcess::NormalExit) {
        fail(m_result.value("success").toBool() ? QStringLiteral("RESULT_UNKNOWN") : code,
            m_result.value("message").toString());
        return;
    }
    if (m_cancelled) { fail(QStringLiteral("RESULT_UNKNOWN")); return; }
    const bool expected = m_action == "install" ? (code == "INSTALLED" || code == "ALREADY_INSTALLED") : code == "OK";
    if (!expected || (m_action == "install" && m_result.value("version") != m_release.value("revision"))) {
        fail(QStringLiteral("RESULT_UNKNOWN")); return;
    }
    if (m_action == "check") { run(QStringLiteral("install")); return; }
    if (m_action != "status") { run(QStringLiteral("status")); return; }
    m_elapsedTimer.stop();
    m_log.close();
    m_state["busy"] = false;
    m_state["stage"] = "";
    m_state["code"] = "";
    refresh();
    const bool expectedInstalled = m_requestedAction == "install";
    if (!m_result.value("installed").isBool()
        || m_result.value("installed").toBool() != expectedInstalled
        || m_state.value("installed").toBool() != expectedInstalled)
        fail(QStringLiteral("RESULT_UNKNOWN"));
}

void AppStore::stopProcess(int signal)
{
    const auto pid = m_processGroup > 0 ? m_processGroup : m_process.processId();
    if (pid > 0) ::kill(-pid, signal);
}

void AppStore::cancel()
{
    if (!m_state.value("busy").toBool()) return;
    m_cancelled = true;
    m_deadline.stop();
    if (m_retryTimer.isActive()) {
        m_retryTimer.stop();
        fail(QStringLiteral("CANCELLED"));
        return;
    }
    setStage(QStringLiteral("cancelling"));
    if (m_reply) { m_reply->abort(); return; }
    stopProcess(SIGTERM);
    m_killTimer.start(10000);
}

void AppStore::open()
{
    if (m_state.value("busy").toBool()) return;
    refresh();
    if (!m_state.value("installed").toBool()) return;
    const QString desktop = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/applications/kmusic.desktop");
    const QString expected = QFileInfo(dataDirectory() + QStringLiteral("/current/share/applications/kmusic.desktop")).canonicalFilePath();
    if (expected.isEmpty() || QFileInfo(desktop).canonicalFilePath() != expected) {
        fail(QStringLiteral("OPEN_FAILED")); return;
    }
    auto* job = new KIO::ApplicationLauncherJob(KService::Ptr(new KService(desktop)), this);
    connect(job, &KJob::result, this, [this](KJob* finished) {
        if (finished->error()) fail(QStringLiteral("OPEN_FAILED"), finished->errorText());
    });
    job->start();
}

void AppStore::openLog()
{
    const auto path = QFileInfo(m_state.value("logPath").toString()).canonicalFilePath();
    const auto stateHome = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + QStringLiteral("/.local/state"));
    const auto root = QFileInfo(stateHome + QStringLiteral("/kmusic-installer")).canonicalFilePath() + "/";
    const auto controllerRoot = QFileInfo(stateHome + QStringLiteral("/kos-settings/app-store")).canonicalFilePath() + "/";
    if (!path.isEmpty() && ((root != "/" && path.startsWith(root))
            || (controllerRoot != "/" && path.startsWith(controllerRoot))))
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void AppStore::openRepository() { QDesktopServices::openUrl(QUrl(repository)); }
