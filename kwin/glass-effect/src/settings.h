#pragma once

#include <QStringList>

namespace KWin
{

QStringList parseWindowClasses(const QString &input);

enum class WindowClassMatchingMode
{
    Blacklist,
    Whitelist
};


struct GeneralSettings
{
    int blurStrength;
    int noiseStrength;
    int decorationBlurStrength;
    int decorationNoiseStrength;
    int dockBlurStrength;
    int dockNoiseStrength;
    float brightness;
    float saturation;
    float contrast;
    bool oklabSaturation;
    float blurRadius;
    float upsampleOffset;
    bool saturationCompensation;
    bool excludeDecorations;
    bool shapeTrace;
};

struct ForceBlurSettings
{
    // Quickshell surfaces often contain several independently rounded blur
    // regions.  Restricting the effect to them avoids changing the rendering
    // or corner geometry of normal application windows.
    bool onlyQuickshell;
    QStringList windowClasses;
    WindowClassMatchingMode windowClassMatchingMode;
    bool blurDecorations;
    bool blurMenus;
    bool blurDocks;
    // Layer-shell clients such as Quickshell may create a background-effect
    // object without declaring a region. Treating that empty region as the
    // entire dock makes transparent panels receive the glass shader.
    bool skipEmptyDockBlurRegions;
};

struct RoundedCornersSettings
{
    float menuRadius;
    float dockRadius;
    float cornerExponent;
    bool useDeclaredCornerRadius;
    bool ignoreContentBlurRegion;
    bool dynamicCorners;
    bool dynamicCornersExcludeDocks;
    bool dynamicCornersExcludeTooltips;
    bool dynamicCornersExcludeMenus;
};

struct RefractionSettings
{
    float edgeSizePixels;
    float refractionStrength;
    float refractionNormalPow;
    float refractionRGBFringing;
    float refractionOffsetStrength;
    float materialSoftness;
    float materialReflectionStrength;
};

class BlurSettings
{
public:
    GeneralSettings general{};
    ForceBlurSettings forceBlur{};
    RoundedCornersSettings roundedCorners{};
    RefractionSettings refraction{};

    void read();
};

}
