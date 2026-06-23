"""Tests for gsettings string-array helpers used by install.sh."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "lib" / "gsettings_strv.py"


def load_module():
    spec = importlib.util.spec_from_file_location("taskbar_count_gsettings_strv", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_append_strv_handles_gsettings_prefix_and_deduplicates():
    mod = load_module()

    assert mod.append_strv("@as ['workspace-window-count@local']", "workspace-window-count@local") == [
        "workspace-window-count@local"
    ]
    assert mod.append_strv("@as ['one']", "two") == ["one", "two"]


def test_append_strv_handles_invalid_existing_values():
    mod = load_module()

    assert mod.append_strv("not an array", "workspace-window-count@local") == [
        "workspace-window-count@local"
    ]


def test_cli_formats_updated_array_from_current_environment(monkeypatch):
    monkeypatch.setenv("CURRENT", "@as ['one']")

    completed = subprocess.run(
        [sys.executable, str(MODULE_PATH), "two"],
        check=True,
        text=True,
        capture_output=True,
    )

    assert completed.stdout.strip() == "['one', 'two']"


def test_gsettings_helper_uses_centralized_logger_only():
    source = MODULE_PATH.read_text(encoding="utf-8")

    assert "from logging_utils import get_logger, log_call" in source
    assert "import logging" not in source
