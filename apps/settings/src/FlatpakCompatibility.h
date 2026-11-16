#pragma once

#include <QVariantMap>

namespace FlatpakCompatibility {
// Run only in the CLI's isolated child process, never in Settings itself.
int probeBundleCleanup();
QVariantMap checkBundleCleanup();
}
