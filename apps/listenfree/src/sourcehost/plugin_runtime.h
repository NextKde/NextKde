#pragma once

#include "sourcehost/source_protocol.h"

#include <QObject>

#include <memory>

namespace listenfree::sourcehost {

// Deep module for executing one legacy ListenFree JavaScript source inside the
// already isolated SourceHost process. Callers only exchange SourceMessage;
// QJSEngine, event adaptation, validation and lifecycle stay private here.
class PluginRuntime final : public QObject {
    Q_OBJECT
public:
    explicit PluginRuntime(QObject* parent = nullptr);
    ~PluginRuntime() override;

    void handle(const SourceMessage& request);

signals:
    void responseReady(const SourceMessage& response);

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace listenfree::sourcehost
