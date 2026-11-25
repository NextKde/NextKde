#include "windowrules.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QLockFile>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>

#include <algorithm>

namespace KOS
{

namespace
{

// Where the plugin's own file lives. A machine-written file belongs beside the
// rest of the session's data rather than in ~/.config, which holds what the user
// wrote.
constexpr auto RulesFileName = "/kos/window-buttons-rules.json";

// Refuse to read a file this size: it is not one of ours, and parsing it on the
// compositor's thread is not worth doing.
constexpr qint64 MaxFileSize = 1024 * 1024;
// Bound the file. A list that only ever grows is eventually a parse of thousands
// of rules for every window that is looked at. Keep the most specific rules,
// with the newest adjustment first among equally specific rules.
constexpr int MaxRules = 200;

// KWin's window types, by the name a rule may use for them. The numbers are
// KWin::WindowType from `kwin/effect/globals.h`.
struct TypeName {
    const char *name;
    int value;
};
const TypeName TypeNames[] = {
    {"normal", 0},        {"desktop", 1},          {"dock", 2},
    {"toolbar", 3},       {"menu", 4},             {"dialog", 5},
    {"utility", 8},       {"splash", 9},           {"dropdownmenu", 10},
    {"popupmenu", 11},    {"tooltip", 12},         {"notification", 13},
    {"combobox", 14},     {"dndicon", 15},         {"onscreendisplay", 16},
    {"criticalnotification", 17},                  {"appletpopup", 18},
};

bool typeFromName(const QString &name, int *type)
{
    for (const TypeName &entry : TypeNames) {
        if (name == QLatin1String(entry.name)) {
            *type = entry.value;
            return true;
        }
    }
    return false;
}

QJsonObject geometryToJson(const PanelGeometry &geometry)
{
    QJsonObject offset;
    offset["x"] = geometry.offset.x;
    offset["y"] = geometry.offset.y;

    QJsonObject out;
    out["position"] =
        geometry.position == ButtonPosition::Left ? "left" : "right";
    out["offset"] = offset;
    out["buttonSize"] = geometry.buttonSize;
    out["buttonSpacing"] = geometry.buttonSpacing;
    out["panelPadding"] = geometry.panelPadding;
    out["panelPaddingX"] = geometry.panelPaddingX;
    out["coverage"] = QJsonObject{{"left", geometry.coverage.left()}, {"top", geometry.coverage.top()},
        {"right", geometry.coverage.right()}, {"bottom", geometry.coverage.bottom()}};
    return out;
}

PanelGeometry geometryFromJson(const QJsonObject &object)
{
    PanelGeometry geometry;
    if (object.contains("position")) {
        // "right" is the layout every desktop these applications follow uses, so
        // anything else falls back to it.
        geometry.position =
            object["position"].toString() == QLatin1String("left")
            ? ButtonPosition::Left
            : ButtonPosition::Right;
    }
    if (object.contains("offset")) {
        const QJsonObject offset = object["offset"].toObject();
        if (offset.contains("x")) {
            geometry.offset.x = offset["x"].toDouble();
        }
        if (offset.contains("y")) {
            geometry.offset.y = offset["y"].toDouble();
        }
    }
    if (object.contains("buttonSize")) {
        geometry.buttonSize = object["buttonSize"].toDouble();
    }
    if (object.contains("buttonSpacing")) {
        geometry.buttonSpacing = object["buttonSpacing"].toDouble();
    }
    if (object.contains("panelPadding")) {
        geometry.panelPadding = object["panelPadding"].toDouble();
    }
    if (object.contains("panelPaddingX")) {
        geometry.panelPaddingX = object["panelPaddingX"].toDouble();
    }
    const auto coverage = object.value("coverage").toObject();
    geometry.coverage = QMarginsF(coverage.value("left").toDouble(), coverage.value("top").toDouble(),
        coverage.value("right").toDouble(), coverage.value("bottom").toDouble());
    // Through the same clamp the gesture goes through, because this file is
    // editable text and a typo in it must not produce an absurd panel.
    return clamped(geometry);
}

const QStringList &titleDelimiters()
{
    static const QStringList delimiters = {
        QStringLiteral(" - "),
        QStringLiteral(" \u2014 "),
        QStringLiteral(" \u2013 "),
        QStringLiteral(" | "),
        QStringLiteral(" \u00B7 "),
    };
    return delimiters;
}

QStringList classTokens(const QString &windowClass)
{
    static const QSet<QString> noise = {
        QStringLiteral("org"),     QStringLiteral("com"),    QStringLiteral("net"),
        QStringLiteral("app"),     QStringLiteral("io"),     QStringLiteral("md"),
        QStringLiteral("kde"),     QStringLiteral("gnome"),  QStringLiteral("github"),
        QStringLiteral("desktop"),
    };
    QStringList tokens;
    QString current;
    for (const QChar ch : windowClass) {
        if (ch.isLetterOrNumber()) {
            current.append(ch.toLower());
        } else if (!current.isEmpty()) {
            if (current.size() >= 3 && !noise.contains(current)
                && !tokens.contains(current)) {
                tokens.append(current);
            }
            current.clear();
        }
    }
    if (current.size() >= 3 && !noise.contains(current)
        && !tokens.contains(current)) {
        tokens.append(current);
    }
    return tokens;
}

bool isPureDigitsOrPunct(const QString &text)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        return true;
    }
    for (const QChar ch : trimmed) {
        if (ch.isLetter()) {
            return false;
        }
    }
    return true;
}

QString makePrefixRegex(const QString &head, const QString &delimiter)
{
    return QStringLiteral("^") + QRegularExpression::escape(head)
        + QStringLiteral("(?:") + QRegularExpression::escape(delimiter)
        + QStringLiteral("|$)");
}

bool matchesNoSibling(const QRegularExpression &re, const QStringList &siblingCaptions)
{
    if (!re.isValid()) {
        return false;
    }
    for (const QString &sibling : siblingCaptions) {
        if (re.match(sibling).hasMatch()) {
            return false;
        }
    }
    return true;
}

} // namespace

bool WindowMatcher::matches(const WindowQuery &query) const
{
    // A matcher with nothing in it is not a rule that applies to everything: it
    // is a mistake, and matching nothing is the safe reading of it.
    if (isEmpty()) {
        return false;
    }

    if (!className.isEmpty() && query.windowClass != className) {
        const QStringList tokens =
            query.windowClass.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (!tokens.contains(className)) {
            return false;
        }
    }

    if (!title.isEmpty() && query.caption != title) {
        return false;
    }

    if (!titleRegex.isEmpty()) {
        if (compiledTitleRegex.pattern() != titleRegex) {
            compiledTitleRegex = QRegularExpression(titleRegex);
        }
        if (!compiledTitleRegex.isValid()
            || !compiledTitleRegex.match(query.caption).hasMatch()) {
            return false;
        }
    }

    // Against an empty role (every Wayland window) this can only match a rule
    // that set no role at all, which is checked above.
    if (!role.isEmpty() && query.role != role) {
        return false;
    }

    if (hasType && query.type != type) {
        return false;
    }

    return true;
}

bool WindowMatcher::isEmpty() const
{
    return className.isEmpty() && title.isEmpty() && titleRegex.isEmpty()
        && role.isEmpty() && !hasType;
}

int WindowMatcher::specificity() const
{
    int count = 0;
    count += className.isEmpty() ? 0 : 1;
    count += title.isEmpty() ? 0 : 1;
    count += titleRegex.isEmpty() ? 0 : 1;
    count += role.isEmpty() ? 0 : 1;
    count += hasType ? 1 : 0;
    return count;
}

QString WindowMatcher::canonicalKey() const
{
    // Encode each field separately: captions and regexes may contain the
    // separators a hand-joined key would otherwise treat as extra fields.
    const QJsonArray fields{className, title, titleRegex, role, hasType,
                            hasType ? type : 0};
    return QString::fromUtf8(QJsonDocument(fields).toJson(QJsonDocument::Compact));
}

QJsonObject WindowMatcher::toJson() const
{
    QJsonObject out;
    if (!className.isEmpty()) {
        out["class"] = className;
    }
    if (!title.isEmpty()) {
        out["title"] = title;
    }
    if (!titleRegex.isEmpty()) {
        out["titleRegex"] = titleRegex;
    }
    if (!role.isEmpty()) {
        out["role"] = role;
    }
    if (hasType) {
        for (const TypeName &entry : TypeNames) {
            if (entry.value == type) {
                out["type"] = QString::fromLatin1(entry.name);
                break;
            }
        }
    }
    return out;
}

WindowMatcher WindowMatcher::fromJson(const QJsonObject &object, bool *ok)
{
    WindowMatcher matcher;
    *ok = true;

    matcher.className = object["class"].toString();
    matcher.title = object["title"].toString();
    matcher.role = object["role"].toString();

    // Reject invalid expressions while the rule can still be identified, and
    // retain the compiled form for repeated matches during painting.
    const QString regex = object["titleRegex"].toString();
    if (!regex.isEmpty()) {
        const QRegularExpression expression(regex);
        if (!expression.isValid()) {
            qWarning() << "KOS: ignoring a rule whose titleRegex is not valid:"
                       << regex << expression.errorString();
            *ok = false;
            return matcher;
        }
        matcher.titleRegex = regex;
        matcher.compiledTitleRegex = expression;
    }

    const QString type = object["type"].toString();
    if (!type.isEmpty()) {
        int value = 0;
        if (!typeFromName(type, &value)) {
            qWarning() << "KOS: ignoring a rule naming an unknown window type:"
                       << type;
            *ok = false;
            return matcher;
        }
        matcher.hasType = true;
        matcher.type = value;
    }

    return matcher;
}

WindowMatcher adjustmentMatcher(const WindowQuery &query)
{
    WindowMatcher matcher;
    matcher.className = query.windowClass;
    matcher.hasType = true;
    matcher.type = query.type;
    matcher.role = query.role;
    if (query.role.isEmpty()) matcher.title = query.caption;
    return matcher;
}

WindowMatcher appMatcher(const WindowQuery &query)
{
    WindowMatcher matcher;
    matcher.className = query.windowClass;
    matcher.hasType = true;
    matcher.type = query.type;
    return matcher;
}

MatchScope matcherScope(const WindowMatcher &matcher)
{
    return (matcher.title.isEmpty() && matcher.titleRegex.isEmpty()
            && matcher.role.isEmpty())
        ? MatchScope::App
        : MatchScope::Window;
}

CaptionTransition classifyCaptionTransition(const QString &windowClass,
                                            const QString &previous,
                                            const QString &current,
                                            QString *commonPrefix,
                                            QString *commonDelimiter)
{
    if (commonPrefix) {
        commonPrefix->clear();
    }
    if (commonDelimiter) {
        commonDelimiter->clear();
    }
    if (previous == current) {
        return CaptionTransition::Unchanged;
    }
    const QString prevTrimmed = previous.trimmed();
    const QString curTrimmed = current.trimmed();
    if (prevTrimmed.isEmpty() || curTrimmed.isEmpty()) {
        return CaptionTransition::StartupPlaceholder;
    }

    const QStringList &delimiters = titleDelimiters();
    bool prevHasDelimiter = false;
    for (const QString &sep : delimiters) {
        if (previous.contains(sep)) {
            prevHasDelimiter = true;
            break;
        }
    }
    if (!prevHasDelimiter) {
        const QStringList tokens = classTokens(windowClass);
        const QString prevLower = prevTrimmed.toLower();
        if (tokens.contains(prevLower)) {
            return CaptionTransition::StartupPlaceholder;
        }
        for (const QString &sep : delimiters) {
            const qsizetype idx = current.lastIndexOf(sep);
            if (idx < 0) {
                continue;
            }
            const QString tail = current.mid(idx + sep.size()).trimmed();
            if (tail.compare(prevTrimmed, Qt::CaseInsensitive) == 0
                || (prevTrimmed.size() >= 3
                    && tail.contains(prevTrimmed, Qt::CaseInsensitive))) {
                return CaptionTransition::StartupPlaceholder;
            }
        }
    }

    for (const QString &sep : delimiters) {
        if (!previous.contains(sep) || !current.contains(sep)) {
            continue;
        }
        const QStringList partsPrev = previous.split(sep, Qt::KeepEmptyParts);
        const QStringList partsCur = current.split(sep, Qt::KeepEmptyParts);
        const qsizetype maxCommon = std::min(partsPrev.size(), partsCur.size()) - 1;
        if (maxCommon < 1) {
            continue;
        }

        qsizetype commonLead = 0;
        while (commonLead < maxCommon
               && !partsPrev[commonLead].trimmed().isEmpty()
               && partsPrev[commonLead].trimmed() == partsCur[commonLead].trimmed()) {
            ++commonLead;
        }

        qsizetype commonTail = 0;
        while (commonTail < maxCommon) {
            const QString a = partsPrev[partsPrev.size() - 1 - commonTail].trimmed();
            const QString b = partsCur[partsCur.size() - 1 - commonTail].trimmed();
            if (a.isEmpty() || a != b) {
                break;
            }
            ++commonTail;
        }

        if (commonLead >= 1 && partsPrev.first().trimmed() == partsCur.first().trimmed()) {
            const QString prefix = partsPrev.mid(0, commonLead).join(sep).trimmed();
            if (!isPureDigitsOrPunct(prefix)) {
                if (commonPrefix) {
                    *commonPrefix = prefix;
                }
                if (commonDelimiter) {
                    *commonDelimiter = sep;
                }
                return CaptionTransition::SamePrefix;
            }
        }
        if (commonTail >= 1) {
            return CaptionTransition::SameSuffix;
        }
    }

    return CaptionTransition::Replaced;
}

WindowMatcher windowScopedMatcher(const WindowQuery &query,
                                  const QStringList &siblingCaptions)
{
    if (!query.role.isEmpty()) {
        return adjustmentMatcher(query);
    }
    if (query.caption.isEmpty()) {
        return appMatcher(query);
    }

    const QStringList &delimiters = titleDelimiters();

    // Strategy 1: strip the longest delimited tail shared with an open sibling.
    for (const QString &sep : delimiters) {
        if (!query.caption.contains(sep)) {
            continue;
        }
        const QStringList parts = query.caption.split(sep, Qt::KeepEmptyParts);
        if (parts.size() < 2) {
            continue;
        }
        qsizetype bestTail = 0;
        for (const QString &sibling : siblingCaptions) {
            if (!sibling.contains(sep)) {
                continue;
            }
            const QStringList sibParts = sibling.split(sep, Qt::KeepEmptyParts);
            if (sibParts.size() < 2) {
                continue;
            }
            const qsizetype maxTail = std::min(parts.size(), sibParts.size()) - 1;
            qsizetype tail = 0;
            while (tail < maxTail) {
                const QString a = parts[parts.size() - 1 - tail].trimmed();
                const QString b = sibParts[sibParts.size() - 1 - tail].trimmed();
                if (a.isEmpty() || a != b) {
                    break;
                }
                ++tail;
            }
            if (tail > bestTail) {
                bestTail = tail;
            }
        }
        if (bestTail >= 1) {
            const QString head = parts.mid(0, parts.size() - bestTail).join(sep).trimmed();
            if (!isPureDigitsOrPunct(head)) {
                const QString pattern = makePrefixRegex(head, sep);
                const QRegularExpression re(pattern);
                if (re.isValid() && re.match(query.caption).hasMatch()
                    && matchesNoSibling(re, siblingCaptions)) {
                    WindowMatcher matcher = appMatcher(query);
                    matcher.titleRegex = pattern;
                    matcher.compiledTitleRegex = re;
                    return matcher;
                }
            }
        }
    }

    // Strategy 2: when the trailing segment names the app from windowClass,
    // generalize to the leading window-kind segment.
    const QStringList tokens = classTokens(query.windowClass);
    if (!tokens.isEmpty()) {
        for (const QString &sep : delimiters) {
            if (!query.caption.contains(sep)) {
                continue;
            }
            const QStringList parts = query.caption.split(sep, Qt::KeepEmptyParts);
            if (parts.size() < 2) {
                continue;
            }
            const QString lastLower = parts.last().trimmed().toLower();
            const bool lastIsApp = std::any_of(
                tokens.cbegin(), tokens.cend(),
                [&](const QString &tok) { return lastLower.contains(tok); });
            if (!lastIsApp) {
                continue;
            }
            const QString head = parts.first().trimmed();
            if (!isPureDigitsOrPunct(head) && !tokens.contains(head.toLower())) {
                const QString pattern = makePrefixRegex(head, sep);
                const QRegularExpression re(pattern);
                if (re.isValid() && re.match(query.caption).hasMatch()
                    && matchesNoSibling(re, siblingCaptions)) {
                    WindowMatcher matcher = appMatcher(query);
                    matcher.titleRegex = pattern;
                    matcher.compiledTitleRegex = re;
                    return matcher;
                }
            }
        }
    }

    return adjustmentMatcher(query);
}

MatchScope initialAdjustScope(const WindowQuery &query,
                              const std::optional<WindowMatcher> &existingMatcher,
                              const WindowScopeContext &context)
{
    if (!query.role.isEmpty()) {
        return MatchScope::Window;
    }
    if (existingMatcher && !existingMatcher->isEmpty()
        && matcherScope(*existingMatcher) == MatchScope::Window) {
        return MatchScope::Window;
    }
    const bool isSecondarySibling = !query.caption.isEmpty()
        && !context.dynamicCaption
        && context.hasUnscopedSibling
        && (context.hasOlderSibling || context.hasDynamicSibling);
    if (isSecondarySibling) {
        return MatchScope::Window;
    }
    return MatchScope::App;
}

WindowMatcher resolvedAdjustMatcher(const WindowQuery &query, MatchScope scope,
                                    const std::optional<WindowMatcher> &existingMatcher,
                                    const QStringList &siblingCaptions)
{
    const bool hasExisting = existingMatcher && !existingMatcher->isEmpty();
    if (scope == MatchScope::App) {
        if (hasExisting && matcherScope(*existingMatcher) == MatchScope::App) {
            return *existingMatcher;
        }
        return appMatcher(query);
    }
    if (hasExisting && matcherScope(*existingMatcher) == MatchScope::Window
        && (!existingMatcher->role.isEmpty() || !existingMatcher->titleRegex.isEmpty())) {
        return *existingMatcher;
    }
    return windowScopedMatcher(query, siblingCaptions);
}

CaptionAdaptation adaptRuleForCaptionChange(
    const WindowQuery &previousQuery,
    const WindowQuery &currentQuery,
    const GeometryRule &previousRule,
    const std::optional<GeometryRule> &currentMatchedRule,
    const WindowScopeContext &context)
{
    CaptionAdaptation result;
    if (previousRule.matcher.isEmpty()
        || matcherScope(previousRule.matcher) != MatchScope::Window
        || !previousRule.matcher.role.isEmpty()) {
        return result;
    }
    if (previousRule.matcher.matches(currentQuery)) {
        return result;
    }
    if (currentMatchedRule
        && matcherScope(currentMatchedRule->matcher) == MatchScope::Window) {
        return result;
    }

    QString commonPrefix;
    QString commonDelim;
    const CaptionTransition transition = classifyCaptionTransition(
        currentQuery.windowClass, previousQuery.caption, currentQuery.caption,
        &commonPrefix, &commonDelim);
    if (transition == CaptionTransition::Unchanged
        || transition == CaptionTransition::StartupPlaceholder) {
        return result;
    }

    if (transition == CaptionTransition::SamePrefix
        && previousRule.matcher.matches(previousQuery)) {
        const QString pattern = makePrefixRegex(commonPrefix, commonDelim);
        const QRegularExpression re(pattern);
        const bool matchesOrigin = previousRule.matcher.title.isEmpty()
            || re.match(previousRule.matcher.title).hasMatch();
        if (re.isValid() && matchesOrigin
            && re.match(previousQuery.caption).hasMatch()
            && re.match(currentQuery.caption).hasMatch()
            && matchesNoSibling(re, context.siblingCaptions)) {
            WindowMatcher upgraded = appMatcher(currentQuery);
            upgraded.titleRegex = pattern;
            upgraded.compiledTitleRegex = re;
            result.kind = CaptionAdaptation::Kind::UpgradeToPrefixRegex;
            result.targetMatcher = upgraded;
            return result;
        }
    }

    const bool hasExistingAppRule = currentMatchedRule
        && matcherScope(currentMatchedRule->matcher) == MatchScope::App;
    if (!context.hasUnscopedSibling
        && (!hasExistingAppRule || !context.hasOlderSibling)) {
        result.kind = CaptionAdaptation::Kind::PromoteToApp;
        result.targetMatcher = appMatcher(currentQuery);
        return result;
    }

    result.kind = CaptionAdaptation::Kind::PinInSession;
    result.targetMatcher = previousRule.matcher;
    return result;
}

QString overlayModeToString(OverlayMode mode)
{
    switch (mode) {
    case OverlayMode::Transparent:
        return QStringLiteral("transparent");
    case OverlayMode::Hidden:
        return QStringLiteral("hidden");
    case OverlayMode::Cover:
    default:
        return QStringLiteral("cover");
    }
}

OverlayMode overlayModeFromString(const QString &value)
{
    if (value == QLatin1String("transparent")) {
        return OverlayMode::Transparent;
    }
    if (value == QLatin1String("hidden")) {
        return OverlayMode::Hidden;
    }
    return OverlayMode::Cover;
}

bool moreSpecific(const WindowMatcher &a, const WindowMatcher &b)
{
    return a.specificity() > b.specificity();
}

WindowRuleStore::WindowRuleStore()
{
    m_path = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QLatin1String(RulesFileName);
    load();
}

void WindowRuleStore::load()
{
    m_rules.clear();
    m_lastWritten.clear();

    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    if (file.size() > MaxFileSize) {
        qWarning() << "KOS: ignoring the window button rules file, it is larger"
                   << "than" << MaxFileSize << "bytes:" << m_path;
        return;
    }

    const QByteArray bytes = file.readAll();
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    if (!document.isObject()) {
        qWarning() << "KOS: the window button rules file is not a JSON object:"
                   << m_path;
        return;
    }

    const QJsonArray rules = document.object()["rules"].toArray();
    for (const QJsonValue &value : rules) {
        const QJsonObject entry = value.toObject();
        bool ok = false;
        const WindowMatcher matcher =
            WindowMatcher::fromJson(entry["match"].toObject(), &ok);
        if (!ok || matcher.isEmpty()) {
            if (ok) {
                qWarning() << "KOS: ignoring a rule that matches nothing, a rule"
                           << "has to name at least one of class, title,"
                           << "titleRegex, role or type:" << m_path;
            }
            continue;
        }
        m_rules.append(GeometryRule{
            matcher,
            geometryFromJson(entry["geometry"].toObject()),
            overlayModeFromString(entry["overlayMode"].toString())});
    }

    // The rules were written most recently first, and the order within the same
    // specificity is what decides between two rules that both match.
    std::stable_sort(m_rules.begin(), m_rules.end(),
                     [](const GeometryRule &a, const GeometryRule &b) {
                         return moreSpecific(a.matcher, b.matcher);
                     });

    if (m_rules.size() > MaxRules) {
        qWarning() << "KOS: the window button rules file holds" << m_rules.size()
                   << "rules, keeping the" << MaxRules << "most specific";
        m_rules.resize(MaxRules);
    }

    // What the file says now, so that storing an identical geometry later does
    // not rewrite it.
    m_lastWritten = bytes;
}

bool WindowRuleStore::foundRule(const WindowQuery &query, GeometryRule *out) const
{
    for (const GeometryRule &rule : m_rules) {
        if (rule.matcher.matches(query)) {
            if (out) {
                *out = rule;
            }
            return true;
        }
    }
    return false;
}

bool WindowRuleStore::found(const WindowQuery &query, PanelGeometry *out) const
{
    GeometryRule rule;
    if (!foundRule(query, &rule)) {
        return false;
    }
    if (out) {
        *out = rule.geometry;
    }
    return true;
}

bool WindowRuleStore::store(const WindowMatcher &matcher,
                            const PanelGeometry &geometry,
                            OverlayMode overlayMode)
{
    return replace(WindowMatcher{}, matcher, geometry, overlayMode);
}

bool WindowRuleStore::replace(const WindowMatcher &previous,
                              const WindowMatcher &matcher,
                              const PanelGeometry &geometry,
                              OverlayMode overlayMode)
{
    if (matcher.isEmpty()) {
        qWarning() << "KOS: refusing to store a rule that matches every window";
        return false;
    }

    const QString key = matcher.canonicalKey();
    const QString prevKey = previous.isEmpty() ? QString() : previous.canonicalKey();
    // Narrowing an app-scoped rule to one caption refines it rather than
    // replacing it: sibling windows keep the class rule while the caption rule
    // -- more specific, sorted first -- wins for this window alone. That is
    // what keeps an image viewer's own cover from taking the main window's
    // rule away. Every other direction replaces, so promoting a caption rule
    // to class+type still leaves nothing stale behind.
    const bool refineOnly = !prevKey.isEmpty() && previous.title.isEmpty()
        && previous.titleRegex.isEmpty() && previous.role.isEmpty()
        && (!matcher.title.isEmpty() || !matcher.titleRegex.isEmpty()
            || !matcher.role.isEmpty());
    for (int i = m_rules.size() - 1; i >= 0; --i) {
        const QString entryKey = m_rules.at(i).matcher.canonicalKey();
        if (entryKey == key
            || (!refineOnly && !prevKey.isEmpty() && entryKey == prevKey)) {
            m_rules.removeAt(i);
        }
    }
    // In front: the adjustment that was just made is the one that should win a
    // tie with an older rule of the same specificity.
    m_rules.prepend(GeometryRule{matcher, clamped(geometry), overlayMode});
    // Keep the same precedence before and after a reload: prepending a broad
    // adjustment must not hide an existing more specific rule.
    std::stable_sort(m_rules.begin(), m_rules.end(),
                     [](const GeometryRule &a, const GeometryRule &b) {
                         return moreSpecific(a.matcher, b.matcher);
                     });
    while (m_rules.size() > MaxRules) {
        m_rules.removeLast();
    }

    return write();
}

bool WindowRuleStore::remove(const WindowMatcher &matcher)
{
    if (matcher.isEmpty()) {
        return false;
    }
    const QString key = matcher.canonicalKey();
    bool removed = false;
    for (int i = m_rules.size() - 1; i >= 0; --i) {
        if (m_rules.at(i).matcher.canonicalKey() == key) {
            m_rules.removeAt(i);
            removed = true;
        }
    }
    if (!removed) {
        return true;
    }
    return write();
}

bool WindowRuleStore::write()
{
    QJsonArray rules;
    for (const GeometryRule &rule : std::as_const(m_rules)) {
        QJsonObject entry;
        entry["match"] = rule.matcher.toJson();
        entry["geometry"] = geometryToJson(rule.geometry);
        if (rule.overlayMode != OverlayMode::Cover) {
            entry["overlayMode"] = overlayModeToString(rule.overlayMode);
        }
        rules.append(entry);
    }

    QJsonObject root;
    root["version"] = 1;
    root["rules"] = rules;

    // Indented, and QJsonObject keeps its keys sorted, so the same rules always
    // produce the same bytes and the comparison below means something.
    const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Indented);
    if (bytes == m_lastWritten) {
        return true;
    }

    const QFileInfo info(m_path);
    if (!QDir().mkpath(info.absolutePath())) {
        qWarning() << "KOS: could not create" << info.absolutePath();
        return false;
    }

    QLockFile lock(m_path + QStringLiteral(".lock"));
    if (!lock.tryLock(100)) {
        qWarning() << "KOS: rules file is locked by another writer:" << m_path;
        return false;
    }

    // Written through a temporary file: the compositor can be killed at any
    // point, and a half-written rules file would be read back as a syntax error
    // and silently drop every adjustment in it.
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "KOS: could not write" << m_path << file.errorString();
        return false;
    }
    if (file.write(bytes) != bytes.size() || !file.commit()) {
        qWarning() << "KOS: could not write" << m_path << file.errorString();
        return false;
    }

    m_lastWritten = bytes;
    return true;
}

} // namespace KOS
