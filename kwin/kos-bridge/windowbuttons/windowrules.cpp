#include "windowrules.h"

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QRegularExpression>
#include <QSaveFile>
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
// of rules for every window that is looked at; the oldest are the ones the user
// has least recently cared about.
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
    // Through the same clamp the gesture goes through, because this file is
    // editable text and a typo in it must not produce an absurd panel.
    return clamped(geometry);
}

// The parts of a matcher that are set, in a fixed order, as one string. Used as
// the identity of a rule: two rules with the same key are the same rule, and
// saving one replaces the other.
QString fieldKey(const QString &field, const QString &value)
{
    return field + QLatin1Char('=') + value;
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
    QStringList parts;
    if (!className.isEmpty()) {
        parts << fieldKey(QStringLiteral("class"), className);
    }
    if (!title.isEmpty()) {
        parts << fieldKey(QStringLiteral("title"), title);
    }
    if (!titleRegex.isEmpty()) {
        parts << fieldKey(QStringLiteral("titleRegex"), titleRegex);
    }
    if (!role.isEmpty()) {
        parts << fieldKey(QStringLiteral("role"), role);
    }
    if (hasType) {
        parts << fieldKey(QStringLiteral("type"), QString::number(type));
    }
    return parts.join(QLatin1Char('|'));
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
        m_rules.append(GeometryRule{matcher,
                                    geometryFromJson(entry["geometry"].toObject())});
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

bool WindowRuleStore::found(const WindowQuery &query, PanelGeometry *out) const
{
    for (const GeometryRule &rule : m_rules) {
        if (rule.matcher.matches(query)) {
            if (out) {
                *out = rule.geometry;
            }
            return true;
        }
    }
    return false;
}

bool WindowRuleStore::store(const WindowMatcher &matcher,
                            const PanelGeometry &geometry)
{
    if (matcher.isEmpty()) {
        qWarning() << "KOS: refusing to store a rule that matches every window";
        return false;
    }

    const QString key = matcher.canonicalKey();
    for (int i = 0; i < m_rules.size(); ++i) {
        if (m_rules.at(i).matcher.canonicalKey() == key) {
            m_rules.removeAt(i);
            break;
        }
    }
    // In front: the adjustment that was just made is the one that should win a
    // tie with an older rule of the same specificity.
    m_rules.prepend(GeometryRule{matcher, clamped(geometry)});
    while (m_rules.size() > MaxRules) {
        m_rules.removeLast();
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
