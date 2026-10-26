#pragma once

#include <QDir>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <cmath>
#include <optional>

namespace KosPlatform {

// Linux power_supply uevents use micro-units, except temperature (tenths °C).
// Keep absent/invalid attributes absent: 0 is a valid current or cycle count.
inline QJsonObject readBatteryDetails(const QString &root = QStringLiteral("/sys/class/power_supply"))
{
    QJsonArray batteries, adapters;
    const auto entries = QDir(root).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const auto &name : entries.mid(0, 64)) {
        QFile file(root + '/' + name + QStringLiteral("/uevent"));
        if (!file.open(QIODevice::ReadOnly)) continue;
        const auto data = file.read(16385);
        if (data.size() > 16384) continue;
        QHash<QByteArray, QByteArray> fields;
        for (const auto &line : data.split('\n')) {
            const auto split = line.indexOf('=');
            if (split > 0) fields.insert(line.left(split), line.mid(split + 1).trimmed());
        }
        const auto number = [&fields](const char *key, double divisor = 1.0) -> std::optional<double> {
            bool ok = false;
            const double value = fields.value(QByteArray("POWER_SUPPLY_") + key).toDouble(&ok) / divisor;
            if (!ok || !std::isfinite(value)) return std::nullopt;
            return value;
        };
        const auto put = [&number](QJsonObject &object, const char *key, const char *attribute,
                                   double divisor, bool signedValue = false) {
            const auto value = number(attribute, divisor);
            if (value && (signedValue || *value >= 0)) object.insert(QString::fromLatin1(key), *value);
        };
        const auto type = fields.value("POWER_SUPPLY_TYPE");
        if (type == "Battery") {
            if (fields.value("POWER_SUPPLY_SCOPE") == "Device" || number("PRESENT") == 0) continue;
            QJsonObject battery{{QStringLiteral("name"), name},
                {QStringLiteral("model"), QString::fromUtf8(fields.value("POWER_SUPPLY_MODEL_NAME"))}};
            put(battery, "energyFullWh", "ENERGY_FULL", 1e6);
            put(battery, "energyDesignWh", "ENERGY_FULL_DESIGN", 1e6);
            put(battery, "chargeFullMah", "CHARGE_FULL", 1e3);
            put(battery, "chargeDesignMah", "CHARGE_FULL_DESIGN", 1e3);
            put(battery, "voltage", "VOLTAGE_NOW", 1e6);
            put(battery, "currentMa", "CURRENT_NOW", 1e3, true);
            put(battery, "powerWatts", "POWER_NOW", 1e6, true);
            put(battery, "cycles", "CYCLE_COUNT", 1);
            put(battery, "temperature", "TEMP", 10, true);
            // Charge-based drivers may omit POWER_NOW; this is battery power,
            // never adapter input power or its rated wattage.
            if (!battery.contains("powerWatts") && battery.contains("voltage") && battery.contains("currentMa"))
                battery.insert("powerWatts", std::abs(battery.value("voltage").toDouble()
                    * battery.value("currentMa").toDouble() / 1000));
            // Use nominal/design voltage for energy conversion, never the
            // fluctuating live voltage, which would distort battery health.
            const auto nominal = number("VOLTAGE_MIN_DESIGN", 1e6);
            if (nominal && *nominal > 0) {
                if (!battery.contains("energyFullWh") && battery.contains("chargeFullMah"))
                    battery.insert("energyFullWh", battery.value("chargeFullMah").toDouble() * *nominal / 1000);
                if (!battery.contains("energyDesignWh") && battery.contains("chargeDesignMah"))
                    battery.insert("energyDesignWh", battery.value("chargeDesignMah").toDouble() * *nominal / 1000);
            }
            batteries.append(battery);
        } else if (type == "Mains" || type.startsWith("USB")) {
            if (number("ONLINE").value_or(0) <= 0) continue;
            QJsonObject adapter{{QStringLiteral("name"), name}};
            put(adapter, "voltage", "VOLTAGE_NOW", 1e6);
            put(adapter, "currentMa", "CURRENT_NOW", 1e3, true);
            put(adapter, "powerWatts", "POWER_NOW", 1e6, true);
            put(adapter, "ratedPowerWatts", "POWER_MAX", 1e6);
            if (!adapter.contains("powerWatts") && adapter.contains("voltage") && adapter.contains("currentMa"))
                adapter.insert("powerWatts", std::abs(adapter.value("voltage").toDouble()
                    * adapter.value("currentMa").toDouble() / 1000));
            const auto voltageMax = number("VOLTAGE_MAX", 1e6), currentMax = number("CURRENT_MAX", 1e6);
            if (!adapter.contains("ratedPowerWatts") && voltageMax && currentMax && *voltageMax > 0 && *currentMax > 0)
                adapter.insert("ratedPowerWatts", *voltageMax * *currentMax);
            adapters.append(adapter);
        }
    }
    return {{QStringLiteral("available"), !batteries.isEmpty()},
        {QStringLiteral("batteries"), batteries}, {QStringLiteral("adapters"), adapters}};
}

} // namespace KosPlatform
