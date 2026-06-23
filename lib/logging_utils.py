#!/usr/bin/env python3
"""Centralized Python logging for linux_taskbar_window_count.

Every Python helper in this repository imports ``get_logger`` and ``log_call``
from here. Logging is best-effort, writes under repository ``.log/`` by
default, and never aborts installer workflows.
"""

from __future__ import annotations

import functools
import inspect
import logging
import os
from pathlib import Path
from typing import Any, Callable, TypeVar

LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
F = TypeVar("F", bound=Callable[..., Any])


def _repo_root() -> Path:
    """Return the repository root relative to this module."""
    return Path(__file__).resolve().parents[1]


def _log_dir() -> Path:
    """Return the configured log directory, defaulting to repository ``.log/``."""
    return Path(os.environ.get("TASKBAR_WINDOW_COUNT_LOG_DIR", _repo_root() / ".log"))


def get_logger(name: str, log_file: str) -> logging.Logger:
    """Return the idempotent project logger writing under ``.log/``.

    Args:
        name: Logger name shown in every record.
        log_file: File name inside the configured log directory.

    Returns:
        A configured logger. If the file sink cannot be created, a null handler
        is attached so logging never raises into callers.
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    if logger.handlers:
        return logger

    try:
        log_dir = _log_dir()
        log_dir.mkdir(parents=True, exist_ok=True)
        handler: logging.Handler = logging.FileHandler(
            log_dir / log_file, encoding="utf-8"
        )
        handler.setFormatter(logging.Formatter(LOG_FORMAT))
    except OSError:
        handler = logging.NullHandler()
    logger.addHandler(handler)
    return logger


def log_call(logger: logging.Logger, level: int = logging.DEBUG) -> Callable[[F], F]:
    """Trace a function by logging bound arguments on entry and return on exit.

    Each record carries ``file:qualname`` for the wrapped function. The wrapper
    does not log timing or intermediate state.

    Args:
        logger: Centralized logger obtained from ``get_logger``.
        level: Logging level for entry and exit records.

    Returns:
        A decorator that wraps the target callable.
    """

    def decorator(func: F) -> F:
        location = f"{Path(func.__code__.co_filename).name}:{func.__qualname__}"
        signature = inspect.signature(func)

        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            bound = signature.bind(*args, **kwargs)
            bound.apply_defaults()
            rendered = ", ".join(
                f"{name}={value!r}" for name, value in bound.arguments.items()
            )
            logger.log(level, "ENTER %s(%s)", location, rendered)
            result = func(*args, **kwargs)
            logger.log(level, "EXIT %s -> %r", location, result)
            return result

        return wrapper  # type: ignore[return-value]

    return decorator
