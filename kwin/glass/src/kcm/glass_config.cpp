/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "glass_config.h"

#include "kwineffects_interface.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QCheckBox>
#include <QDBusConnection>
#include <QFormLayout>
#include <QGroupBox>
#include <QLabel>
#include <QScrollArea>
#include <QSpinBox>
#include <QVBoxLayout>
#include <QWidget>

namespace KWin
{

namespace
{


// Widget ranges mirror the shader-side scaling in glass.cpp: strengths are
// stored as 0..20 or 0..100 integers and normalised when the effect reads
// them, so the KCM shows the same numbers the previous configuration used.
QSpinBox *makeSpin(QWidget *parent, int min, int max, const QString &suffix)
{
    auto *spin = new QSpinBox(parent);
    spin->setRange(min, max);
    if (!suffix.isEmpty()) {
        spin->setSuffix(suffix);
    }
    return spin;
}

} // namespace

GlassEffectConfig::GlassEffectConfig(QObject *parent, const KPluginMetaData &data)
    : KCModule(parent, data)
{
    auto *scroll = new QScrollArea(widget());
    scroll->setWidgetResizable(true);
    auto *content = new QWidget(scroll);
    auto *layout = new QVBoxLayout(content);
    scroll->setWidget(content);
    auto *outer = new QVBoxLayout(widget());
    outer->addWidget(scroll);

    auto addRow = [](QFormLayout *form, const QString &label, QWidget *field,
                     const QString &help) {
        form->addRow(label, field);
        if (!help.isEmpty()) {
            auto *hint = new QLabel(help, field->parentWidget());
            hint->setWordWrap(true);
            hint->setEnabled(false);
            form->addRow(QString(), hint);
        }
    };

    // ---- Blur -----------------------------------------------------------
    auto *blurBox = new QGroupBox(i18n("Blur"), content);
    auto *blurForm = new QFormLayout(blurBox);
    m_blurStrength = makeSpin(blurBox, 1, 15, QString());
    addRow(blurForm, i18n("Strength"), m_blurStrength,
           i18n("Selects how many downsample levels the blur chain runs. "
                "Higher values blur further without ghosted copies."));
    m_blurFinetune = makeSpin(blurBox, 0, 10, QString());
    addRow(blurForm, i18n("Finetune"), m_blurFinetune,
           i18n("Scales every level's tap distance."));
    m_saturationCompensation = new QCheckBox(i18n("Compensate saturation"), blurBox);
    addRow(blurForm, QString(), m_saturationCompensation,
           i18n("Restores colour that repeated averaging would otherwise wash out."));
    layout->addWidget(blurBox);

    // ---- Liquid material ------------------------------------------------
    auto *liquidBox = new QGroupBox(i18n("Liquid material"), content);
    auto *liquidForm = new QFormLayout(liquidBox);
    m_refractionStrength = makeSpin(liquidBox, 0, 20, QString());
    addRow(liquidForm, i18n("Refraction"), m_refractionStrength, QString());
    m_refractionEdgeSize = makeSpin(liquidBox, 1, 100, i18n(" px"));
    addRow(liquidForm, i18n("Edge size"), m_refractionEdgeSize,
           i18n("Width of the raised lens band along the contour."));
    m_refractionNormalPow = makeSpin(liquidBox, 0, 8, QString());
    addRow(liquidForm, i18n("Edge falloff"), m_refractionNormalPow, QString());
    m_refractionRGBFringing = makeSpin(liquidBox, 0, 20, QString());
    addRow(liquidForm, i18n("RGB fringing"), m_refractionRGBFringing, QString());
    m_refractionOffsetStrength = makeSpin(liquidBox, 0, 12, QString());
    addRow(liquidForm, i18n("Body bend"), m_refractionOffsetStrength,
           i18n("How far the body of the glass displaces the backdrop."));
    m_materialSoftness = makeSpin(liquidBox, 0, 100, i18n("%"));
    addRow(liquidForm, i18n("Softness"), m_materialSoftness,
           i18n("Broad inward scatter instead of a hard contour. "
                "Used by the soft glass profile."));
    m_materialReflection = makeSpin(liquidBox, 0, 100, i18n("%"));
    addRow(liquidForm, i18n("Reflection"), m_materialReflection, QString());
    layout->addWidget(liquidBox);

    // ---- Pointer --------------------------------------------------------
    auto *pointerBox = new QGroupBox(i18n("Pointer"), content);
    auto *pointerForm = new QFormLayout(pointerBox);
    m_hoverLight = new QCheckBox(i18n("Cursor light"), pointerBox);
    addRow(pointerForm, QString(), m_hoverLight,
           i18n("Specular lobe and edge transmission near the pointer. "
                "Liquid profiles only."));
    m_hoverLightStrength = makeSpin(pointerBox, 0, 20, QString());
    addRow(pointerForm, i18n("Light strength"), m_hoverLightStrength, QString());
    m_hoverLightRadius = makeSpin(pointerBox, 0, 400, i18n(" px"));
    addRow(pointerForm, i18n("Light reach"), m_hoverLightRadius,
           i18n("How far the light spreads from the pointer. "
                "0 keeps the automatic size that follows the surface."));
    m_pointerParallax = new QCheckBox(i18n("Lens parallax"), pointerBox);
    addRow(pointerForm, QString(), m_pointerParallax,
           i18n("Biases the lens edge a few pixels toward the pointer."));
    layout->addWidget(pointerBox);

    // ---- Click ----------------------------------------------------------
    auto *clickBox = new QGroupBox(i18n("Click"), content);
    auto *clickForm = new QFormLayout(clickBox);
    m_clickLight = new QCheckBox(i18n("Click ripple"), clickBox);
    addRow(clickForm, QString(), m_clickLight,
           i18n("A light ring that spreads from the press point. "
                "Liquid profiles only."));
    m_clickLightStrength = makeSpin(clickBox, 0, 20, QString());
    addRow(clickForm, i18n("Strength"), m_clickLightStrength, QString());
    m_clickLightRadius = makeSpin(clickBox, 20, 600, i18n(" px"));
    addRow(clickForm, i18n("Reach"), m_clickLightRadius, QString());
    m_clickLightDuration = makeSpin(clickBox, 100, 2000, i18n(" ms"));
    addRow(clickForm, i18n("Duration"), m_clickLightDuration, QString());
    layout->addWidget(clickBox);

    layout->addStretch(1);

    for (QSpinBox *spin : {m_blurStrength, m_blurFinetune, m_refractionStrength,
                           m_refractionEdgeSize, m_refractionNormalPow,
                           m_refractionRGBFringing, m_refractionOffsetStrength,
                           m_materialSoftness, m_materialReflection,
                           m_hoverLightStrength, m_hoverLightRadius,
                           m_clickLightStrength, m_clickLightRadius,
                           m_clickLightDuration}) {
        connect(spin, &QSpinBox::valueChanged, this,
                [this](int) { markAsChanged(); });
    }
    for (QCheckBox *check : {m_saturationCompensation, m_hoverLight,
                             m_pointerParallax, m_clickLight}) {
        connect(check, &QCheckBox::toggled, this,
                [this](bool) { markAsChanged(); });
    }
}

GlassEffectConfig::~GlassEffectConfig() = default;

void GlassEffectConfig::load()
{
    const KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwinrc")),
                             QStringLiteral("Effect-blurplus"));
    m_blurStrength->setValue(group.readEntry("BlurStrength", 15));
    m_blurFinetune->setValue(group.readEntry("BlurFinetune", 3));
    m_saturationCompensation->setChecked(
        group.readEntry("BlurSaturationCompensation", true));

    m_refractionStrength->setValue(group.readEntry("RefractionStrength", 0));
    m_refractionEdgeSize->setValue(group.readEntry("RefractionEdgeSize", 20));
    m_refractionNormalPow->setValue(group.readEntry("RefractionNormalPow", 2));
    m_refractionRGBFringing->setValue(group.readEntry("RefractionRGBFringing", 1));
    m_refractionOffsetStrength->setValue(
        group.readEntry("RefractionOffsetStrength", 0));
    m_materialSoftness->setValue(
        static_cast<int>(group.readEntry("MaterialSoftness", 0.0) * 100.0));
    m_materialReflection->setValue(
        static_cast<int>(group.readEntry("MaterialReflectionStrength", 0.0) * 100.0));

    m_hoverLight->setChecked(group.readEntry("HoverLight", true));
    m_hoverLightStrength->setValue(group.readEntry("HoverLightStrength", 10));
    m_hoverLightRadius->setValue(group.readEntry("HoverLightRadius", 0));
    m_pointerParallax->setChecked(group.readEntry("PointerParallax", true));

    m_clickLight->setChecked(group.readEntry("ClickLight", true));
    m_clickLightStrength->setValue(group.readEntry("ClickLightStrength", 10));
    m_clickLightRadius->setValue(group.readEntry("ClickLightRadius", 200));
    m_clickLightDuration->setValue(group.readEntry("ClickLightDuration", 450));

    KCModule::load();
}

void GlassEffectConfig::save()
{
    KSharedConfigPtr config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    KConfigGroup group(config, QStringLiteral("Effect-blurplus"));
    group.writeEntry("BlurStrength", m_blurStrength->value());
    group.writeEntry("BlurFinetune", m_blurFinetune->value());
    group.writeEntry("BlurSaturationCompensation",
                     m_saturationCompensation->isChecked());

    group.writeEntry("RefractionStrength", m_refractionStrength->value());
    group.writeEntry("RefractionEdgeSize", m_refractionEdgeSize->value());
    group.writeEntry("RefractionNormalPow", m_refractionNormalPow->value());
    group.writeEntry("RefractionRGBFringing", m_refractionRGBFringing->value());
    group.writeEntry("RefractionOffsetStrength",
                     m_refractionOffsetStrength->value());
    group.writeEntry("MaterialSoftness",
                     static_cast<double>(m_materialSoftness->value()) / 100.0);
    group.writeEntry("MaterialReflectionStrength",
                     static_cast<double>(m_materialReflection->value()) / 100.0);

    group.writeEntry("HoverLight", m_hoverLight->isChecked());
    group.writeEntry("HoverLightStrength", m_hoverLightStrength->value());
    group.writeEntry("HoverLightRadius", m_hoverLightRadius->value());
    group.writeEntry("PointerParallax", m_pointerParallax->isChecked());

    group.writeEntry("ClickLight", m_clickLight->isChecked());
    group.writeEntry("ClickLightStrength", m_clickLightStrength->value());
    group.writeEntry("ClickLightRadius", m_clickLightRadius->value());
    group.writeEntry("ClickLightDuration", m_clickLightDuration->value());
    group.sync();

    KCModule::save();

    OrgKdeKwinEffectsInterface interface(QStringLiteral("org.kde.KWin"),
                                         QStringLiteral("/Effects"),
                                         QDBusConnection::sessionBus());
    interface.reconfigureEffect(QStringLiteral("glass"));
}

void GlassEffectConfig::defaults()
{
    m_blurStrength->setValue(15);
    m_blurFinetune->setValue(3);
    m_saturationCompensation->setChecked(true);
    m_refractionStrength->setValue(0);
    m_refractionEdgeSize->setValue(20);
    m_refractionNormalPow->setValue(2);
    m_refractionRGBFringing->setValue(1);
    m_refractionOffsetStrength->setValue(0);
    m_materialSoftness->setValue(0);
    m_materialReflection->setValue(0);
    m_hoverLight->setChecked(true);
    m_hoverLightStrength->setValue(10);
    m_hoverLightRadius->setValue(0);
    m_pointerParallax->setChecked(true);
    m_clickLight->setChecked(true);
    m_clickLightStrength->setValue(10);
    m_clickLightRadius->setValue(200);
    m_clickLightDuration->setValue(450);
    KCModule::defaults();
}

K_PLUGIN_CLASS(GlassEffectConfig)

} // namespace KWin

#include "glass_config.moc"
