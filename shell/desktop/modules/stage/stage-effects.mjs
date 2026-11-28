// D-Bus loadEffect returns a boolean even when qdbus exits successfully.
// Keep the current effect until the replacement is verified; restore runtime
// and persistent plugin state if any subsequent step fails.
export function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// Distributions name the Qt 6 D-Bus CLI differently: qdbus6 (Arch, openSUSE),
// qdbus-qt6 or the Qt 6 bin directory's qdbus (Fedora), plain qdbus
// elsewhere. Fedora ships no qdbus6 at all, so a hard-coded name fails every
// Stage transition there before KWin is ever asked. Sets $qdbus, or fails.
export const QDBUS_RESOLVE = "qdbus=$(command -v qdbus6 || command -v qdbus-qt6"
    + " || { [ -x /usr/lib64/qt6/bin/qdbus ] && echo /usr/lib64/qt6/bin/qdbus; }"
    + " || { [ -x /usr/lib/qt6/bin/qdbus ] && echo /usr/lib/qt6/bin/qdbus; }"
    + " || command -v qdbus)";

export function reconfigureEffectCommand(effectId) {
    if (!/^[a-zA-Z0-9_]+$/.test(effectId))
        throw new Error("invalid effect id");
    return `{ ${QDBUS_RESOLVE} && "$qdbus" org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect ${shellQuote(effectId)}; }`;
}

export function effectSwitchCommand(enabled, effectId, commit = ":") {
    if (!/^[a-zA-Z0-9_]+$/.test(effectId))
        throw new Error("invalid effect id");
    const next = enabled ? effectId : "kos_dock_window_animation";
    const previous = enabled ? "kos_dock_window_animation" : effectId;
    return `set -e
${QDBUS_RESOLVE}
next=${shellQuote(next)}
previous=${shellQuote(previous)}
call_effect() { "$qdbus" org.kde.KWin /Effects "org.kde.kwin.Effects.$1" "$2"; }
next_loaded=$(call_effect isEffectLoaded "$next")
previous_loaded=$(call_effect isEffectLoaded "$previous")
case "$next_loaded:$previous_loaded" in true:true|true:false|false:true|false:false) ;; *) exit 1 ;; esac
next_config=$(kreadconfig6 --file kwinrc --group Plugins --key "${next}Enabled" --default __missing__)
previous_config=$(kreadconfig6 --file kwinrc --group Plugins --key "${previous}Enabled" --default __missing__)
restore_config() {
    if [ "$2" = __missing__ ]; then
        kwriteconfig6 --file kwinrc --group Plugins --key "$1Enabled" --delete
    else
        kwriteconfig6 --file kwinrc --group Plugins --key "$1Enabled" "$2"
    fi
}
rollback() {
    rc=$?
    trap - EXIT
    if [ "$rc" -ne 0 ]; then
        set +e
        # Restore the previous effect before unloading the replacement.
        [ "$previous_loaded" != true ] || call_effect loadEffect "$previous" >/dev/null
        [ "$next_loaded" = true ] || call_effect unloadEffect "$next"
        restore_config "$next" "$next_config"
        restore_config "$previous" "$previous_config"
    fi
    exit "$rc"
}
trap rollback EXIT
if [ "$next_loaded" != true ]; then
    [ "$(call_effect loadEffect "$next")" = true ]
fi
[ "$(call_effect isEffectLoaded "$next")" = true ]
call_effect unloadEffect "$previous"
[ "$(call_effect isEffectLoaded "$previous")" = false ]
kwriteconfig6 --file kwinrc --group Plugins --key "${next}Enabled" true
kwriteconfig6 --file kwinrc --group Plugins --key "${previous}Enabled" false
${commit}
trap - EXIT`;
}
