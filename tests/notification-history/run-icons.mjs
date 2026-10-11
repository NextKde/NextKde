import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
        copyFileSync(new URL(`../../shell/desktop/modules/bar/${name}.qml`, import.meta.url), join(directory, `${name}.qml`));
    writeFileSync(join(directory, "qmldir"), "NotificationSourceIcon 1.0 NotificationSourceIcon.qml\nNotificationHistoryGroup 1.0 NotificationHistoryGroup.qml\nNotificationHistoryEntry 1.0 NotificationHistoryEntry.qml\n");
    const data = join(directory, "data");
    mkdirSync(join(data, "applications"), {recursive: true});
    const iconPath = join(directory, "app-icon.svg");
    writeFileSync(iconPath, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" rx="5" fill="#0088dd"/><path d="M6 12h12M12 6v12" stroke="#fff" stroke-width="3"/></svg>');
    const themeDir = join(data, "icons/hicolor/48x48/places");
    mkdirSync(themeDir, {recursive: true});
    copyFileSync(iconPath, join(themeDir, "folder.svg"));
    writeFileSync(join(data, "icons/hicolor/index.theme"), "[Icon Theme]\nName=hicolor\nDirectories=48x48/places\n[48x48/places]\nSize=48\nContext=Places\nType=Fixed\n");
    writeFileSync(join(data, "applications/org.test.icon.desktop"), `[Desktop Entry]\nType=Application\nName=Icon Fixture\nExec=true\nIcon=${iconPath}\n`);
    const imagePath = join(qaDirectory, process.argv.includes("--stacks") ? "macos-stacks-dark-light.png" : "stack-and-icons.png");
    const result = spawnSync(process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : "quickshell", ["-p", directory], {encoding: "utf8", timeout: 7000,
        env: {...process.env, XDG_DATA_HOME: data, QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "kde", QT_QUICK_BACKEND: "software", KOS_ICON_TEST_PATH: iconPath, KOS_ICON_QA_IMAGE: imagePath}});
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.status, 0, output);
    assert.match(output, /NOTIFICATION_ICONS_TEST_PASS/);
    assert.doesNotMatch(output, /TypeError|ReferenceError|Required property|Binding loop|Error:|Failed to load/);
    console.log(`Notification theme/path/desktop/fallback icons and dark/light stacks passed; QA: ${imagePath}`);
} finally { rmSync(directory, {recursive: true, force: true}); }
