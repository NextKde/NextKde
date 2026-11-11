import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Exercise the shipping presentation and animation in Qt Quick without a
// desktop session. Only the common-module import/token singleton is replaced.
const directory = mkdtempSync(join(tmpdir(), "kos-inputmethod-motion-"));
try {
    const source = new URL("../../shell/desktop/modules/", import.meta.url);
    writeFileSync(join(directory, "InputMethodPresentation.qml"),
        readFileSync(new URL("inputmethod/InputMethodPresentation.qml", source), "utf8")
            .replace("import qs.desktop.modules.common", 'import "."'));
    copyFileSync(new URL("common/PopupMotion.qml", source), join(directory, "PopupMotion.qml"));
    copyFileSync(new URL("inputmethod/InputMethodPlacement.mjs", source), join(directory, "InputMethodPlacement.mjs"));
    writeFileSync(join(directory, "InputMethodService.qml"),
        readFileSync(new URL("inputmethod/InputMethodService.qml", source), "utf8")
            .replace("import Quickshell", "")
            .replace("import qs.desktop.modules.platform", 'import "."')
            .replace("import qs.desktop.modules.dock", "")
            .replace("import qs.desktop.modules.common", "")
            .replace("Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null", "null"));
    copyFileSync(new URL("motion.qml", import.meta.url), join(directory, "tst_motion.qml"));
    copyFileSync(new URL("appearance.qml", import.meta.url), join(directory, "tst_appearance.qml"));
    writeFileSync(join(directory, "InputMethodCandidateList.qml"),
        readFileSync(new URL("inputmethod/InputMethodCandidateList.qml", source), "utf8")
            .replace("import qs.desktop.modules.common", 'import "."')
            .replace('import "../../../shared/qml/i18n"', "")
            .replaceAll("GlassText", "Text").replaceAll("I18n.tr", "qsTr"));
    writeFileSync(join(directory, "InputMethodConfigService.qml"),
        readFileSync(new URL("inputmethod/InputMethodConfigService.qml", source), "utf8")
            .replace("import Quickshell", "")
            .replace("import qs.desktop.modules.platform", 'import "."')
            .replace("Quickshell.stateDir", '"/state/kos"'));
    writeFileSync(join(directory, "JsonConfigStore.qml"), `pragma Singleton
import QtQuick
QtObject {
    property var writes: []
    property bool writeSucceeds: true
    function readPath(path, callback) {
        Qt.callLater(() => callback('{"fontSize":18,"layout":"adaptive","showAnnotations":false}', true))
    }
    function writePath(path, data, callback) {
        writes = writes.concat([{path, data}]); callback(writeSucceeds)
    }
}
`);
    writeFileSync(join(directory, "qmldir"),
        "singleton AppearanceTokens 1.0 AppearanceTokens.qml\n"
        + "singleton InputMethodService 1.0 InputMethodService.qml\n"
        + "singleton PlatformClient 1.0 PlatformClient.qml\n"
        + "singleton WindowService 1.0 WindowService.qml\n");
    writeFileSync(join(directory, "qmldir"), readFileSync(join(directory, "qmldir"), "utf8")
        + "singleton ScreenLifecycle 1.0 ScreenLifecycle.qml\n"
        + "singleton InputMethodConfigService 1.0 InputMethodConfigService.qml\n"
        + "singleton JsonConfigStore 1.0 JsonConfigStore.qml\n");
    writeFileSync(join(directory, "ScreenLifecycle.qml"), `pragma Singleton
import QtQuick
QtObject {
    property var usableScreens: [{name:"screen-a",x:0,y:0,width:1920,height:1080}]
    property var activeScreen: usableScreens[0]
}
`);
    writeFileSync(join(directory, "PlatformClient.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool connected: false
    property var calls: []
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)
    function supports(op) { return true }
    function request(op, payload, callback) { calls = calls.concat([{ op, payload, callback }]) }
}
`);
    writeFileSync(join(directory, "WindowService.qml"), `pragma Singleton
import QtQuick
QtObject {
    property string kwinActiveId: "window-a"
    property var records: []
}
`);
    copyFileSync(new URL("../../shared/qml/foundation/MotionTokens.qml", import.meta.url), join(directory, "MotionTokens.qml"));
    writeFileSync(join(directory, "AppearanceTokens.qml"), `pragma Singleton
import QtQuick
QtObject {
    property MotionTokens motion: MotionTokens {
        property int popupOpenDuration: base.duration
        property int popupCloseDuration: base.duration
    }
}
`);
    const result = spawnSync(process.argv[2] || "qmltestrunner", ["-input", directory], {
        encoding: "utf8", timeout: 20000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            WAYLAND_DISPLAY: "", DISPLAY: "" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL!|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
