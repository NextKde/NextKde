#include "settings.h"
#include "blurconfig.h"

#include <algorithm>

namespace KWin
{

QStringList parseWindowClasses(const QString &input)
{
    QStringList result;
    const auto blank = QStringLiteral("blank");
    for (const auto &line : input.split("\n", Qt::SkipEmptyParts)) {
        QString unescaped = "";
        bool consumed = false;
        for (qsizetype i = 0; i < line.size(); i++) {
            const auto character = line[i];
            if (character == QChar('$') && !consumed) {
                consumed = true;
                continue;
            }
            if (consumed) {
                const qsizetype skips = blank.size();
                if (line.mid(i, skips) == blank) {
                    consumed = false;
                    i += skips - 1;
                    continue;
                }
            }
            consumed = false;
            unescaped += character;
        }
        if (consumed) {
            unescaped += QChar('$');
        }
        result << unescaped;
    }
    return result;
}

void BlurSettings::read()
{
    BlurConfig::self()->read();

    general.blurStrength = BlurConfig::blurStrength() - 1;
    general.noiseStrength = BlurConfig::noiseStrength();
    // One global blur level is used by every glass surface. Keep the separate
    // pipeline fields only as an internal compatibility detail.
    general.decorationBlurStrength = general.blurStrength;
    general.decorationNoiseStrength = BlurConfig::decorationNoiseStrength();
    general.dockBlurStrength = general.blurStrength;
    general.dockNoiseStrength = BlurConfig::dockNoiseStrength();
    general.brightness = BlurConfig::brightness();
    general.saturation = BlurConfig::saturation();
    general.contrast = BlurConfig::contrast();
    general.oklabSaturation = BlurConfig::oklabSaturation();

    const float finetune = 0.5f + std::clamp(BlurConfig::blurFinetune(), 0, 10) * 0.13f;
    general.blurRadius = finetune;
    general.upsampleOffset = finetune;
    general.saturationCompensation = BlurConfig::blurSaturationCompensation();

    general.excludeDecorations = BlurConfig::excludeDecorations();
    general.shapeTrace = BlurConfig::shapeTrace();

    forceBlur.onlyQuickshell = BlurConfig::onlyQuickshell();
    forceBlur.windowClasses = parseWindowClasses(BlurConfig::windowClasses());
    forceBlur.windowClassMatchingMode = BlurConfig::blurMatching() ? WindowClassMatchingMode::Whitelist : WindowClassMatchingMode::Blacklist;
    forceBlur.blurDecorations = BlurConfig::blurDecorations();
    forceBlur.blurMenus = BlurConfig::blurMenus();
    forceBlur.blurDocks = BlurConfig::blurDocks();
    forceBlur.skipEmptyDockBlurRegions = BlurConfig::skipEmptyDockBlurRegions();

    roundedCorners.menuRadius = BlurConfig::menuCornerRadius();
    roundedCorners.dockRadius = BlurConfig::dockCornerRadius();
    roundedCorners.cornerExponent = std::clamp(
        static_cast<float>(BlurConfig::cornerExponent()), 2.0f, 8.0f);
    roundedCorners.useDeclaredCornerRadius = BlurConfig::useDeclaredCornerRadius();
    roundedCorners.ignoreContentBlurRegion = BlurConfig::ignoreContentBlurRegion();
    roundedCorners.dynamicCorners = BlurConfig::dynamicCorners();
    roundedCorners.dynamicCornersExcludeDocks = BlurConfig::dynamicCornersExcludeDocks();
    roundedCorners.dynamicCornersExcludeTooltips = BlurConfig::dynamicCornersExcludeTooltips();
    roundedCorners.dynamicCornersExcludeMenus = BlurConfig::dynamicCornersExcludeMenus();

    // The setting is already expressed in logical pixels. Multiplying it here
    // made a 28 px edge enter the shader as 280 px, where it was also reused
    // as the Snell lens displacement and could pull the backdrop across an
    // entire panel.
    refraction.edgeSizePixels = BlurConfig::refractionEdgeSize();
    refraction.refractionStrength = BlurConfig::refractionStrength() / 20.0;
    refraction.refractionNormalPow = BlurConfig::refractionNormalPow() / 2.0;
    refraction.refractionRGBFringing = BlurConfig::refractionRGBFringing() / 20.0;
    refraction.refractionOffsetStrength = BlurConfig::refractionOffsetStrength() / 2.0;
    refraction.materialSoftness = std::clamp(BlurConfig::materialSoftness(), 0.0, 1.0);
    refraction.materialReflectionStrength = std::clamp(BlurConfig::materialReflectionStrength(), 0.0, 1.0);
}

}
