"""Resolve the same saved component flags for installation and JSON export."""

import argparse
import json
import sys


FLAG_FIELDS = ("favorite", "on", "startup", "sticky", "uninstall", "workspace")


def flag_value(value):
    """Convert a supported JSON flag into zero or one."""
    if value in (1, True, "1", "true", "on"):
        return 1
    if value in (0, False, None, "", "0", "false", "off"):
        return 0
    raise ValueError(f"unsupported flag value {value!r}; use 0 or 1")


def resolve_components(config_path, defaults):
    """Validate a configuration and normalize its known component fields."""
    config = {}
    if config_path:
        with open(config_path, encoding="utf-8") as stream:
            document = json.load(stream)
        if not isinstance(document, dict):
            raise ValueError("installation config must be an object")
        config = document.get("components", {})
        if not isinstance(config, dict):
            raise ValueError("installation config 'components' must be an object")
        unknown = sorted(set(config) - set(defaults))
        if unknown:
            raise ValueError(f"unknown component id(s): {', '.join(unknown)}")

    components = {}
    for component_id, default_on in defaults.items():
        values = config.get(component_id, {})
        if not isinstance(values, dict):
            raise ValueError(f"installation config for {component_id!r} must be an object")
        normalized = {"config_value": str(values.get("config_value", ""))}
        for field in FLAG_FIELDS:
            fallback = default_on if field == "on" and not config_path else 0
            try:
                normalized[field] = flag_value(values.get(field, fallback))
            except ValueError as error:
                raise ValueError(f"{component_id}.{field}: {error}") from error
        components[component_id] = normalized
    return components


def main():
    """Print selected IDs or resolved JSON without changing desktop state."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("selected", "export"))
    parser.add_argument("repo")
    parser.add_argument("config_path")
    parser.add_argument("defaults", nargs="+")
    args = parser.parse_args()
    try:
        defaults = {name: flag_value(value) for name, value in
                    (entry.rsplit("=", 1) for entry in args.defaults)}
        components = resolve_components(args.config_path, defaults)
    except (OSError, ValueError) as error:
        print(f"ERROR: invalid installation config: {error}", file=sys.stderr)
        return 1

    if args.operation == "selected":
        for component_id, values in components.items():
            if values["on"]:
                print(component_id)
    else:
        print(json.dumps({"components": components, "repo": args.repo,
                          "schema_version": 1, "scope": "standalone"}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
