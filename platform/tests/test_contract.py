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


if __name__ == "__main__":
    test_shortcuts_service_defaults()
    test_platform_contract_mentions_socket_and_errors()
    print("platform contracts: ok")
