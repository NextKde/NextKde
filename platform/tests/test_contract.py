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


def test_theme_toggle_uses_the_safe_palette_path() -> None:
    source = (ROOT / "platform/src/daemon/PlatformServer.cpp").read_text()
    toggle = source[source.index('if (op == QStringLiteral("theme.toggle"))'):]
    assert "QSettings settings" in toggle
    assert "auto *reader" not in toggle
    helper = source[source.index("void PlatformServer::applySystemTheme"):]
    assert helper.index("plasma-apply-colorscheme") < helper.index(
        "plasma-apply-lookandfeel"
    )


if __name__ == "__main__":
    test_shortcuts_service_defaults()
    test_platform_contract_mentions_socket_and_errors()
    test_theme_toggle_uses_the_safe_palette_path()
    print("platform contracts: ok")
