#include "PowerSettings.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QTemporaryDir>
#include <QThread>
#undef NDEBUG
#include <cassert>

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QTemporaryDir root;
    assert(root.isValid());
    const auto state = root.filePath("mode");
    { QFile f(state); assert(f.open(QIODevice::WriteOnly)); f.write("balanced"); }
    QFile helper(root.filePath("powerprofilesctl"));
    assert(helper.open(QIODevice::WriteOnly));
    helper.write(R"(#!/usr/bin/python3
import os,pathlib,sys
p=pathlib.Path(os.environ['TEST_POWER_STATE'])
if sys.argv[1]=='list':
 for mode in ['power-saver','balanced','performance']:
  print(('* ' if p.read_text()==mode else '  ')+mode+':')
elif sys.argv[1]=='set':
 if sys.argv[2]=='performance': sys.exit(1)
 if os.environ.get('TEST_REJECT_POWER')!='1': p.write_text(sys.argv[2])
)");
    helper.close();
    helper.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    qputenv("PATH", root.path().toUtf8()+":"+qgetenv("PATH"));
    qputenv("TEST_POWER_STATE", state.toUtf8());
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent/kos-power-test");
    PowerSettings settings;
    auto wait = [&] {
        QElapsedTimer timer; timer.start();
        while(settings.state()["busy"].toBool() && timer.elapsed()<5000) {
            app.processEvents(); QThread::msleep(2);
        }
        assert(!settings.state()["busy"].toBool());
    };
    settings.refresh(); wait();
    assert(settings.state()["activeProfile"]=="balanced");
    assert(settings.state()["profiles"].toStringList().size()==3);
    settings.setProfile("power-saver"); wait();
    assert(settings.state()["activeProfile"]=="power-saver");
    settings.setProfile("performance"); wait();
    assert(settings.state()["activeProfile"]=="power-saver");
    assert(!settings.state()["error"].toString().isEmpty());
    qputenv("TEST_REJECT_POWER","1");
    settings.setProfile("balanced"); wait();
    assert(settings.state()["activeProfile"]=="power-saver");
    assert(settings.state()["error"].toString().contains("did not keep"));
    settings.setProfile("invalid");
    assert(!settings.state()["busy"].toBool());
    assert(QMetaObject::invokeMethod(&settings,"systemChanged",Qt::DirectConnection,
        Q_ARG(QString,QStringLiteral("net.hadess.PowerProfiles")),
        Q_ARG(QVariantMap,(QVariantMap{{"ActiveProfile","performance"}})), Q_ARG(QStringList,QStringList{})));
    assert(settings.state()["activeProfile"]=="performance");
    wait();
    qInfo("Power settings: modes, confirmed writes, denial, rejection and external signals passed");
}
