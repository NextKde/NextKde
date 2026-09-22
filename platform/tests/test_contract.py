#!/usr/bin/env python3
"""Small, dependency-free checks for the versioned platform contracts."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

# The authoritative default shortcut table lives in the Shell's
# ShortcutsService; it must keep referring to every documented target.
SHORTCUTS_SERVICE = ROOT / "shell/desktop/modules/shortcuts/ShortcutsService.qml"


def test_shortcuts_service_defaults() -> None:
    text = SHORTCUTS_SERVICE.read_text()
    ids = re.findall(r'id: "(net\.local\.kos-[^"]+)"', text)
    assert len(ids) == 6, f"expected 6 KOS shortcuts, found {ids}"
    assert len(ids) == len(set(ids))
    for required in ("net.local.kos-launcher", "net.local.kos-window-switcher"):
        assert required in ids


def test_platform_contract_mentions_socket_and_errors() -> None:
    text = (ROOT / "shared/contracts/platform.v1.md").read_text()
    assert "kos-platform.sock" in text
    assert "requestId" in text
    assert "retryable" in text
    assert "kwin.layout.update" in text
    for field in ("outputName", "outputRect", "barReservedHeight", "dockRect"):
        assert field in text


def test_literal_shell_operations_have_daemon_handlers() -> None:
    """Every literal platform request in QML must exist in the daemon.

    Keeping this check generic prevents a client-only operation from degrading
    into a startup notification saying "unknown platform operation".
    Dynamic operation names remain covered by their owning feature tests.
    """
    request_patterns = (
        re.compile(r'PlatformClient\.request\(\s*"([^"]+)"'),
        re.compile(r'_platform\(\s*"([^"]+)"'),
    )
    operations: set[str] = set()
    for qml in (ROOT / "shell").rglob("*.qml"):
        text = qml.read_text()
        for pattern in request_patterns:
            operations.update(pattern.findall(text))

    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    missing = sorted(
        operation
        for operation in operations
        if f'QStringLiteral("{operation}")' not in source
    )
    assert not missing, f"QML requests unsupported platform operations: {missing}"


def test_application_launch_uses_kde_launcher_without_arbitrary_commands() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    handler = source[source.index("bool PlatformServer::handleApplication"):]
    handler = handler[:handler.index("bool PlatformServer::handleFileOperation")]
    assert 'QStringLiteral("application.launch")' in handler
    assert "KService::serviceByStorageId" in handler
    assert "KIO::ApplicationLauncherJob" in handler
    assert 'value(QStringLiteral("desktopId"))' in handler
    assert 'value(QStringLiteral("urls"))' in handler
    assert 'value(QStringLiteral("command"))' not in handler

    qml = (ROOT / "shell/desktop/modules/common/AppActionService.qml").read_text()
    assert 'PlatformClient.request("application.launch"' in qml
    assert "systemd-run" not in qml

    main = (ROOT / "platform/src/daemon/main.cpp").read_text()
    assert "app.setQuitOnLastWindowClosed(false)" in main
    assert "QCoreApplication::setQuitLockEnabled(false)" in main
    assert "PlatformServer::~PlatformServer()" in source


def test_theme_toggle_uses_the_safe_palette_path() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    toggle = source[source.index('if (op == QStringLiteral("theme.toggle"))'):]
    assert "QSettings settings" in toggle
    assert 'QStringLiteral("ColorScheme")' in toggle
    assert 'QStringLiteral("Colors:Window/BackgroundNormal")' in toggle
    assert "auto *reader" not in toggle
    helper = source[source.index("void PlatformServer::applySystemTheme"):]
    assert helper.index("plasma-apply-colorscheme") < helper.index(
        "plasma-apply-lookandfeel"
    )


def test_nightlight_toggle_only_changes_persistent_master_switch() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    toggle = source[source.index('if (op == QStringLiteral("nightlight.toggle"))'):]
    toggle = toggle[:toggle.index('if (op == QStringLiteral("shortcuts.apply"))')]
    assert 'QStringLiteral("NightColor/Active")' in toggle
    assert 'QStringLiteral("inhibit")' in toggle
    assert 'QStringLiteral("uninhibit")' in toggle
    assert 'QStringLiteral("reconfigure")' in toggle
    for key in ("Mode", "NightTemperature", "LatitudeAuto", "LongitudeAuto"):
        assert f'QStringLiteral("NightColor/{key}")' not in toggle


def test_bridge_trace_is_opt_in() -> None:
    source = (ROOT / "platform/src/kwin/KWinBridge.cpp").read_text()
    publish = source[source.index("void publishEvent("):source.index("void publishThumbnailError(")]
    assert 'qEnvironmentVariableIntValue("KOS_PLATFORM_TRACE_EVENTS") == 1' in publish
    assert publish.index("g_eventHandler(event)") < publish.index("if (traceEvents)")
    assert publish.index("if (traceEvents)") < publish.index("QJsonDocument(event).toJson")


def assert_thumbnail_fd_ownership(source: str) -> None:
    """Both ends of the screenshot pipe must have exactly one owner.

    Measured against the shipped binary before this was fixed: every capture
    leaked two descriptors - the drain's read end, and the local write end that
    was duplicated for QDBusUnixFileDescriptor and then never closed (that
    class duplicates what it is handed: Qt 6 setFileDescriptor() calls
    qt_safe_dup()). Two per capture reached RLIMIT_NOFILE after a few hundred
    thumbnails, and glib then aborted the whole daemon on the next thread that
    needed a wakeup pipe.
    """
    body = source[source.index("void captureThumbnail("):]
    body = body[:body.index("static QString normalizeName(")]
    # The capture is dispatched with asyncCall() so a stalled or slow KWin reply
    # cannot block every other bridge request. The message is still marshalled
    # and sent before the call returns (NoBlock defers the reply, not the send),
    # which is what lets the duplicated write end go back at that point.
    call_site = body.index("screenshot.asyncCall(")
    before_call = body[:call_site]
    after_call = body[call_site:]

    assert body.count("::dup(pipeFds[1])") == 1, "one local write end, no more"
    # The failed-dup exit is the only place this side may close either pipe end.
    assert before_call.count("::close(pipeFds[0])") == 1, "failed-dup exit closes the read end"
    assert before_call.count("::close(pipeFds[1])") == 1, "failed-dup exit closes the write end"
    assert "::close(dbusWriteFd)" not in before_call, \
        "the descriptor handed to D-Bus must outlive the call"
    # After the call both of our write ends go back: the pipe end, and the
    # duplicate we made for QDBusUnixFileDescriptor, which only copies it.
    assert after_call.count("::close(pipeFds[1])") == 1, "the pipe write end needs one owner"
    assert after_call.count("::close(dbusWriteFd)") == 1, \
        "the duplicated write end needs one owner"


def test_thumbnail_drain_owns_the_read_descriptor() -> None:
    source = (ROOT / "platform/src/kwin/KWinBridge.cpp").read_text()
    drain = source[source.index("auto pixelsFuture = QtConcurrent::run("):]
    drain = drain[:drain.index("QVariantMap options;")]
    # The loop returns from four branches. Hand-closing the read end on two of
    # them leaked one descriptor per capture, which eventually exhausted
    # RLIMIT_NOFILE and made glib abort the daemon inside a new thread.
    assert drain.count("::close(readFd)") == 1, "the read fd needs exactly one owner"
    assert drain.index("qScopeGuard") < drain.index("return"), "install the guard first"
    assert "::close(readFd);\n                return" not in drain, "no hand-closed exit"


def test_thumbnail_capture_closes_every_descriptor_it_opens() -> None:
    assert_thumbnail_fd_ownership((ROOT / "platform/src/kwin/KWinBridge.cpp").read_text())


def test_brightness_targets_one_kde_display() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    assert "openScreenBrightness" in source
    assert 'property("DisplaysDBusNames")' in source
    assert 'QStringLiteral("org.kde.ScreenBrightness.Display")' in source
    setter = source[source.index("bool setKdeDisplayBrightness("):]
    setter = setter[:setter.index("QJsonObject readSysfsBrightness()")]
    assert "displayIds.contains(displayId)" in setter
    assert 'display.call(QStringLiteral("SetBrightness")' in setter
    assert "for (const QString &displayId : displayIds)" not in setter

    handler = source[source.index('if (op == QStringLiteral("display.brightness.set"))'):]
    handler = handler[:handler.index('if (op == QStringLiteral("theme.reconfigure"))')]
    assert 'payload.value(QStringLiteral("displayId"))' in handler
    assert "setKdeDisplayBrightness(displayId, value)" in handler


if __name__ == "__main__":
    test_shortcuts_service_defaults()
    test_platform_contract_mentions_socket_and_errors()
    test_literal_shell_operations_have_daemon_handlers()
    test_application_launch_uses_kde_launcher_without_arbitrary_commands()
    test_theme_toggle_uses_the_safe_palette_path()
    test_nightlight_toggle_only_changes_persistent_master_switch()
    test_bridge_trace_is_opt_in()
    test_thumbnail_drain_owns_the_read_descriptor()
    test_thumbnail_capture_closes_every_descriptor_it_opens()
    test_brightness_targets_one_kde_display()
    print("platform contracts: ok")
