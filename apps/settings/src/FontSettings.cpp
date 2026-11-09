#include "FontSettings.h"

#include <KCoreConfigSkeleton>
#include <KConfig>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>
#include <QAbstractItemModel>
#include <QFontInfo>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickItem>
#include <memory>

namespace {
const QStringList categories{QStringLiteral("font"), QStringLiteral("fixed"),
    QStringLiteral("smallestReadableFont"), QStringLiteral("toolBarFont"),
    QStringLiteral("menuFont"), QStringLiteral("activeFont")};

QStringList options(QObject *module, const char *property)
{
    QStringList labels;
    if (!module) return labels;
    const auto model = qobject_cast<QAbstractItemModel *>(module->property(property).value<QObject *>());
    if (model) {
        for (int row = 0; row < model->rowCount(); ++row)
            labels.append(model->data(model->index(row, 0), Qt::DisplayRole).toString());
    }
    return labels;
}

bool editable(QObject *object, const QString &name)
{
    const auto skeleton = qobject_cast<KCoreConfigSkeleton *>(object);
    return skeleton && skeleton->findItem(name) && !skeleton->isImmutable(name);
}
}

FontSettings::FontSettings(QQmlEngine *engine, QObject *parent)
    : QObject(parent), m_engine(engine)
{
}

bool FontSettings::needsSave() const { return m_module && m_module->needsSave(); }
QObject *FontSettings::module() const { return m_module; }
QObject *FontSettings::fonts() const
{
    return m_module ? m_module->property("fontsSettings").value<QObject *>() : nullptr;
}
QObject *FontSettings::rendering() const
{
    return m_module ? m_module->property("fontsAASettings").value<QObject *>() : nullptr;
}
QStringList FontSettings::subPixelOptions() const { return options(m_module, "subPixelOptionsModel"); }
QStringList FontSettings::hintingOptions() const { return options(m_module, "hintingOptionsModel"); }

void FontSettings::refresh()
{
    // Retain edits when navigating away and back. Reset is the explicit discard.
    if (needsSave()) return;
    m_error.clear();
    if (!m_module) {
        const auto metadata = KPluginMetaData::findPluginById(
            QStringLiteral("plasma/kcms/systemsettings"), QStringLiteral("kcm_fonts"));
        if (!metadata.isValid()) {
            m_error = QStringLiteral("The KDE font settings module is not installed.");
            emit changed();
            return;
        }
        // The host owns this engine and outlives this adapter.
        const auto result = KQuickConfigModuleLoader::loadModule(metadata, this, {},
            std::shared_ptr<QQmlEngine>(m_engine, [](QQmlEngine *) {}));
        if (!result) {
            m_error = QStringLiteral("Could not load KDE font settings: %1").arg(result.errorString);
            emit changed();
            return;
        }
        m_module = result.plugin;
        if (!fonts() || !rendering()
            || m_module->metaObject()->indexOfProperty("subPixelCurrentIndex") < 0
            || m_module->metaObject()->indexOfProperty("hintingCurrentIndex") < 0) {
            delete m_module;
            m_module = nullptr;
            m_error = QStringLiteral("This KDE font settings module is not supported.");
            emit changed();
            return;
        }
        connect(m_module, &KQuickConfigModule::needsSaveChanged, this, &FontSettings::changed);
        // KFonts::load() uses engine() for its preview provider. KCMUtils only
        // initializes that engine wrapper in mainUi(), even with an explicitly
        // supplied engine. Keep KDE's host item detached and hidden; the user
        // interacts exclusively with FontSettingsPage, never a KDE window.
        auto host = m_module->mainUi();
        if (!host) {
            m_error = QStringLiteral("Could not initialize KDE font settings: %1").arg(m_module->errorString());
            delete m_module;
            m_module = nullptr;
            emit changed();
            return;
        }
        host->setVisible(false);
    }
    m_module->load();
    emit changed();
}

void FontSettings::reset()
{
    m_error.clear();
    if (m_module) m_module->load();
    emit changed();
}

void FontSettings::defaults()
{
    m_error.clear();
    if (m_module) m_module->defaults();
    emit changed();
}

bool FontSettings::apply()
{
    if (!m_module) return false;
    m_error.clear();
    // KDE saves every font role and renderer setting, then exports GTK/Xft and
    // sends refreshFonts. Writing kdeglobals alone misses those side effects.
    m_module->save();
    for (QObject *object : {fonts(), rendering()}) {
        const auto skeleton = qobject_cast<KCoreConfigSkeleton *>(object);
        if (skeleton && skeleton->config()->isDirty())
            m_error = QStringLiteral("Could not save all font settings. Check that your configuration is writable.");
    }
    // As in KDE's KCModuleQml host, save() does not clear the module's dirty
    // flag itself. needsSave is UI state, not a save failure return value.
    if (m_error.isEmpty()) m_module->setNeedsSave(false);
    emit changed();
    return m_error.isEmpty();
}

bool FontSettings::fontEditable(const QString &category) const
{
    return categories.contains(category) && editable(fonts(), category);
}

bool FontSettings::renderingEditable(const QString &setting) const
{
    if (!rendering() || rendering()->property("isAaImmutable").toBool()) return false;
    if (setting == QLatin1String("dpi") && QGuiApplication::platformName() != QLatin1String("xcb"))
        return false;
    return editable(rendering(), setting == QLatin1String("dpi") ? QStringLiteral("forceFontDPI") : setting);
}

void FontSettings::setFont(const QString &category, QFont font)
{
    if (!fontEditable(category) || font.family().isEmpty()) return;
    font.setPointSizeF(qMax(4.0, font.pointSizeF()));
    fonts()->setProperty(category.toUtf8().constData(), font);
}

void FontSettings::adjustAllFonts(const QFont &font, bool family, bool style, bool size)
{
    for (const auto &category : categories) {
        if (!fontEditable(category)) continue;
        QFont adjusted = fonts()->property(category.toUtf8().constData()).value<QFont>();
        // A family chosen for proportional text must not replace a fixed face.
        const bool fixed = category == QLatin1String("fixed");
        if (family && (!fixed || QFontInfo(font).fixedPitch())) adjusted.setFamilies(font.families());
        if (style) {
            adjusted.setWeight(font.weight());
            adjusted.setStyle(font.style());
            adjusted.setStyleName(font.styleName());
        }
        if (size) {
            const double points = qMax(4.0, font.pointSizeF());
            adjusted.setPointSizeF(category == QLatin1String("smallestReadableFont") && points >= 9
                ? points - 2 : points);
        }
        setFont(category, adjusted);
    }
}

void FontSettings::setRendering(const QString &setting, const QVariant &value)
{
    static const QStringList settings{QStringLiteral("antiAliasing"), QStringLiteral("exclude"),
        QStringLiteral("excludeFrom"), QStringLiteral("excludeTo"), QStringLiteral("dpi")};
    if (!settings.contains(setting) || !renderingEditable(setting)) return;
    if (setting == QLatin1String("dpi") && (value.toInt() < 0 || value.toInt() > 999)) return;
    if ((setting == QLatin1String("excludeFrom") || setting == QLatin1String("excludeTo"))
        && (value.toInt() < 0 || value.toInt() > 999)) return;
    rendering()->setProperty(setting.toUtf8().constData(), value);
}

void FontSettings::setSubPixel(int index)
{
    if (renderingEditable(QStringLiteral("subPixel")) && index >= 0 && index < subPixelOptions().size())
        m_module->setProperty("subPixelCurrentIndex", index);
}

void FontSettings::setHinting(int index)
{
    if (renderingEditable(QStringLiteral("hinting")) && index >= 0 && index < hintingOptions().size())
        m_module->setProperty("hintingCurrentIndex", index);
}
