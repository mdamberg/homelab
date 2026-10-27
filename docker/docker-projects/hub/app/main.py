"""Homelab Hub API and static frontend.

GET /                  index.html
GET /static/...        frontend files (bind-mounted)
GET /api/config        pages.yaml + services.yaml + each widget's poll interval
GET /api/widgets/{id}  cached result for one widget
GET /healthz           container healthcheck
"""
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app import config
from app.poller import Poller
from app.widgets import discover

STATIC_DIR = Path("/srv/static")

poller = Poller(discover())


@asynccontextmanager
async def lifespan(app):
    await poller.start()
    yield
    await poller.stop()


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.middleware("http")
async def revalidate_static(request, call_next):
    # Without this, browsers may reuse a cached app.js or widget after an edit
    response = await call_next(request)
    if request.url.path.startswith("/static/"):
        response.headers["Cache-Control"] = "no-cache"
    return response


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-cache"})


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/api/config")
def get_config():
    try:
        pages = config.pages()
        services = config.services()
    except config.ConfigError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    widgets = {
        wid: {"interval": module.WIDGET["interval"]}
        for wid, module in poller.widgets.items()
    }
    return {"pages": pages, "services": services, "widgets": widgets}


@app.get("/api/widgets/{wid}")
def get_widget(wid: str):
    if wid not in poller.widgets:
        raise HTTPException(status_code=404, detail=f"unknown widget {wid}")
    return poller.get(wid)
