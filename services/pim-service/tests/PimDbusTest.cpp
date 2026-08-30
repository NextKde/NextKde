#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

namespace {

constexpr auto serviceName = "org.nextkde.Kos.Pim1";
constexpr auto objectPath = "/Pim";
constexpr auto interfaceName = "org.nextkde.Kos.Pim1";

QJsonObject parseObject(const QString &encoded)
{
    return QJsonDocument::fromJson(encoded.toUtf8()).object();
}

QString encode(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

} // namespace

class PimDbusTest : public QObject {
    Q_OBJECT

private slots:
    void servicePublishesMutations();
};

void PimDbusTest::servicePublishesMutations()
{
    const QStringList arguments = QCoreApplication::arguments();
    QVERIFY2(arguments.size() >= 2, "PIM service executable argument is missing");
    QTemporaryDir storage;
    QVERIFY(storage.isValid());

    QProcess service;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("KOS_PIM_STORAGE_DIR"), storage.path());
    service.setProcessEnvironment(environment);
    service.setProgram(arguments.at(1));
    service.start();
    QVERIFY(service.waitForStarted(5000));

    QDBusConnectionInterface *busInterface = QDBusConnection::sessionBus().interface();
    QVERIFY(busInterface);
    QTRY_VERIFY_WITH_TIMEOUT(
        busInterface->isServiceRegistered(QString::fromLatin1(serviceName)).value(), 5000);

    QDBusInterface pim(QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
                       QString::fromLatin1(interfaceName), QDBusConnection::sessionBus());
    QVERIFY2(pim.isValid(), qPrintable(pim.lastError().message()));
    QSignalSpy changedSpy(&pim, SIGNAL(changed(qulonglong)));
    QVERIFY(changedSpy.isValid());

    const QDBusReply<QString> createReply = pim.call(
        QStringLiteral("createTodo"), encode({
            {QStringLiteral("title"), QStringLiteral("Cross-process task")},
            {QStringLiteral("listId"), QStringLiteral("inbox")},
        }));
    QVERIFY2(createReply.isValid(), qPrintable(createReply.error().message()));
    const QJsonObject created = parseObject(createReply.value());
    QVERIFY(created.value(QStringLiteral("ok")).toBool());
    const QString uid = created.value(QStringLiteral("item")).toObject()
                            .value(QStringLiteral("id")).toString();
    QVERIFY(!uid.isEmpty());
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 1, 3000);

    const QDBusReply<QString> snapshotReply = pim.call(QStringLiteral("snapshot"));
    QVERIFY(snapshotReply.isValid());
    const QJsonObject snapshot = parseObject(snapshotReply.value());
    QCOMPARE(snapshot.value(QStringLiteral("schemaVersion")).toInt(), 1);
    const QJsonArray todos = snapshot.value(QStringLiteral("todos")).toArray();
    QCOMPARE(todos.size(), 1);
    QCOMPARE(todos.first().toObject().value(QStringLiteral("id")).toString(), uid);

    const QDBusReply<QString> updateReply = pim.call(
        QStringLiteral("updateTodo"), uid, encode({
            {QStringLiteral("completed"), true},
        }));
    QVERIFY(updateReply.isValid());
    QVERIFY(parseObject(updateReply.value()).value(QStringLiteral("ok")).toBool());
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 2, 3000);

    service.terminate();
    if (!service.waitForFinished(3000)) {
        service.kill();
        QVERIFY(service.waitForFinished(3000));
    }
}

QTEST_GUILESS_MAIN(PimDbusTest)

#include "PimDbusTest.moc"
