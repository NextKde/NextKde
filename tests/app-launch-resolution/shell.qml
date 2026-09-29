import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Regression guard for the launch-by-id contract.
//
// A presentation descriptor, an identity result and every model item must
// carry strings only. Storing a live DesktopEntry there used to crash the shell
// with SIGSEGV: DesktopEntries replaces and destroys entries on each catalogue
// rescan, and QML does not track a QObject* wrapped inside a QVariantMap, so
// delegation incubation and teardown dereferenced freed memory.
//
// This checks both halves of the contract: nothing stores an entry, and the
// launch path still resolves one from the id and hands the daemon the right
// desktop id.
Item {
    property bool started: false

    function check(condition, message) {
        if (!condition)
            throw new Error(message)
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (started)
                return
            const installed = DesktopEntries.applications?.values ?? []
            if (!installed.length)
                return
            started = true
            try {
                const catalogue = AppPresentationService.catalog()
                check(catalogue.length > 0, "the catalogue must not be empty")

                const description = catalogue[0]
                check(description.desktopId.length > 0,
                    "a descriptor must expose its desktopId")
                check(description.displayName.length > 0,
                    "a descriptor must expose a displayName")
                check(description.iconSource.length > 0,
                    "a descriptor must expose an iconSource")
                check(description.entry === undefined,
                    "a descriptor must not carry a live DesktopEntry")

                const entry = AppPresentationService.entryFor(description.desktopId)
                check(entry && typeof entry.execute === "function",
                    "entryFor must resolve a live entry from a desktopId")
                const bare = AppPresentationService.entryFor(
                    description.desktopId.replace(/\.desktop$/i, ""))
                check(bare && typeof bare.execute === "function",
                    "entryFor must accept an id without the .desktop suffix")

                const identity = AppIdentityService.resolve(description.desktopId)
                check(identity.entry === undefined,
                    "an identity result must not carry a live DesktopEntry")
                check(identity.iconSource.length > 0,
                    "an identity result must still resolve an icon source")

                // An uninstalled id must still reach the daemon: the daemon op
                // takes the desktop id alone, so a missing entry is not a
                // reason to drop the request before the launch path.
                console.log("APP_LAUNCH_TARGET " + description.desktopId)
                AppActionService.launch(description)
                AppActionService.launch(identity)
                AppActionService.launch({ desktopId: "kos-missing-entry.desktop" })

                // The Dock's "new window" action used to branch on the entry it
                // had cached on the identity. It must now resolve the entry
                // itself and still reach the daemon with the canonical id.
                const second = catalogue.length > 1 ? catalogue[1] : null
                if (second) {
                    console.log("APP_LAUNCH_SECOND " + second.desktopId)
                    DockModelService.launchNewWindow(second.desktopId)
                }
                settled.restart()
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }

    Timer {
        id: settled
        interval: 2500
        onTriggered: {
            console.log("APP_LAUNCH_RESOLUTION_PASS")
            Qt.quit()
        }
    }

    Timer {
        interval: 12000
        running: true
        onTriggered: {
            console.log("FAIL the installed-app catalogue never became ready")
            Qt.quit()
        }
    }
}
