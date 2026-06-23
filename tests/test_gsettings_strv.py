"""Tests for gsettings string-array helpers used by install.sh."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "lib" / "gsettings_strv.py"
LOGGING_PATH = ROOT / "lib" / "logging_utils.py"


def load_module(path: Path = MODULE_PATH, name: str = "taskbar_count_gsettings_strv"):
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    try:
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(path.parent))


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


def test_logging_module_is_idempotent_and_traces_calls(tmp_path, monkeypatch):
    monkeypatch.setenv("TASKBAR_WINDOW_COUNT_LOG_DIR", str(tmp_path))
    logging_utils = load_module(LOGGING_PATH, "taskbar_count_logging_utils")

    logger = logging_utils.get_logger("taskbar-test", "test.log")
    same_logger = logging_utils.get_logger("taskbar-test", "test.log")

    assert logger is same_logger
    assert len(logger.handlers) == 1

    @logging_utils.log_call(logger)
    def combine(value: str, suffix: str = "!") -> str:
        return f"{value}{suffix}"

    assert combine("ok", suffix="?") == "ok?"

    for handler in logger.handlers:
        handler.flush()
    log_text = (tmp_path / "test.log").read_text(encoding="utf-8")
    assert "ENTER test_gsettings_strv.py:test_logging_module_is_idempotent_and_traces_calls" in log_text
    assert "value='ok'" in log_text
    assert "suffix='?'" in log_text
    assert "EXIT test_gsettings_strv.py:test_logging_module_is_idempotent_and_traces_calls" in log_text
    assert "-> 'ok?'" in log_text


def test_gsettings_helper_uses_centralized_logger_only():
    source = MODULE_PATH.read_text(encoding="utf-8")

    assert "from logging_utils import get_logger, log_call" in source
    assert "import logging" not in source
    assert "def _configure_logging" not in source
