#pragma once

#include <QJsonObject>

namespace KosPlatform::WidgetPackageIndex {

// Discovery only: inspect package metadata without instantiating either QML entry.
QJsonObject snapshot();

}
