#pragma once
#include <QDir>
#include <QFileInfo>
#include <QStringList>
#include <QUrl>

namespace listenfree {
// Resolve relative paths in the launching process, before forwarding to the
// resident instance. Desktop-file %U values arrive as file: URLs.
inline QStringList mediaFilesFromArguments(const QStringList& arguments) {
    QStringList files;
    bool positionalOnly = false;
    for (qsizetype i = 0; i < arguments.size(); ++i) {
        const auto& argument = arguments[i];
        if (!positionalOnly && argument == "--") { positionalOnly = true; continue; }
        if (!positionalOnly && (argument == "--data-dir" || argument == "--capture" || argument == "--view")) {
            ++i; continue;
        }
        if (!positionalOnly && argument.startsWith('-')) continue;
        const QUrl url(argument);
        if (!url.scheme().isEmpty() && !url.isLocalFile()) continue;
        const QFileInfo info(url.isLocalFile() ? url.toLocalFile() : argument);
        if (!info.isFile() || !info.isReadable()) continue;
        const auto path = info.canonicalFilePath();
        if (!files.contains(path)) files.append(path);
        if (files.size() == 64) break;
    }
    return files;
}
}
