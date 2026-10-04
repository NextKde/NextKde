#pragma once

#include <QJsonObject>
#include <QRegularExpression>
#include <QString>
#include <QVector>

#include "panelgeometry.h"

namespace KOS
{

// What a rule is matched against: the four things a window says about itself
// that are stable enough to key a saved adjustment on.
//
// `type` is the number of the KWin window type rather than the enum, so that
// this unit -- which the unit test links without a compositor -- needs no KWin
// headers. The names are mapped in windowrules.cpp.
struct WindowQuery {
    QString windowClass;
    QString caption;
    // Empty on Wayland, where KWin has no window role to report: the matcher is
    // kept for X11 and for the shape of the schema, and a rule that sets one
    // simply never matches here.
    QString role;
    int type = 0;
};

// One rule's matchers. An unset field constrains nothing.
struct WindowMatcher {
    // Matches the whole window class, or any whitespace-separated token of it
    // (WM_CLASS arrives as "instance class", and a key of "code" has always
    // matched "code code").
    QString className;
    QString title;
    QString titleRegex;
    QString role;
    bool hasType = false;
    int type = 0;
    // Rules are matched during painting. Keep the compiled expression across
    // frames; pattern comparison also handles matchers built by callers that
    // assign titleRegex directly.
    mutable QRegularExpression compiledTitleRegex;

    bool matches(const WindowQuery &) const;
    // A matcher that constrains nothing would match every window, which is never
    // what a rule means. These are dropped at load with a warning.
    bool isEmpty() const;
    // How many fields are set. A rule with more of them is a more specific
    // statement about a window, and wins over one with fewer.
    int specificity() const;
    // The matcher's own identity, for replacing a rule rather than appending a
    // second one for the same window.
    QString canonicalKey() const;
    QJsonObject toJson() const;
    // `ok` is false when the object names a window type that does not exist. The
    // rule is then dropped whole: ignoring the field would quietly widen the
    // rule to match windows it was never meant for.
    static WindowMatcher fromJson(const QJsonObject &, bool *ok);
};

// More matcher fields first. The sort is stable, so rules with the same number
// of fields keep the order they were written in -- which for the machine-written
// file is newest first.
bool moreSpecific(const WindowMatcher &, const WindowMatcher &);

struct GeometryRule {
    WindowMatcher matcher;
    PanelGeometry geometry;
};

// The machine-written rules file.
//
// This is the only thing in the plugin that writes anywhere, and it writes only
// its own file: the user's window-buttons.json is hand-written and is never
// opened for writing.
class WindowRuleStore
{
public:
    WindowRuleStore();

    void load();
    // First matching rule wins, in the order they were loaded in.
    bool found(const WindowQuery &, PanelGeometry *out) const;
    // Replaces the rule with the same matcher, or adds it. False when the file
    // could not be written.
    bool store(const WindowMatcher &, const PanelGeometry &);

    QString path() const { return m_path; }
    int count() const { return m_rules.size(); }

private:
    bool write();

    QString m_path;
    QVector<GeometryRule> m_rules;
    // What the file last said, so a store that changes nothing -- the same drag
    // saved twice -- does not rewrite it.
    QByteArray m_lastWritten;
};

} // namespace KOS
