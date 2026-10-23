pragma Singleton
import QtQuick

QtObject {
    property var _backdrops: []

    function registerBackdrop(backdrop) {
        _backdrops = _backdrops.concat([backdrop])
    }

    function unregisterBackdrop(backdrop) {
        _backdrops = _backdrops.filter(item => item !== backdrop)
    }

    function backdropFor(window) {
        if (!window) return null
        for (let index = _backdrops.length - 1; index >= 0; --index) {
            const backdrop = _backdrops[index]
            if (backdrop && backdrop.registerAsDefault && backdrop.available
                    && backdrop.hostWindow === window)
                return backdrop
        }
        return null
    }
}
