#!/usr/bin/env python3
"""Small, dependency-free checks for the versioned platform contracts."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_shortcuts_contract() -> None:
    data = json.loads((ROOT / "shared/contracts/shortcuts.v1.json").read_text())
    assert data["version"] == 1
    ids = [item["id"] for item in data["shortcuts"]]
    assert len(ids) == len(set(ids))
    for item in data["shortcuts"]:
        assert item["target"]
        assert item["action"]
        assert item["default"]


def test_platform_contract_mentions_socket_and_errors() -> None:
    text = (ROOT / "shared/contracts/platform.v1.md").read_text()
    assert "kos-platform.sock" in text
    assert "requestId" in text
    assert "retryable" in text


if __name__ == "__main__":
    test_shortcuts_contract()
    test_platform_contract_mentions_socket_and_errors()
    print("platform contracts: ok")
