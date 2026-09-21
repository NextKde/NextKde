// ScreenSelection.mjs
// 通用多显示器主屏幕选举算法 / Generic multi-monitor primary screen election algorithm

/**
 * 当无法从系统获取显式优先级的无偏几何兜底算法：
 * 1. 若当前已选屏幕仍然存在且有效，保持不变以防止插拔抖动；
 * 2. 否则，计算所有可用屏幕在虚拟桌面上的水平几何中心，选取中心点最靠近物理居中位置的屏幕；
 * 3. 若只有一个屏幕，直接返回该屏幕。
 * 纯数学几何计算，零硬件接口名称依赖（不假定 DP/HDMI/eDP 等名称）。
 */
function fallbackScreen(screens, currentScreen) {
    if (screens && screens.includes(currentScreen)) {
        return currentScreen;
    }
    if (!screens || screens.length === 0) {
        return null;
    }
    if (screens.length === 1) {
        return screens[0];
    }

    // 计算整个多显示器虚拟桌面的水平边界
    let minX = Number.POSITIVE_INFINITY;
    let maxX = Number.NEGATIVE_INFINITY;
    for (const s of screens) {
        const sx = Number(s.x || 0);
        const sw = Number(s.width || 0);
        if (sx < minX) minX = sx;
        if (sx + sw > maxX) maxX = sx + sw;
    }
    const overallCenterX = (minX + maxX) / 2;

    // 寻找物理中心最靠近总体中心的屏幕（居中显示器）
    let bestScreen = screens[0];
    let bestDist = Number.POSITIVE_INFINITY;
    for (const s of screens) {
        const sx = Number(s.x || 0);
        const sw = Number(s.width || 0);
        const screenCenterX = sx + sw / 2;
        const dist = Math.abs(screenCenterX - overallCenterX);
        if (dist < bestDist) {
            bestDist = dist;
            bestScreen = s;
        }
    }
    return bestScreen;
}

/**
 * 主选屏函数：
 * @param screens Quickshell / Qt 提供的当前可用屏幕列表
 * @param outputs 系统 (KDE KScreen / Wayland) 上报的显示输出配置
 * @param currentScreen 当前已选定的主屏幕实例
 */
export function selectScreen(screens, outputs, currentScreen) {
    if (!screens || screens.length === 0) {
        return null;
    }

    // 1. 优先采用系统显式指定的主屏幕（KDE KScreen priority == 1 或 isPrimary 标志）
    const ranked = (outputs || []).filter(output => output && output.connected && output.enabled
        && Number(output.priority) > 0)
        .slice().sort((a, b) => Number(a.priority) - Number(b.priority));

    for (const output of ranked) {
        const screen = screens.find(candidate => candidate && candidate.name === output.name);
        if (screen)
            return screen;
    }

    // 2. 若系统未提供有效优先级，采用纯几何无偏算法进行居中保底选屏
    return fallbackScreen(screens, currentScreen);
}
