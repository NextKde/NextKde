import { copyFileSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
export function stageIcons(directory) {
    const common = join(directory, "desktop/modules/common");
    mkdirSync(common, {recursive: true});
    symlinkSync(new URL("../../shell/shared", import.meta.url), join(directory, "shared"), "dir");
    const declarations = ["singleton AppearanceTokens 1.0 AppearanceTokens.qml"];
    writeFileSync(join(common, "AppearanceTokens.qml"), `pragma Singleton
import QtQuick
QtObject { readonly property bool isDarkTheme: true }
`);
    for (const name of ["AppIcon", "BundledIcon", "ShellText", "GlassText", "BundledIcons", "AppPresentationService", "SystemIconResolver", "IconThemeReloadService"]) {
        copyFileSync(new URL(`../../shell/desktop/modules/common/${name}.qml`, import.meta.url), join(common, `${name}.qml`));
        declarations.push(`${["AppIcon", "BundledIcon", "ShellText", "GlassText"].includes(name) ? "" : "singleton "}${name} 1.0 ${name}.qml`);
    }
    writeFileSync(join(common, "qmldir"), `module qs.desktop.modules.common\n${declarations.join("\n")}\n`);
    copyFileSync(new URL("../../shell/desktop/modules/bar/NotificationSourceIcon.qml", import.meta.url), join(directory, "NotificationSourceIcon.qml"));
}
