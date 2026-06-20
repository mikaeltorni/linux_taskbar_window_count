"""gsettings_strv.py - helpers for GNOME gsettings string-array values.

Components:
  - parse_strv:  Parse gsettings array output into a list of strings.
  - append_strv: Return a de-duplicated array with a value appended.
  - format_strv: Serialize values back to the gsettings string-array format.
  - main:        CLI entrypoint used by ``install.sh`` to update an array key.

Usage:
    CURRENT="@as ['one']" python3 lib/gsettings_strv.py two
    # -> ['one', 'two']

Logging:
    Every call records structured, timestamped lines to the repository-root
    ``.log/gsettings_strv.log`` file (created on demand) so installer runs are
    auditable. Logs are runtime artifacts and are git-ignored.
"""

from __future__ import annotations

import ast
import logging
import os
import sys
from pathlib import Path

# Repository root is one directory above this module's ``lib/`` folder. All
# repository-generated logs live under ``<repo root>/.log/`` per the project
# logging policy; never the repo root, ``/tmp``, or scattered component dirs.
_REPO_ROOT = Path(__file__).resolve().parents[1]
_LOG_DIR = _REPO_ROOT / ".log"
_LOG_FILE = _LOG_DIR / "gsettings_strv.log"

logger = logging.getLogger("gsettings_strv")


def _configure_logging() -> None:
    """Attach a file handler writing to ``.log/gsettings_strv.log`` once.

    Creates the repository-root ``.log/`` directory if it does not yet exist
    and installs a single timestamped file handler on the module logger. Safe
    to call repeatedly: it is a no-op once a handler is already attached, so
    repeated CLI invocations do not stack duplicate handlers.

    Returns:
        None. Side effect: configures the module-level ``logger``.
    """
    if logger.handlers:
        return
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    handler = logging.FileHandler(_LOG_FILE, encoding="utf-8")
    handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    )
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)


def parse_strv(raw: str | None) -> list[str]:
    """Parse gsettings string-array output into normalized string values.

    Args:
        raw: Raw stdout from ``gsettings get`` for a string-array (``as``) key,
            e.g. ``"@as ['a', 'b']"`` or ``"['a', 'b']"``. ``None`` and empty
            strings are treated as an empty array. Malformed input that does not
            evaluate to a Python list yields an empty list rather than raising.

    Returns:
        list[str]: The array contents, each element coerced to ``str``. Empty
        when ``raw`` is missing, empty, or not a well-formed list literal.
    """
    value = (raw or "").strip()
    if value.startswith("@as "):
        value = value[4:].strip()

    try:
        parsed = ast.literal_eval(value) if value else []
    except (SyntaxError, ValueError):
        logger.debug("parse_strv: unparsable value %r -> []", raw)
        return []

    if not isinstance(parsed, list):
        logger.debug("parse_strv: non-list value %r -> []", raw)
        return []

    result = [str(item) for item in parsed]
    logger.debug("parse_strv: %r -> %s element(s)", raw, len(result))
    return result


def append_strv(raw: str | None, value: str) -> list[str]:
    """Return normalized values with ``value`` appended if it is not present.

    Args:
        raw: Raw ``gsettings get`` output for the existing string-array key;
            parsed via :func:`parse_strv`. Existing entries are preserved and
            de-duplicated in first-seen order.
        value: The string to ensure is present in the resulting array. An empty
            string is never appended.

    Returns:
        list[str]: The de-duplicated existing values, with ``value`` appended at
        the end when it was both non-empty and not already present.
    """
    current = list(dict.fromkeys(parse_strv(raw)))
    if value and value not in current:
        current.append(value)
        logger.info("append_strv: appended %r (now %s entries)", value, len(current))
    else:
        logger.debug("append_strv: %r already present or empty; unchanged", value)
    return current


def format_strv(values: list[str]) -> str:
    """Serialize values for ``gsettings set``.

    Args:
        values: The string-array contents to serialize. Each element is coerced
            to ``str`` and rendered with Python ``repr`` so quoting and escaping
            match the GVariant string-array syntax ``gsettings set`` expects.

    Returns:
        str: A bracketed, comma-separated literal such as ``['a', 'b']`` that can
        be passed verbatim as the value argument to ``gsettings set``.
    """
    formatted = "[" + ", ".join(repr(str(item)) for item in values) + "]"
    logger.debug("format_strv: %s element(s) -> %s", len(values), formatted)
    return formatted


def main(argv: list[str] | None = None) -> int:
    """CLI entrypoint used by ``install.sh``.

    Reads the existing array from the ``CURRENT`` environment variable, appends
    the single positional value (de-duplicated), and prints the serialized array
    to stdout for ``install.sh`` to feed back into ``gsettings set``.

    Args:
        argv: Optional argument vector (excluding the program name). Defaults to
            ``sys.argv[1:]`` when ``None``. Exactly one positional value — the
            entry to ensure is present — is required.

    Returns:
        int: ``0`` on success (serialized array written to stdout); ``2`` when
        the wrong number of arguments is supplied (usage written to stderr).
    """
    _configure_logging()
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        logger.error("main: expected exactly one argument, got %s", len(args))
        print("Usage: gsettings_strv.py <value>", file=sys.stderr)
        return 2

    current = os.environ.get("CURRENT", "")
    logger.info("main: ensuring %r is present in array", args[0])
    print(format_strv(append_strv(current, args[0])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
