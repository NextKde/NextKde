#pragma once

#include <QObject>
#include <QDBusConnection>
#include <optional>

namespace KosPlatform {

// A separate bus connection makes the inhibitor belong to one Shell socket,
// rather than to the lifetime of the shared platform daemon.
class KeepAwakeLease final : public QObject {
    Q_OBJECT
public:
    explicit KeepAwakeLease(QObject *parent = nullptr);
    ~KeepAwakeLease() override;
    void start();
    bool enabled() const { return m_enabled; }
    static bool available();

signals:
    void finished(bool ok, const QString &message);
    void invalidated();

private:
    void inhibit(bool screenSaver);
    QString m_connectionName;
    QDBusConnection m_bus;
    std::optional<uint> m_powerCookie;
    std::optional<uint> m_screenCookie;
    bool m_enabled = false;
    bool m_valid = true;
};

} // namespace KosPlatform
