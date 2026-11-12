import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, readFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { stageIcons } from "./stage-icons.mjs";
const directory = mkdtempSync(join(tmpdir(), "nextkde-notification-icons-"));
const qaDirectory = join(tmpdir(), "nextkde-notification-qa");
mkdirSync(qaDirectory, {recursive: true});
try {
    stageIcons(directory);
    copyFileSync(new URL(process.argv.includes("--stacks") ? "mac-stacks.qml" : "icons.qml", import.meta.url), join(directory, "shell.qml"));
    for (const name of ["NotificationHistoryGroup", "NotificationHistoryEntry"])
        writeFileSync(join(directory, `${name}.qml`), readFileSync(new URL(`../../shell/desktop/modules/bar/${name}.qml`, import.meta.url), "utf8")
            .replaceAll('"../../../shared/qml/i18n"', '"./shared/qml/i18n"'));
    writeFileSync(join(directory, "qmldir"), "NotificationSourceIcon 1.0 NotificationSourceIcon.qml\nNotificationHistoryGroup 1.0 NotificationHistoryGroup.qml\nNotificationHistoryEntry 1.0 NotificationHistoryEntry.qml\n");
    // Static integration guard: the actual popup must consume the same
    // component tested below, with raw fields retained through its exit.
    const popup = readFileSync(new URL("../../shell/desktop/modules/notifications/NotificationWindow.qml", import.meta.url), "utf8");
    assert.match(popup, /NotificationIcon\s*\{/);
    for (const field of ["image", "appIcon", "desktopEntry"])
        assert(popup.includes(`${field}: card.displayIcon.${field}`), `Popup lost ${field} wiring`);
    assert.doesNotMatch(popup, /AppIdentityService\._iconPath|_lastIconSource/);
    const data = join(directory, "data");
    const config = join(directory, "config");
    mkdirSync(join(data, "applications"), {recursive: true});
    mkdirSync(config, {recursive: true});
    writeFileSync(join(config, "kdeglobals"), "[Icons]\nTheme=hicolor\n");
    const iconPath = join(directory, "nextkde-test-custom.svg");
    writeFileSync(iconPath, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" rx="5" fill="#0088dd"/><path d="M6 12h12M12 6v12" stroke="#fff" stroke-width="3"/></svg>');
    const themedPath = join(directory, "nextkde-test-themed.svg");
    copyFileSync(iconPath, themedPath);
    const themeDir = join(data, "icons/hicolor/48x48/apps");
    mkdirSync(themeDir, {recursive: true});
    for (const name of ["nextkde-test-themed", "kos-calendar"])
        writeFileSync(join(themeDir, `${name}.svg`), '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="12" fill="#dd4488"/></svg>');
    writeFileSync(join(themeDir, "nextkde-test-broken.png"), "not a decodable image");
    writeFileSync(join(data, "icons/hicolor/index.theme"), "[Icon Theme]\nName=hicolor\nDirectories=48x48/apps\n[48x48/apps]\nSize=48\nContext=Applications\nType=Fixed\n");
    for (const [id, icon] of [["icon", "nextkde-test-themed"], ["custom", iconPath], ["path", themedPath], ["broken", "nextkde-test-broken"]])
        writeFileSync(join(data, `applications/org.test.${id}.desktop`), `[Desktop Entry]\nType=Application\nName=Icon Fixture ${id}\nExec=true\nIcon=${icon}\n`);
    const imagePath = join(qaDirectory, process.argv.includes("--stacks") ? "macos-stacks-dark-light.png" : "stack-and-icons.png");
    const result = spawnSync(process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "quickshell", ["-p", directory], {encoding: "utf8", timeout: 7000,
        env: {...process.env, XDG_CONFIG_HOME: config, XDG_DATA_HOME: data, XDG_DATA_DIRS: data, QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "kde", QT_QUICK_BACKEND: "software", KOS_ICON_TEST_PATH: iconPath, KOS_ICON_THEMED_PATH: themedPath, KOS_ICON_QA_IMAGE: imagePath}});
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.status, 0, output);
    assert.match(output, /NOTIFICATION_ICONS_TEST_PASS/);
    assert.doesNotMatch(output, /TypeError|ReferenceError|Required property|Binding loop|Unable to assign|Cannot assign|Error:|Failed to load/);
    console.log(process.argv.includes("--stacks")
        ? `Notification dark/light stack capture passed; QA: ${imagePath}`
        : `Notification source/popup wiring, themed priority, custom/content/decode fallbacks and stable-URL reload checks passed; QA: ${imagePath}`);
} finally { rmSync(directory, {recursive: true, force: true}); }
