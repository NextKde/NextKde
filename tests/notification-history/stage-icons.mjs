import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
export function stageIcons(directory) {
    const common = join(directory, "desktop/modules/common");
    mkdirSync(common, {recursive: true});
    const declarations = [];
    for (const name of ["AppIcon", "BundledIcon", "BundledIcons", "AppPresentationService", "SystemIconResolver", "IconThemeReloadService"]) {
        copyFileSync(new URL(`../../shell/desktop/modules/common/${name}.qml`, import.meta.url), join(common, `${name}.qml`));
        declarations.push(`${["AppIcon", "BundledIcon"].includes(name) ? "" : "singleton "}${name} 1.0 ${name}.qml`);
    }
    writeFileSync(join(common, "qmldir"), `module qs.desktop.modules.common\n${declarations.join("\n")}\n`);
    copyFileSync(new URL("../../shell/desktop/modules/bar/NotificationSourceIcon.qml", import.meta.url), join(directory, "NotificationSourceIcon.qml"));
}
