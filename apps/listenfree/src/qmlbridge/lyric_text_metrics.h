#pragma once
#include <QObject>
#include <QVariantList>
#include <QTextBoundaryFinder>
#include <QTextLayout>
#include <QFontMetricsF>
#include <algorithm>
#include <cmath>

namespace listenfree::qmlbridge {
// AMLL 9a1bd986 lyric-line emphasis, adapted to the existing timed tokens.
// Qt shapes the complete token once; animated slices retain kerning/ligatures.
class LyricTextMetrics : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QVariantList prepare(const QVariantList& words, const QFont& font) const {
        QVariantList result;
        const QFontMetricsF fontMetrics(font);
        for (const auto& value : words) {
            auto token = value.toMap();
            const QString original = token.value("text").toString();
            qsizetype firstInk = 0, afterInk = original.size();
            while (firstInk < afterInk && original[firstInk].isSpace()) ++firstInk;
            while (afterInk > firstInk && original[afterInk-1].isSpace()) --afterInk;
            const QString text = original.mid(firstInk, afterInk-firstInk);
            // As in AMLL's trimmed word spans, whitespace reserves layout
            // advance without consuming any of the audible word's sweep.
            const qreal leading = firstInk ? fontMetrics.horizontalAdvance(original.first(firstInk)) : 0;
            const qreal trailing = afterInk < original.size() ? fontMetrics.horizontalAdvance(original.mid(afterInk)) : 0;
            token.insert("displayText", text);
            token.insert("leadingSpace", leading);
            token.insert("trailingSpace", trailing);
            QTextLayout layout(text, font);
            layout.beginLayout();
            auto line = layout.createLine();
            if (line.isValid()) line.setLineWidth(1e6);
            layout.endLayout();
            const qreal width = line.isValid() ? line.horizontalAdvance() : 0;
            QVariantList glyphs;
            QTextBoundaryFinder finder(QTextBoundaryFinder::Grapheme, text);
            int from = 0, to = 0, ordinal = 0;
            while ((to = finder.toNextBoundary()) >= 0) {
                const qreal a = line.isValid() ? line.cursorToX(from) : 0;
                const qreal b = line.isValid() ? line.cursorToX(to) : 0;
                const QString part = text.mid(from, to - from);
                glyphs.append(QVariantMap{{"text", part}, {"left", std::min(a,b)},
                    {"right", std::max(a,b)}, {"ordinal", part.trimmed().isEmpty() ? -1 : ordinal++}});
                from = to;
            }
            token.insert("glyphs", glyphs);
            token.insert("advance", leading + width + trailing);
            token.insert("charCount", ordinal);
            token.insert("emphasized", false);
            result.append(token);
        }

        // Adjacent Latin syllables without whitespace share one emphasis
        // envelope. Preserve supplied CJK timings instead of inventing splits.
        int lastVisible = int(result.size())-1;
        while (lastVisible >= 0 && result[lastVisible].toMap().value("charCount").toInt() == 0) --lastVisible;
        int first = 0;
        while (first < result.size()) {
            int last = first;
            QString merged = result[first].toMap().value("text").toString();
            while (last + 1 < result.size() && mergeable(merged) && !merged.back().isSpace()) {
                const QString next = result[last+1].toMap().value("text").toString();
                if (!mergeable(next) || next.front().isSpace()) break;
                merged += next;
                ++last;
            }
            qreal start = result[first].toMap().value("startMs").toDouble();
            qreal end = start;
            int count = 0;
            bool emphasize = false;
            for (int i = first; i <= last; ++i) {
                const auto token = result[i].toMap();
                const qreal s = token.value("startMs").toDouble(), e = token.value("endMs").toDouble();
                start = std::min(start, s); end = std::max(end, e);
                count += token.value("charCount").toInt();
                emphasize |= shouldEmphasize(token.value("text").toString(), e-s);
            }
            emphasize |= !isCjk(merged.trimmed()) && shouldEmphasize(merged, end-start);
            // Equal text earlier in a line is not its final word. Empty trailing
            // timing tokens also must not take the last sung group's emphasis.
            const bool final = first <= lastVisible && lastVisible <= last;
            const qreal duration = std::max(1000., end-start);
            // The original iPad samples retain visible expansion for 1–2 s
            // notes. Cubing this ratio almost removes those eligible notes'
            // emphasis. Keep the existing >2 s curve and upper bound.
            const qreal strength = duration/2000;
            const qreal amount = std::min(1.2, .6 * (strength <= 1 ? strength : std::sqrt(strength))
                * (final ? 1.6 : 1));
            // Short sustained notes still have a soft halo in the reference.
            // Tie its minimum energy to the visible emphasis, not a second
            // cubic attenuation that nearly eliminates 1-2 s notes.
            const qreal glow = std::min(.8, std::max(.5 * amount,
                .5 * shape(duration/3000) * (final ? 1.5 : 1)));
            int offset = 0;
            for (int i = first; i <= last; ++i) {
                auto token = result[i].toMap();
                token.insert("emphasized", emphasize && count > 0);
                token.insert("emphasisStart", start);
                token.insert("emphasisDuration", duration * (final ? 1.2 : 1));
                token.insert("emphasisAmount", amount);
                token.insert("emphasisGlow", glow);
                token.insert("groupCount", count);
                token.insert("charOffset", offset);
                offset += token.value("charCount").toInt();
                result[i] = token;
            }
            first = last + 1;
        }
        return result;
    }
private:
    static qreal shape(qreal x) { return x <= 1 ? x*x*x : std::sqrt(x); }
    static bool isCjk(const QString& text) {
        if (text.isEmpty()) return false;
        for (const char32_t c : text.toUcs4()) {
            // Unified_Ideograph plus AMLL's U+0800..U+9FFC interval.
            if ((c >= 0x0800 && c <= 0x9ffc) || (c >= 0x9ffd && c <= 0x9fff)
                || (c >= 0x20000 && c <= 0x2a6df) || (c >= 0x2a700 && c <= 0x2b73f)
                || (c >= 0x2b740 && c <= 0x2b81f) || (c >= 0x2b820 && c <= 0x2ceaf)
                || (c >= 0x2ceb0 && c <= 0x2ebef) || (c >= 0x2ebf0 && c <= 0x2ee5f)
                || (c >= 0x30000 && c <= 0x3134f) || (c >= 0x31350 && c <= 0x323af)
                || c == 0xfa0e || c == 0xfa0f || c == 0xfa11 || c == 0xfa13 || c == 0xfa14
                || c == 0xfa1f || c == 0xfa21 || c == 0xfa23 || c == 0xfa24
                || c == 0xfa27 || c == 0xfa28 || c == 0xfa29) continue;
            return false;
        }
        return true;
    }
    static bool shouldEmphasize(const QString& text, qreal duration) {
        const auto trimmed = text.trimmed();
        return duration >= 1000 && (isCjk(trimmed) || (trimmed.size() > 1 && trimmed.size() <= 7));
    }
    static bool mergeable(const QString& text) {
        const auto trimmed = text.trimmed();
        if (trimmed.isEmpty() || isCjk(trimmed)) return false;
        for (const auto c : trimmed) if (c.isSpace()) return false;
        return true;
    }
};
}
