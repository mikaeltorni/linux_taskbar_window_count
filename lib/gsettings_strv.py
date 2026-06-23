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
import os
import sys

from logging_utils import get_logger, log_call

LOGGER = get_logger("gsettings_strv", "gsettings_strv.log")


@log_call(LOGGER)
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
        LOGGER.warning("Unparsable GSettings string-array value; using []")
        return []

    if not isinstance(parsed, list):
        LOGGER.warning("Non-list GSettings string-array value; using []")
        return []

    result = [str(item) for item in parsed]
    return result


@log_call(LOGGER)
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
        LOGGER.info("Appended GSettings string-array value; entry count is %s", len(current))
    else:
        LOGGER.debug("GSettings string-array already contained requested value")
    return current


@log_call(LOGGER)
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
    return "[" + ", ".join(repr(str(item)) for item in values) + "]"


@log_call(LOGGER)
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
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        LOGGER.error("Expected exactly one argument, got %s", len(args))
        print("Usage: gsettings_strv.py <value>", file=sys.stderr)
        return 2

    current = os.environ.get("CURRENT", "")
    LOGGER.info("Ensuring extension UUID is present in enabled-extensions")
    print(format_strv(append_strv(current, args[0])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
