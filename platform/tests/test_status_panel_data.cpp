#include "../src/daemon/StatusPanelData.h"
#include <QCoreApplication>
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
}
