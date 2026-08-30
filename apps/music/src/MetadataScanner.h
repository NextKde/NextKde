#pragma once

#include "MusicTypes.h"

#include <optional>

class MetadataScanner {
public:
    static QStringList supportedExtensions();
    static std::optional<TrackRecord> scanFile(const QString &path,
                                               const QString &artworkCachePath,
                                               QString *warning = nullptr);
    static ScanResult scan(const QString &rootPath, const FingerprintMap &knownFiles,
                           const QString &artworkCachePath);
};
