#include "PlatformServer.h"
#include "KimpanelBridge.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QLocalSocket>

namespace KosPlatform {

void PlatformServer::initKimpanelBridge()
{
    if (m_kimpanelBridge)
        return;

    m_kimpanelBridge = new KimpanelBridge(this);

    connect(m_kimpanelBridge, &KimpanelBridge::stateChanged, this,
            [this](const QJsonObject &state) {
        QJsonObject event{
            {QStringLiteral("event"), QStringLiteral("inputmethod.state")},
            {QStringLiteral("payload"), state}
        };
        for (auto *socket : std::as_const(m_inputMethodSubscribers)) {
            sendEvent(socket, event);
        }
    });

    connect(m_kimpanelBridge, &KimpanelBridge::menuRequested, this,
            [this](const QJsonObject &menu) {
        QJsonObject event{
            {QStringLiteral("event"), QStringLiteral("inputmethod.menu")},
            {QStringLiteral("payload"), menu}
        };
        for (auto *socket : std::as_const(m_inputMethodSubscribers)) {
            sendEvent(socket, event);
        }
    });

    m_kimpanelBridge->syncTakeoverState();
}

bool PlatformServer::handleInputMethodOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (!op.startsWith(QStringLiteral("inputmethod.")))
        return false;

    if (!m_kimpanelBridge)
        initKimpanelBridge();

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();

    if (op == QStringLiteral("inputmethod.subscribe")) {
        m_inputMethodSubscribers.insert(socket);
        m_kimpanelBridge->setShellConnected(true);
        respond(socket, request, true, QJsonObject{{QStringLiteral("subscribed"), true}});
        // Immediately reply with current state snapshot so client doesn't wait
        QJsonObject event{
            {QStringLiteral("event"), QStringLiteral("inputmethod.state")},
            {QStringLiteral("payload"), m_kimpanelBridge->currentState()}
        };
        sendEvent(socket, event);
        return true;
    }

    if (op == QStringLiteral("inputmethod.state")) {
        respond(socket, request, true, m_kimpanelBridge->currentState());
        return true;
    }

    if (op == QStringLiteral("inputmethod.set-enabled")) {
        const bool enabled = payload.value(QStringLiteral("enabled")).toBool(false);
        const QPointer<QLocalSocket> peer(socket);
        const bool ok = m_kimpanelBridge->setUserEnabled(enabled);
        if (!peer || !m_buffers.contains(peer.data()))
            return true;
        respond(socket, request, ok, QJsonObject{
            {QStringLiteral("enabled"), m_kimpanelBridge->isUserEnabled()},
            {QStringLiteral("active"), m_kimpanelBridge->isTakeoverActive()}
        });
        return true;
    }

    if (op == QStringLiteral("inputmethod.select-candidate")) {
        const int index = payload.value(QStringLiteral("index")).toInt(0);
        m_kimpanelBridge->selectCandidate(index);
        respond(socket, request, true, {});
        return true;
    }

    if (op == QStringLiteral("inputmethod.page-up")) {
        m_kimpanelBridge->pageUp();
        respond(socket, request, true, {});
        return true;
    }

    if (op == QStringLiteral("inputmethod.page-down")) {
        m_kimpanelBridge->pageDown();
        respond(socket, request, true, {});
        return true;
    }

    if (op == QStringLiteral("inputmethod.trigger-property")) {
        const QString property = payload.value(QStringLiteral("property")).toString();
        if (property.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("missing-property"),
                    QStringLiteral("缺少 property 参数"), false);
            return true;
        }
        m_kimpanelBridge->triggerProperty(property);
        respond(socket, request, true, {});
        return true;
    }

    if (op == QStringLiteral("inputmethod.configure")) {
        m_kimpanelBridge->configure();
        respond(socket, request, true, {});
        return true;
    }

    if (op == QStringLiteral("inputmethod.reload-config")) {
        m_kimpanelBridge->reloadConfig();
        respond(socket, request, true, {});
        return true;
    }

    return false;
}

} // namespace KosPlatform
