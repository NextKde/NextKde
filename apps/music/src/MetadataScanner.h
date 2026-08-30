#pragma once

#include "MusicTypes.h"

class MetadataScanner {
public:
    static QStringList supportedExtensions();
    static ScanResult scan(const QString &rootPath, const FingerprintMap &knownFiles,
                           const QString &artworkCachePath);
};
