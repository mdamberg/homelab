"""Loads pages.yaml and services.yaml from the bind-mounted config folder.

Files are re-read when their modification time changes, so an edit shows on the
next browser refresh without restarting the container.
"""
from pathlib import Path

import yaml

CONFIG_DIR = Path("/srv/config")

_cache = {}


class ConfigError(Exception):
    pass


def _load(name):
    path = CONFIG_DIR / name
    mtime = path.stat().st_mtime
    cached = _cache.get(name)
    if cached and cached[0] == mtime:
        return cached[1]
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        raise ConfigError(f"{name}: {exc}") from exc
    _cache[name] = (mtime, data)
    return data


def pages():
    return _load("pages.yaml").get("pages", [])


def services():
    return _load("services.yaml").get("groups", [])
