import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.platform

ShellRoot {
    readonly property var service: IndependentAppWidgetService
    readonly property var transport: PlatformClient
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (!PlatformClient.connected || IndependentAppWidgetService.pending.calendar
                    || IndependentAppWidgetService.pending.weather)
                return
            stop()
            IndependentAppWidgetService.poll.stop()
            IndependentAppWidgetService.weatherPoll.stop()
            PlatformClient.request("test.begin", {}, function() {
                IndependentAppWidgetService.weather = JSON.parse(Quickshell.env("WIDGET_CACHED_STATE"))
                if (Quickshell.env("WIDGET_IN_FLIGHT_POLL") === "1")
                    IndependentAppWidgetService.reload("weather")
                IndependentAppWidgetService.open("weather", { location: "old-location" })
                IndependentAppWidgetService.open("weather", { location: "old-location" })
                finish.start()
            })
        }
    }
    Timer {
        id: finish
        interval: 20
        repeat: true
        onTriggered: {
            if (IndependentAppWidgetService.opening.weather || IndependentAppWidgetService.pending.weather)
                return
            console.log("WIDGET_OPEN_RESULT " + JSON.stringify({
                state: IndependentAppWidgetService.weather.state,
                error: IndependentAppWidgetService.launchErrors.weather || "",
                busy: !!IndependentAppWidgetService.opening.weather
            }))
            Qt.quit()
        }
    }
}
