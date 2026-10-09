#pragma once
#include <QRegularExpression>
#include <QVariantMap>

namespace listenfree::sourcehost {
// Read only the leading documentation block; never evaluate imported code in
// the UI process. Accept UTF-8 BOMs and the whitespace used by LX exporters.
inline QVariantMap scriptMetadata(const QByteArray &script) {
    const auto text = QString::fromUtf8(script).remove(QChar(0xfeff));
    const auto header = QRegularExpression(QStringLiteral(R"(^\s*/\*([\s\S]*?)\*/)"))
                            .match(text.left(65536));
    QVariantMap result;
    const QRegularExpression entry(QStringLiteral(R"(^\s*\*?\s*@(name|version|author|description|homepage)\s+(.+?)\s*$)"));
    for (const auto &line : header.captured(1).split('\n')) {
        const auto match = entry.match(line);
        if (match.hasMatch()) result[match.captured(1)] = match.captured(2).trimmed().left(1024);
    }
    return result;
}
}
