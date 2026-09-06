import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: root

    width: 1180
    height: 760
    minimumWidth: 760
    minimumHeight: 520
    // The clear colour must be transparent in glass mode. Drawing the same
    // material both here and in background would compound alpha to ~0.99 and
    // make compositor blur visually ineffective.
    color: AppTheme.glassActive ? "transparent" : AppTheme.window
    property var applicationSettings: null
    readonly property bool compact: width < 940 * AppTheme.densityScale
    readonly property int adaptivePageMargin: compact
        ? Math.round(16 * AppTheme.densityScale)
        : Math.round(AppTheme.pageMargin * AppTheme.densityScale)

    palette.window: AppTheme.window
    palette.windowText: AppTheme.text
    palette.text: AppTheme.text
    palette.buttonText: AppTheme.text
    palette.button: AppTheme.button
    palette.base: AppTheme.windowRaised
    palette.highlight: AppTheme.accent
    palette.highlightedText: AppTheme.accentText

    Binding {
        target: AppTheme
        property: "appearanceMode"
        value: root.applicationSettings
            ? root.applicationSettings.appearanceMode : "system"
    }
    Binding {
        target: AppTheme
        property: "materialMode"
        value: root.applicationSettings
            ? root.applicationSettings.materialMode : "auto"
    }
    Binding {
        target: AppTheme
        property: "materialOpacity"
        value: root.applicationSettings
            ? root.applicationSettings.materialOpacity : 0.86
    }
    Binding {
        target: AppTheme
        property: "accentName"
        value: root.applicationSettings
            ? root.applicationSettings.accentName : "system"
    }
    Binding {
        target: AppTheme
        property: "reduceTransparency"
        value: root.applicationSettings
            ? root.applicationSettings.reduceTransparency : false
    }
    Binding {
        target: AppTheme
        property: "reduceMotion"
        value: root.applicationSettings
            ? root.applicationSettings.reduceMotion : false
    }
    Binding {
        target: AppTheme
        property: "nativeBlurAvailable"
        value: root.applicationSettings
            ? root.applicationSettings.nativeBlurAvailable : false
    }

    background: Rectangle {
        color: AppTheme.windowSurface

        Behavior on color { ColorAnimation { duration: AppTheme.motionNormal } }

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: AppTheme.windowTintSurface
            }
            GradientStop { position: 0.34; color: AppTheme.windowSurface }
            GradientStop { position: 1; color: AppTheme.windowSurface }
        }
    }
}
