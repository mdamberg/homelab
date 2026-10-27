"""Finds every widgets/<id>/widget.py and returns {id: module}.

A widget module defines WIDGET = {"id", "interval", "timeout", "stale_after"}
and an async fetch(ctx) that returns a JSON-safe dict.
"""
import importlib
from pathlib import Path

REQUIRED = ("id", "interval", "timeout", "stale_after")


def discover():
    widgets = {}
    for path in sorted(Path(__file__).parent.glob("*/widget.py")):
        module = importlib.import_module(f"app.widgets.{path.parent.name}.widget")
        missing = [key for key in REQUIRED if key not in module.WIDGET]
        if missing:
            raise ValueError(f"{path.parent.name}: WIDGET is missing {', '.join(missing)}")
        widgets[module.WIDGET["id"]] = module
    return widgets
