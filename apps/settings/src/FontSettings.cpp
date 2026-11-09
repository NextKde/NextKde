#include "FontSettings.h"

#include <KCoreConfigSkeleton>
#include <KConfig>
#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>
#include <QAbstractItemModel>
#include <QFontInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QMetaProperty>
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

bool writableProperties(QObject *object, const QStringList &names, QMetaType type = {})
{
    if (!object) return false;
    for (const auto &name : names) {
        const int index = object->metaObject()->indexOfProperty(name.toUtf8().constData());
        if (index < 0) return false;
        const auto property = object->metaObject()->property(index);
        if (!property.isReadable() || !property.isWritable()) return false;
        if (type.isValid() && property.metaType() != type) return false;
    }
    return true;
}
}

FontSettings::FontSettings(QQmlEngine *engine, QObject *parent)
    : QObject(parent), m_engine(engine)
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(350);
    connect(&m_saveTimer, &QTimer::timeout, this, [this] { if (needsSave()) apply(); });
}

FontSettings::~FontSettings()
{
    // The adapter outlives page loaders. A real application exit must not lose
    // the last edit just because the debounce interval has not elapsed yet.
    if (m_saveTimer.isActive()) apply();
}

void FontSettings::scheduleSave()
{
    m_error.clear();
    m_saveTimer.start();
    emit changed();
}

bool FontSettings::needsSave() const { return m_module && m_module->needsSave(); }
bool FontSettings::previewAvailable() const { return !qEnvironmentVariableIsEmpty("DISPLAY"); }
bool FontSettings::dpiAvailable() const
{
    const auto skeleton = qobject_cast<KCoreConfigSkeleton *>(rendering());
    return skeleton && skeleton->findItem(QStringLiteral("forceFontDPI"))
        && writableProperties(rendering(), {QStringLiteral("dpi")}, QMetaType::fromType<int>());
}
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

QStringList FontSettings::fontFamilies(bool monospacedOnly) const
{
    QStringList families;
    for (const auto &family : QFontDatabase::families()) {
        if (!QFontDatabase::isPrivateFamily(family)
            && (!monospacedOnly || QFontDatabase::isFixedPitch(family)))
            families.append(family);
    }
    return families;
}

QStringList FontSettings::fontStyles(const QString &family) const
{
    return QFontDatabase::styles(family);
}

QString FontSettings::fontStyleName(const QFont &font) const
{
    return QFontDatabase::styleString(font);
}

QFont FontSettings::selectionFont(const QFont &original, const QString &family,
    const QString &style, double pointSize) const
{
    QFont font = QFontDatabase::font(family, style, qRound(qBound(4.0, pointSize, 512.0)));
    font.setPointSizeF(qBound(4.0, pointSize, 512.0));
    font.setUnderline(original.underline());
    font.setStrikeOut(original.strikeOut());
    return font;
}

void FontSettings::refresh()
{
    // Activation/navigation must not reload over an edit awaiting its save.
    if (m_saveTimer.isActive() || needsSave()) return;
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
        // These are the font KCM's properties, not a universal KDE settings
        // API. Check the complete form contract before exposing the backend.
        // Never fall back to guessing config keys on an incompatible version.
        if (!qobject_cast<KCoreConfigSkeleton *>(fonts())
            || !qobject_cast<KCoreConfigSkeleton *>(rendering())
            || !writableProperties(fonts(), categories, QMetaType::fromType<QFont>())
            || !writableProperties(rendering(), {QStringLiteral("antiAliasing"), QStringLiteral("exclude")},
                QMetaType::fromType<bool>())
            || !writableProperties(rendering(), {QStringLiteral("excludeFrom"), QStringLiteral("excludeTo")},
                QMetaType::fromType<int>())
            || !writableProperties(rendering(), {QStringLiteral("subPixel"), QStringLiteral("hinting")})
            || rendering()->metaObject()->indexOfProperty("isAaImmutable") < 0
            || !writableProperties(m_module, {QStringLiteral("subPixelCurrentIndex"), QStringLiteral("hintingCurrentIndex")},
                QMetaType::fromType<int>())
            || subPixelOptions().isEmpty() || hintingOptions().isEmpty()) {
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
    m_saveTimer.stop();
    m_error.clear();
    if (m_module) m_module->load();
    emit changed();
}

void FontSettings::defaults()
{
    m_error.clear();
    if (m_module) m_module->defaults();
    if (needsSave()) scheduleSave();
    emit changed();
}

bool FontSettings::apply()
{
    m_saveTimer.stop();
    if (!m_module) return false;
    m_error.clear();
    // KDE saves every font role and renderer setting, then exports GTK/Xft and
    // sends refreshFonts. Writing kdeglobals alone misses those side effects.
    m_module->save();
    for (QObject *object : {fonts(), rendering()}) {
        const auto skeleton = qobject_cast<KCoreConfigSkeleton *>(object);
        // FontsAASettings adds Xft keys to the shared kdeglobals after the font
        // skeleton saved. Flush those pending writes; dirty alone is not an
        // error, and the long-lived Settings process must not defer them to exit.
        if (skeleton && !skeleton->config()->sync())
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
    if (setting == QLatin1String("dpi") && (!dpiAvailable() || QGuiApplication::platformName() != QLatin1String("xcb")))
        return false;
    return editable(rendering(), setting == QLatin1String("dpi") ? QStringLiteral("forceFontDPI") : setting);
}

void FontSettings::setFont(const QString &category, QFont font)
{
    if (!fontEditable(category) || font.family().isEmpty()) return;
    font.setPointSizeF(qMax(4.0, font.pointSizeF()));
    const auto key = category.toUtf8();
    if (fonts()->property(key.constData()).value<QFont>() == font) return;
    fonts()->setProperty(key.constData(), font);
    scheduleSave();
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
    const auto key = setting.toUtf8();
    if (rendering()->property(key.constData()) == value) return;
    rendering()->setProperty(key.constData(), value);
    scheduleSave();
}

void FontSettings::setSubPixel(int index)
{
    if (renderingEditable(QStringLiteral("subPixel")) && index >= 0 && index < subPixelOptions().size()
        && m_module->property("subPixelCurrentIndex").toInt() != index) {
        m_module->setProperty("subPixelCurrentIndex", index);
        scheduleSave();
    }
}

void FontSettings::setHinting(int index)
{
    if (renderingEditable(QStringLiteral("hinting")) && index >= 0 && index < hintingOptions().size()
        && m_module->property("hintingCurrentIndex").toInt() != index) {
        m_module->setProperty("hintingCurrentIndex", index);
        scheduleSave();
    }
}
