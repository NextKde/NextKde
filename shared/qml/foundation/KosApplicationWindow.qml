import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: root

    width: 1180
    height: 760
    minimumWidth: 760
    minimumHeight: 520
    color: AppTheme.window

    palette.window: AppTheme.window
    palette.windowText: AppTheme.text
    palette.text: AppTheme.text
    palette.buttonText: AppTheme.text
    palette.base: AppTheme.windowRaised
    palette.highlight: AppTheme.accent
    palette.highlightedText: "white"

    background: Rectangle {
        color: AppTheme.window

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0
                color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.09 : 0.07)
            }
            GradientStop { position: 0.42; color: AppTheme.window }
            GradientStop { position: 1; color: AppTheme.window }
        }
    }
}
