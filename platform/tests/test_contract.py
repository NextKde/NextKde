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


def test_nightlight_toggle_does_not_overwrite_user_configuration() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    toggle = source[source.index('if (op == QStringLiteral("nightlight.toggle"))'):]
    toggle = toggle[:toggle.index('if (op == QStringLiteral("shortcuts.apply"))')]
    assert 'QStringLiteral("inhibit")' in toggle
    assert 'QStringLiteral("uninhibit")' in toggle
    assert "m_nightLightInhibitionCookie" in toggle
    assert "kwriteconfig6" not in toggle
    assert 'QStringLiteral("NightColor")' not in toggle


def test_bridge_trace_is_opt_in() -> None:
    source = (ROOT / "platform/src/kwin/KWinBridge.cpp").read_text()
    publish = source[source.index("void publishEvent("):source.index("void publishThumbnailError(")]
    assert 'qEnvironmentVariableIntValue("KOS_PLATFORM_TRACE_EVENTS") == 1' in publish
    assert publish.index("g_eventHandler(event)") < publish.index("if (traceEvents)")
    assert publish.index("if (traceEvents)") < publish.index("QJsonDocument(event).toJson")


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
    test_application_launch_uses_kde_launcher_without_arbitrary_commands()
    test_theme_toggle_uses_the_safe_palette_path()
    test_nightlight_toggle_does_not_overwrite_user_configuration()
    test_bridge_trace_is_opt_in()
    test_brightness_targets_one_kde_display()
    print("platform contracts: ok")
