"""Polls each widget's upstream on its own timer and caches the latest result.

The browser only reads this cache, so the upstream load is the same no matter
how many tabs or widgets are open. A failing upstream marks only its own widget
as down and keeps the last good data so the tile can still show it.
"""
import asyncio
import os
import time
from dataclasses import dataclass, field

import httpx


@dataclass
class Context:
    http: httpx.AsyncClient
    env: dict = field(default_factory=lambda: dict(os.environ))


@dataclass
class Entry:
    data: dict | None = None
    updated: float | None = None
    error: str | None = None
    failed_at: float | None = None


class Poller:
    def __init__(self, widgets):
        self.widgets = widgets
        self.cache = {wid: Entry() for wid in widgets}
        self.tasks = []
        self.http = None

    async def start(self):
        self.http = httpx.AsyncClient()
        ctx = Context(http=self.http)
        for wid, module in self.widgets.items():
            self.tasks.append(asyncio.create_task(self._loop(wid, module, ctx)))

    async def stop(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        await self.http.aclose()

    async def _loop(self, wid, module, ctx):
        meta = module.WIDGET
        entry = self.cache[wid]
        while True:
            try:
                entry.data = await asyncio.wait_for(module.fetch(ctx), timeout=meta["timeout"])
                entry.updated = time.time()
                entry.error = None
                entry.failed_at = None
            except asyncio.TimeoutError:
                entry.error = f"timed out after {meta['timeout']}s"
                entry.failed_at = time.time()
            except Exception as exc:
                # The message reaches the browser, so widgets must not put secrets in it
                entry.error = str(exc) or type(exc).__name__
                entry.failed_at = time.time()
            await asyncio.sleep(meta["interval"])

    def get(self, wid):
        meta = self.widgets[wid].WIDGET
        entry = self.cache[wid]
        if entry.error:
            status = "down"
        elif entry.updated is None:
            status = "pending"
        elif time.time() - entry.updated > meta["stale_after"]:
            status = "stale"
        else:
            status = "ok"
        return {
            "id": wid,
            "status": status,
            "updated": entry.updated,
            "error": entry.error,
            "data": entry.data,
        }
