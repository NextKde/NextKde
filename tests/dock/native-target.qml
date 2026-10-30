import QtQuick
import QtTest
import "."

Item {
    id: root
    Item { id: surface }
    Item { id: replacementSurface }
    QtObject {
        id: icon
        property var windowAnimationSurface: surface
        property real surfaceOriginX: 1920
        property real surfaceOriginY: 900
        property string animationWindowId: "aaaa-bbbb"
        property string appId: "org.kde.kate.desktop"
        property var target: ({ appId, windowId: animationWindowId,
            x: 2080.5, y: 950.5, width: 44, height: 44 })
        function windowAnimationTarget() { return target }
    }
    TestCase {
        name: "NativeMinimizePublication"
        when: windowShown

        function test_publication_and_cleanup() {
            const service = DockWindowAnimationTargetService
            service.nativeTasks.append({ AppId: "org.kde.kate", WinIdList: ["{aaaa-bbbb}"] })
            service.registerIcon(icon)
            wait(120)
            service.publishNow()
            let calls = service.nativeTasks.requests
            verify(calls.length > 0)
            compare(calls[calls.length - 1].parent, surface)
            compare(calls[calls.length - 1].x, 160)
            compare(calls[calls.length - 1].y, 50)
            compare(calls[calls.length - 1].width, 45)
            verify(PlatformClient.calls > 0, "private effect failure was exercised")

            // Native publication survives the private effect's retry backoff.
            icon.target = { appId: icon.appId, windowId: "aaaa-bbbb",
                x: 2090, y: 960, width: 44, height: 44 }
            service.publishNow()
            calls = service.nativeTasks.requests
            compare(calls[calls.length - 1].x, 170)

            const previous = calls.length
            service.publishNow()
            compare(service.nativeTasks.requests.length, previous, "unchanged geometry is cached")
            service.publishNow(true)
            compare(service.nativeTasks.requests.length, previous + 1, "heartbeat retries the protocol")

            // Move the rectangle to a recreated Dock surface, clearing the old.
            icon.windowAnimationSurface = replacementSurface
            service.publishNow()
            calls = service.nativeTasks.requests
            compare(calls[calls.length - 2].width, 0)
            compare(calls[calls.length - 2].parent, surface)
            compare(calls[calls.length - 1].parent, replacementSurface)

            service.unregisterIcon(icon)
            service.publishNow()
            calls = service.nativeTasks.requests
            compare(calls[calls.length - 1].width, 0, "removed icons invalidate old geometry")
            compare(calls[calls.length - 1].height, 0)
            // Task removal must never publish through a now-reused row index.
            const beforeRemoval = calls.length
            service.nativeTasks.clear()
            wait(20)
            compare(service.nativeTasks.requests.length, beforeRemoval)
        }
    }
}
