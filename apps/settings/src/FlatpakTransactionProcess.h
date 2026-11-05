#pragma once

#include <QVariantMap>
#include <functional>

namespace FlatpakTransactionProcess {
using Cancelled = std::function<bool()>;
using Progress = std::function<void(const QString&, int)>;

QVariantMap run(const QVariantMap& request, const Cancelled& cancelled, const Progress& progress);
int helperMain();
}
