#include "sourcehost/source_protocol.h"
#include "sourcehost/sourcehost_client.h"

#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <QThread>

#include <cstdlib>
#include <utility>

#ifdef Q_OS_WIN
#include <windows.h>
#include <tlhelp32.h>
#endif

using listenfree::sourcehost::MessageType;
using listenfree::sourcehost::SourceHostClient;
using listenfree::sourcehost::SourceMessage;

namespace {

QString faultHostPath() {
    return QCoreApplication::applicationDirPath() + QStringLiteral("/listenfree-sourcehost-fault-host.exe");
}

SourceMessage request(QString id, bool spawnTree = false) {
    SourceMessage message;
    message.type = MessageType::Search;
    message.requestId = std::move(id);
    if (spawnTree) message.payload.insert(QStringLiteral("spawnTree"), true);
    return message;
}

bool processExited(quint64 pid) {
#ifdef Q_OS_WIN
    if (pid == 0) return true;
    HANDLE handle = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(pid));
    if (handle == nullptr) return true;
    const DWORD status = WaitForSingleObject(handle, 0);
    CloseHandle(handle);
    return status == WAIT_OBJECT_0;
#else
    Q_UNUSED(pid);
    return true;
#endif
}

void setFaultMode(const QString& value) { qputenv("LISTENFREE_FAULT_MODE", value.toUtf8()); }
void clearFaultMode() { qunsetenv("LISTENFREE_FAULT_MODE"); }

[[noreturn]] void crashCurrentProcess() {
#ifdef Q_OS_WIN
    TerminateProcess(GetCurrentProcess(), 86);
#endif
    std::abort();
}

QList<quint64> readProcessIds(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    QList<quint64> result;
    for (const auto& line : file.readAll().split('\n')) {
        bool valid = false;
        const quint64 pid = line.trimmed().toULongLong(&valid);
        if (valid && pid != 0) result.push_back(pid);
    }
    return result;
}

quint64 currentHandleCount() {
#ifdef Q_OS_WIN
    DWORD count = 0;
    return GetProcessHandleCount(GetCurrentProcess(), &count) ? count : 0;
#else
    return 0;
#endif
}

quint64 currentThreadCount() {
#ifdef Q_OS_WIN
    quint64 count = 0;
    const DWORD processId = GetCurrentProcessId();
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    THREADENTRY32 entry{};
    entry.dwSize = sizeof(entry);
    if (Thread32First(snapshot, &entry)) {
        do {
            if (entry.th32OwnerProcessID == processId) ++count;
        } while (Thread32Next(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return count;
#else
    return 0;
#endif
}

int runParentCrashLauncher(const QString& hostPath, const QString& pidPath) {
    qputenv("LISTENFREE_FAULT_MODE", QByteArrayLiteral("hang"));
    qputenv("LISTENFREE_CHILD_PID_FILE", pidPath.toUtf8());
    SourceHostClient client(hostPath);
    QTimer poll;
    poll.setInterval(10);
    QObject::connect(&poll, &QTimer::timeout, &poll, [pidPath] {
        if (readProcessIds(pidPath).size() == 3) crashCurrentProcess();
    });
    QObject::connect(&client, &SourceHostClient::ready, &client, [&client, &poll] {
        if (!client.request(request(QStringLiteral("parent-crash-tree"), true), 5000)) {
            QCoreApplication::exit(3);
            return;
        }
        poll.start();
    });
    QTimer::singleShot(5000, &client, [] { QCoreApplication::exit(4); });
    if (!client.start()) return 2;
    return QCoreApplication::exec();
}

} // namespace

class SourceHostFaultTests final : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() { QVERIFY2(QFileInfo::exists(faultHostPath()), qPrintable(faultHostPath())); }
    void cleanup() { clearFaultMode(); qunsetenv("LISTENFREE_CHILD_PID_FILE"); }

    void startupHandshakeRequest();
    void slowStartupRemainsReady();
    void handshakeFailureRetriesAndRecovers();
    void handshakeRetriesAreBounded();
    void silentHostTimesOut();
    void busyParentAcceptsBufferedHandshake();
    void failedAndMalformedStartup();
    void cancellationAndTimeoutAreExactlyOnce();
    void writeFailureIsTerminal();
    void outboundBackpressureIsBounded();
    void cancellationRespectsOutboundBackpressure();
    void oversizedRequestIdIsRejected();
    void crashAutoRestart();
    void repeatedLifecycleIsStable();
    void gracefulStopCleansProcessTree();
    void forcedTerminationCleansProcessTree();
    void parentCrashCleansProcessTree();
    void destructorCleansProcessTree();
};

void SourceHostFaultTests::startupHandshakeRequest() {
    setFaultMode(QStringLiteral("normal"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client.request(request(QStringLiteral("request-1")), 1000));
    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 1, 1000);
    QCOMPARE(finished.at(0).at(1).value<SourceHostClient::RequestTerminal>(),
             SourceHostClient::RequestTerminal::Succeeded);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
}

void SourceHostFaultTests::failedAndMalformedStartup() {
    {
        SourceHostClient client(QCoreApplication::applicationDirPath() + QStringLiteral("/missing-sourcehost.exe"));
        QSignalSpy errors(&client, &SourceHostClient::protocolError);
        QVERIFY(client.start());
        QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
        QVERIFY(errors.count() > 0);
    }
    for (const QString& fault : {QStringLiteral("bad-handshake")}) {
        setFaultMode(fault);
        SourceHostClient client(faultHostPath());
        client.setAutoRestart(false);
        QSignalSpy errors(&client, &SourceHostClient::protocolError);
        QVERIFY(client.start());
        QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2500);
        QVERIFY(errors.count() > 0);
        clearFaultMode();
    }
}

void SourceHostFaultTests::cancellationAndTimeoutAreExactlyOnce() {
    setFaultMode(QStringLiteral("hang"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy timedOut(&client, &SourceHostClient::requestTimedOut);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client.request(request(QStringLiteral("cancel-1")), 100));
    client.cancel("cancel-1");
    client.cancel("cancel-1");
    QCOMPARE(finished.count(), 1);
    QCOMPARE(finished.at(0).at(1).value<SourceHostClient::RequestTerminal>(),
             SourceHostClient::RequestTerminal::Cancelled);
    QVERIFY(client.request(request(QStringLiteral("timeout-1")), 50));
    QTRY_COMPARE_WITH_TIMEOUT(timedOut.count(), 1, 1000);
    QCOMPARE(finished.count(), 2);
    QCOMPARE(finished.at(1).at(1).value<SourceHostClient::RequestTerminal>(),
             SourceHostClient::RequestTerminal::TimedOut);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
}

void SourceHostFaultTests::writeFailureIsTerminal() {
    setFaultMode(QStringLiteral("writefail"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client.request(request(QStringLiteral("write-fail")), 1000));
    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 1, 2000);
    const auto terminal = finished.at(0).at(1).value<SourceHostClient::RequestTerminal>();
    QCOMPARE(terminal, SourceHostClient::RequestTerminal::WriteFailed);
    QTest::qWait(50);
    QCOMPARE(finished.count(), 1);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
}

void SourceHostFaultTests::slowStartupRemainsReady() {
    setFaultMode(QStringLiteral("delay-handshake"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 4000);
    QCOMPARE(client.state(), SourceHostClient::HostState::Ready);
    QCOMPARE(errors.count(), 0);
}

void SourceHostFaultTests::handshakeFailureRetriesAndRecovers() {
    setFaultMode(QStringLiteral("bad-handshake"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy restarted(&client, &SourceHostClient::restarted);
    connect(&client, &SourceHostClient::protocolError, &client, [](const QString& error) {
        if (error == QStringLiteral("invalid-sourcehost-handshake"))
            setFaultMode(QStringLiteral("normal"));
    });
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 4000);
    QCOMPARE(restarted.count(), 1);
}

void SourceHostFaultTests::handshakeRetriesAreBounded() {
    setFaultMode(QStringLiteral("bad-handshake"));
    SourceHostClient client(faultHostPath());
    QSignalSpy crashed(&client, &SourceHostClient::crashed);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(crashed.count(), 4, 5000);
    QTRY_COMPARE(client.state(), SourceHostClient::HostState::Stopped);
    QTest::qWait(500);
    QCOMPARE(crashed.count(), 4);
    QVERIFY(!client.running());
}

void SourceHostFaultTests::silentHostTimesOut() {
    setFaultMode(QStringLiteral("never-handshake"));
    SourceHostClient client(faultHostPath());
    client.setAutoRestart(false);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QVERIFY(client.start());
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 8000);
    QVERIFY(errors.contains({QStringLiteral("sourcehost-handshake-timeout")}));
}

void SourceHostFaultTests::busyParentAcceptsBufferedHandshake() {
    setFaultMode(QStringLiteral("delay-handshake"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QVERIFY(client.start());
    QTest::qWait(250); // Send Hello, then simulate a busy GUI during shell startup.
    QThread::msleep(5500);
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QCOMPARE(errors.count(), 0);
}

void SourceHostFaultTests::outboundBackpressureIsBounded() {
    setFaultMode(QStringLiteral("backpressure"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);

    int accepted = 0;
    for (int index = 0; index < 300; ++index) {
        auto message = request(QStringLiteral("backpressure-%1").arg(index));
        message.payload.insert(QStringLiteral("blob"), QString(64 * 1024, QChar('x')));
        if (!client.request(message, 5000)) break;
        ++accepted;
    }
    bool boundedError = false;
    for (const auto& values : errors) {
        if (values.at(0).toString() == QStringLiteral("outgoing-write-buffer-full")) {
            boundedError = true;
            break;
        }
    }
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 3000);
    QCOMPARE(finished.count(), accepted);
    QVERIFY(accepted > 0);
    QVERIFY2(accepted < 100, qPrintable(QStringLiteral("accepted=%1").arg(accepted)));
    QVERIFY(boundedError);
}

void SourceHostFaultTests::cancellationRespectsOutboundBackpressure() {
    setFaultMode(QStringLiteral("backpressure"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);

    QString firstId;
    int accepted = 0;
    for (int index = 0; index < 300; ++index) {
        const QString id = QString(64 * 1024, QChar('c')) + QString::number(index);
        if (!client.request(request(id), 5000)) break;
        if (firstId.isEmpty()) firstId = id;
        ++accepted;
    }
    QVERIFY(!firstId.isEmpty());
    const qsizetype errorsBeforeCancel = errors.count();
    client.cancel(firstId.toStdString());
    QCOMPARE(finished.count(), 1);
    const bool cancelWasBounded = errors.count() == errorsBeforeCancel + 1 &&
                                  errors.last().at(0).toString() ==
                                      QStringLiteral("outgoing-write-buffer-full");

    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 3000);
    QCOMPARE(finished.count(), accepted);
    QVERIFY(cancelWasBounded);
}

void SourceHostFaultTests::oversizedRequestIdIsRejected() {
    setFaultMode(QStringLiteral("normal"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy errors(&client, &SourceHostClient::protocolError);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);

    const auto oversized = request(QString(256 * 1024 + 1, QChar('x')));
    QVERIFY(!client.request(oversized, 1000));
    bool foundBoundedError = false;
    for (const auto& values : errors) {
        if (values.at(0).toString() == QStringLiteral("request-id-too-large")) {
            foundBoundedError = true;
            break;
        }
    }
    QVERIFY(foundBoundedError);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
}

void SourceHostFaultTests::crashAutoRestart() {
    setFaultMode(QStringLiteral("crash"));
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QSignalSpy crashed(&client, &SourceHostClient::crashed);
    QSignalSpy restarted(&client, &SourceHostClient::restarted);
    QSignalSpy finished(&client, &SourceHostClient::requestFinished);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    for (int cycle = 0; cycle < 3; ++cycle) {
        QVERIFY(client.request(request(QStringLiteral("crash-%1").arg(cycle)), 1000));
        QTRY_COMPARE_WITH_TIMEOUT(crashed.count(), cycle + 1, 2000);
        QCOMPARE(finished.count(), cycle + 1);
        QCOMPARE(finished.at(cycle).at(1).value<SourceHostClient::RequestTerminal>(),
                 SourceHostClient::RequestTerminal::HostCrashed);
        QTRY_COMPARE_WITH_TIMEOUT(restarted.count(), cycle + 1, 3000);
        QVERIFY(client.running());
    }
    QVERIFY(client.request(request(QStringLiteral("crash-limit")), 1000));
    QTRY_COMPARE_WITH_TIMEOUT(crashed.count(), 4, 2000);
    QTRY_COMPARE_WITH_TIMEOUT(client.state(), SourceHostClient::HostState::Stopped, 2000);
    QCOMPARE(restarted.count(), 3);
    QCOMPARE(finished.count(), 4);
    QCOMPARE(finished.at(3).at(1).value<SourceHostClient::RequestTerminal>(),
             SourceHostClient::RequestTerminal::HostCrashed);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
}

void SourceHostFaultTests::repeatedLifecycleIsStable() {
    setFaultMode(QStringLiteral("normal"));
    SourceHostClient client(faultHostPath());
    quint64 stableHandles = 0;
    quint64 stableThreads = 0;
    for (int i = 0; i < 8; ++i) {
        QSignalSpy ready(&client, &SourceHostClient::ready);
        QVERIFY(client.start());
        QVERIFY(!client.start());
        QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
        client.stop();
        client.stop();
        QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        QCOMPARE(client.findChildren<QTimer*>().size(), 0);
        if (i == 2) {
            stableHandles = currentHandleCount();
            stableThreads = currentThreadCount();
            QVERIFY(stableHandles > 0);
            QVERIFY(stableThreads > 0);
        } else if (i > 2) {
            QCOMPARE(currentHandleCount(), stableHandles);
            QCOMPARE(currentThreadCount(), stableThreads);
        }
    }
}

void SourceHostFaultTests::gracefulStopCleansProcessTree() {
    setFaultMode(QStringLiteral("hang"));
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString pidPath = dir.filePath(QStringLiteral("child.pid"));
    qputenv("LISTENFREE_CHILD_PID_FILE", pidPath.toUtf8());
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client.request(request(QStringLiteral("tree-1"), true), 1000));
    QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(pidPath), 1000);
    QTRY_COMPARE_WITH_TIMEOUT(readProcessIds(pidPath).size(), 3, 2000);
    const auto processIds = readProcessIds(pidPath);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 2000);
    QCOMPARE(processIds.size(), 3);
    for (const quint64 pid : processIds) {
        QTRY_VERIFY_WITH_TIMEOUT(processExited(pid), 3000);
        QVERIFY(processExited(pid));
    }
}

void SourceHostFaultTests::forcedTerminationCleansProcessTree() {
    setFaultMode(QStringLiteral("ignore-stop"));
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString pidPath = dir.filePath(QStringLiteral("child.pid"));
    qputenv("LISTENFREE_CHILD_PID_FILE", pidPath.toUtf8());
    SourceHostClient client(faultHostPath());
    QSignalSpy ready(&client, &SourceHostClient::ready);
    QVERIFY(client.start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client.request(request(QStringLiteral("tree-force"), true), 1000));
    QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(pidPath), 1000);
    QTRY_COMPARE_WITH_TIMEOUT(readProcessIds(pidPath).size(), 3, 2000);
    const auto processIds = readProcessIds(pidPath);
    client.stop();
    QTRY_VERIFY_WITH_TIMEOUT(!client.running(), 3000);
    QCOMPARE(processIds.size(), 3);
    for (const quint64 pid : processIds) {
        QTRY_VERIFY_WITH_TIMEOUT(processExited(pid), 3000);
        QVERIFY(processExited(pid));
    }
}

void SourceHostFaultTests::parentCrashCleansProcessTree() {
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString pidPath = dir.filePath(QStringLiteral("parent-crash-tree.pid"));
    QProcess launcher;
    QSignalSpy finished(&launcher, &QProcess::finished);
    launcher.start(QCoreApplication::applicationFilePath(),
                   {QStringLiteral("--parent-crash-launcher"), faultHostPath(), pidPath});
    QTRY_COMPARE_WITH_TIMEOUT(readProcessIds(pidPath).size(), 3, 4000);
    const auto processIds = readProcessIds(pidPath);
    QTRY_COMPARE_WITH_TIMEOUT(finished.count(), 1, 4000);
    QVERIFY(launcher.exitStatus() == QProcess::CrashExit || launcher.exitCode() != 0);
    for (const quint64 pid : processIds) {
        QTRY_VERIFY_WITH_TIMEOUT(processExited(pid), 3000);
        QVERIFY(processExited(pid));
    }
    QTRY_VERIFY_WITH_TIMEOUT(QCoreApplication::instance()->findChildren<QProcess*>().isEmpty(), 3000);
}

void SourceHostFaultTests::destructorCleansProcessTree() {
    setFaultMode(QStringLiteral("hang"));
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString pidPath = dir.filePath(QStringLiteral("destructor-tree.pid"));
    qputenv("LISTENFREE_CHILD_PID_FILE", pidPath.toUtf8());
    auto client = std::make_unique<SourceHostClient>(faultHostPath());
    QSignalSpy ready(client.get(), &SourceHostClient::ready);
    QVERIFY(client->start());
    QTRY_COMPARE_WITH_TIMEOUT(ready.count(), 1, 2000);
    QVERIFY(client->request(request(QStringLiteral("destructor-tree"), true), 1000));
    QTRY_COMPARE_WITH_TIMEOUT(readProcessIds(pidPath).size(), 3, 2000);
    const auto processIds = readProcessIds(pidPath);

    client.reset();

    for (const quint64 pid : processIds) {
        QTRY_VERIFY_WITH_TIMEOUT(processExited(pid), 3000);
        QVERIFY(processExited(pid));
    }
}

int main(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);
    const QStringList arguments = app.arguments();
    if (arguments.size() == 4 && arguments.at(1) == QStringLiteral("--parent-crash-launcher")) {
        return runParentCrashLauncher(arguments.at(2), arguments.at(3));
    }
    SourceHostFaultTests tests;
    return QTest::qExec(&tests, argc, argv);
}

#include "sourcehost_fault_tests.moc"
