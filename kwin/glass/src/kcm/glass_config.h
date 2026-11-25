/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KCModule>

class QCheckBox;
class QSpinBox;

namespace KWin
{

// Settings page for the Glass effect. It writes the same `Effect-blurplus`
// group in kwinrc that the shell's theme sync and the effect itself read, so a
// change here takes effect on the next reconfigure without a restart.
//
// Only the keys the rewritten effect actually consumes are exposed. The
// previous implementation's noise, decoration, dock, corner and static-blur
// controls were dropped with the features they configured.
class GlassEffectConfig : public KCModule
{
    Q_OBJECT

public:
    explicit GlassEffectConfig(QObject *parent, const KPluginMetaData &data);
    ~GlassEffectConfig() override;

    void load() override;
    void save() override;
    void defaults() override;

private:
    QSpinBox *m_blurStrength = nullptr;
    QSpinBox *m_blurFinetune = nullptr;
    QCheckBox *m_saturationCompensation = nullptr;

    QSpinBox *m_refractionStrength = nullptr;
    QSpinBox *m_refractionEdgeSize = nullptr;
    QSpinBox *m_refractionNormalPow = nullptr;
    QSpinBox *m_refractionRGBFringing = nullptr;
    QSpinBox *m_refractionOffsetStrength = nullptr;
    QSpinBox *m_materialSoftness = nullptr;
    QSpinBox *m_materialReflection = nullptr;

    QCheckBox *m_hoverLight = nullptr;
    QSpinBox *m_hoverLightStrength = nullptr;
    QSpinBox *m_hoverLightRadius = nullptr;
    QCheckBox *m_pointerParallax = nullptr;

    QCheckBox *m_clickLight = nullptr;
    QSpinBox *m_clickLightStrength = nullptr;
    QSpinBox *m_clickLightRadius = nullptr;
    QSpinBox *m_clickLightDuration = nullptr;
};

} // namespace KWin
