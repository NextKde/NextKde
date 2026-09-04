import assert from "node:assert/strict";

function normalize(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : NaN;
}

function compositorBlurLevel(strength) {
    const value = normalize(strength);
    return Number.isFinite(value)
        ? Math.round(1 + Math.pow(value, 1.5) * 14) : 1;
}

// KWin owns one glass configuration. Surface names remain consumer aliases,
// not independent compositor settings.
function computeEffective(state) {
    const rawBlur = normalize(state.globalBlurStrength ?? state.blurStrength
        ?? state.dockBlurStrength ?? 0.42);
    const rawLiquid = normalize(state.globalLiquidStrength ?? state.liquidStrength
        ?? state.dockLiquidStrength ?? 1.0);
    const blur = Number.isFinite(rawBlur) ? rawBlur : 0.42;
    const liquid = Number.isFinite(rawLiquid) ? rawLiquid : 1.0;
    return {
        dockBlur: blur, dockLiquid: liquid,
        barBlur: blur, barLiquid: liquid,
        launcherBlur: blur, launcherLiquid: liquid,
    };
}

function migrate(previous = {}) {
    return {
        version: 8,
        globalBlurStrength: previous.globalBlurStrength ?? previous.blurStrength
            ?? previous.dockBlurStrength ?? 0.42,
        globalLiquidStrength: previous.globalLiquidStrength ?? previous.liquidStrength
            ?? previous.dockLiquidStrength ?? 1.0,
        shellStyle: previous.shellStyle ?? "macos",
        barIntegratedWithDock: previous.barIntegratedWithDock ?? false,
        barVisibilityMode: previous.barVisibilityMode ?? "always",
        barLayoutMode: previous.barLayoutMode ?? "full",
        dockWindowAnimationStyle: previous.dockWindowAnimationStyle ?? "scale",
    };
}

{
    assert.equal(compositorBlurLevel(0), 1);
    assert.equal(compositorBlurLevel(0.42), 5);
    assert.equal(compositorBlurLevel(0.454), 5);
    assert.equal(compositorBlurLevel(1), 15);
    console.log("ok: compositor blur uses a clear perceptual response");
}

{
    assert.deepEqual(computeEffective({}), {
        dockBlur: 0.42, dockLiquid: 1,
        barBlur: 0.42, barLiquid: 1,
        launcherBlur: 0.42, launcherLiquid: 1,
    });
    console.log("ok: global defaults apply to every surface");
}

{
    assert.deepEqual(computeEffective({ globalBlurStrength: 0.18, globalLiquidStrength: 0.73 }), {
        dockBlur: 0.18, dockLiquid: 0.73,
        barBlur: 0.18, barLiquid: 0.73,
        launcherBlur: 0.18, launcherLiquid: 0.73,
    });
    console.log("ok: global update propagates to every surface");
}

{
    const effective = computeEffective({
        globalBlurStrength: 0.26, globalLiquidStrength: 0.61,
        dockBlurInherit: false, dockBlurStrength: 0.95,
        barBlurInherit: false, barBlurStrength: 0.88,
        launcherBlurInherit: false, launcherLiquidStrength: 0.11,
    });
    assert.equal(effective.dockBlur, 0.26);
    assert.equal(effective.barBlur, 0.26);
    assert.equal(effective.launcherLiquid, 0.61);
    console.log("ok: legacy per-surface values are ignored");
}

{
    const v8 = migrate({ dockBlurStrength: 0.31, dockLiquidStrength: 0.82 });
    assert.equal(v8.version, 8);
    assert.equal(v8.globalBlurStrength, 0.31);
    assert.equal(v8.globalLiquidStrength, 0.82);
    assert.equal("dockBlurStrength" in v8, false);
    assert.equal("barBlurInherit" in v8, false);
    console.log("ok: v7 configuration migrates to flattened v8");
}

console.log("ALL TESTS PASS");
