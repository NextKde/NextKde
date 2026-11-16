#include "../src/daemon/StatusPanelData.h"
#include "../src/daemon/BatteryData.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#undef NDEBUG
#include <cassert>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    const auto parsed = KosPlatform::parseApplicationTraffic(
        "ESTAB 0 0 127.0.0.1:40 127.0.0.1:99 users:((\"browser\",pid=123,fd=2),(\"helper\",pid=124,fd=3)) ino:321 bytes_sent:4096 bytes_received:8192\n"
        "ESTAB 0 0 1.2.3.4:40 5.6.7.8:99 ino:322 bytes_sent:999\n"
        "ESTAB 0 0 1.2.3.4:40 5.6.7.8:99 users:((\"mail\",pid=222,fd=3)) ino:323\n");
    const auto sockets = parsed.value("sockets").toArray();
    assert(sockets.size() == 2);
    assert(sockets.at(0).toObject().value("name") == "browser");
    assert(sockets.at(0).toObject().value("rxBytes").toDouble() == 8192);
    assert(sockets.at(1).toObject().value("txBytes").toDouble() == 0);
    const auto profiles = KosPlatform::parsePowerProfiles("  performance:\n    Degraded: no\n* balanced:\n  power-saver:\n");
    assert(profiles.value("profiles").toArray().size() == 3);
    assert(profiles.value("activeProfile") == "balanced");
    assert(profiles.value("degraded").toString().isEmpty());
    const auto limited = KosPlatform::parsePowerProfiles("* performance:\n    Degraded: high-operating-temperature\n  balanced:\n");
    assert(limited.value("degraded") == "high-operating-temperature");
    assert(KosPlatform::parsePowerProfiles("not a profile").value("profiles").toArray().isEmpty());

    QTemporaryDir supplies;
    assert(supplies.isValid());
    const auto supply = [&supplies](const QString &name, const QByteArray &contents) {
        assert(QDir(supplies.path()).mkpath(name));
        QFile file(supplies.path() + '/' + name + "/uevent");
        assert(file.open(QIODevice::WriteOnly));
        assert(file.write(contents) == contents.size());
    };
    supply("BAT0", "POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_PRESENT=1\n"
        "POWER_SUPPLY_CHARGE_FULL=4500000\nPOWER_SUPPLY_CHARGE_FULL_DESIGN=5000000\n"
        "POWER_SUPPLY_VOLTAGE_NOW=12000000\nPOWER_SUPPLY_VOLTAGE_MIN_DESIGN=11000000\n"
        "POWER_SUPPLY_CURRENT_NOW=-1000000\nPOWER_SUPPLY_CYCLE_COUNT=0\nPOWER_SUPPLY_TEMP=325\n");
    supply("mouse", "POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_SCOPE=Device\nPOWER_SUPPLY_PRESENT=1\n");
    supply("removed", "POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_PRESENT=0\n");
    supply("AC", "POWER_SUPPLY_TYPE=Mains\nPOWER_SUPPLY_ONLINE=1\n");
    supply("offline", "POWER_SUPPLY_TYPE=USB\nPOWER_SUPPLY_ONLINE=0\nPOWER_SUPPLY_POWER_NOW=99999999\n");
    supply("USB", "POWER_SUPPLY_TYPE=USB_PD\nPOWER_SUPPLY_ONLINE=1\n"
        "POWER_SUPPLY_VOLTAGE_NOW=20000000\nPOWER_SUPPLY_CURRENT_NOW=1500000\n"
        "POWER_SUPPLY_VOLTAGE_MAX=20000000\nPOWER_SUPPLY_CURRENT_MAX=3250000\n");
    const auto details = KosPlatform::readBatteryDetails(supplies.path());
    assert(details.value("available").toBool());
    assert(details.value("complete").toBool());
    assert(details.value("batteries").toArray().size() == 1);
    const auto pack = details.value("batteries").toArray().first().toObject();
    assert(pack.value("chargeFullMah").toDouble() == 4500);
    assert(pack.value("energyFullWh").toDouble() == 49.5);
    assert(pack.value("energyDesignWh").toDouble() == 55);
    assert(pack.value("currentMa").toDouble() == -1000);
    assert(pack.value("powerWatts").toDouble() == 12);
    assert(pack.value("cycles").toInt(-1) == 0);
    assert(pack.value("temperature").toDouble() == 32.5);
    const auto adapters = details.value("adapters").toArray();
    assert(adapters.size() == 2);
    assert(!adapters.first().toObject().contains("powerWatts")); // missing != battery power
    assert(adapters.last().toObject().value("powerWatts").toDouble() == 30);
    assert(adapters.last().toObject().value("ratedPowerWatts").toDouble() == 65);
    supply("BAT0", "POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_PRESENT=1\n"
        "POWER_SUPPLY_ENERGY_FULL=49000000\nPOWER_SUPPLY_ENERGY_FULL_DESIGN=bad\n"
        "POWER_SUPPLY_POWER_NOW=0\nPOWER_SUPPLY_CYCLE_COUNT=-1\nPOWER_SUPPLY_TEMP=-50\n");
    const auto sparse = KosPlatform::readBatteryDetails(supplies.path()).value("batteries").toArray().first().toObject();
    assert(sparse.value("energyFullWh").toDouble() == 49);
    assert(!sparse.contains("energyDesignWh") && !sparse.contains("cycles"));
    assert(sparse.contains("powerWatts") && sparse.value("powerWatts").toDouble() == 0);
    assert(sparse.value("temperature").toDouble() == -5);
    supply("BAT1", "POWER_SUPPLY_TYPE=Battery\nPOWER_SUPPLY_ENERGY_FULL=20000000\n");
    assert(KosPlatform::readBatteryDetails(supplies.path()).value("complete").toBool());
    assert(QFile::remove(supplies.path() + "/BAT1/uevent"));
    const auto partial = KosPlatform::readBatteryDetails(supplies.path());
    assert(partial.value("batteries").toArray().size() == 1);
    assert(!partial.value("complete").toBool());
    assert(QDir(supplies.path() + "/BAT1").removeRecursively());
    supply("BAT0", QByteArray(17000, 'x'));
    assert(!KosPlatform::readBatteryDetails(supplies.path()).value("complete").toBool());
    assert(!KosPlatform::readBatteryDetails(supplies.path()).value("available").toBool());
    assert(!KosPlatform::readBatteryDetails(supplies.path() + "/missing").value("available").toBool());
    assert(!KosPlatform::readBatteryDetails(supplies.path() + "/missing").value("complete").toBool());
}
