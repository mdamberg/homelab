"""Up/down state of every Uptime Kuma monitor, read from Kuma's Prometheus /metrics.

/metrics needs an API key (Kuma > Settings > API Keys), sent as the basic-auth
password with an empty username.
"""
import re

WIDGET = {
    "id": "service_health",
    "interval": 30,
    "timeout": 5,
    "stale_after": 120,
}

KUMA_URL = "http://uptime-kuma:3001/metrics"

# Kuma's monitor_status gauge: 0 down, 1 up, 2 pending, 3 maintenance
STATES = {"0": "down", "1": "up", "2": "pending", "3": "maintenance"}

# Matches lines like: monitor_status{monitor_name="Plex",monitor_type="http",...} 1
STATUS_LINE = re.compile(r'^monitor_status\{(?P<labels>.*)\}\s+(?P<value>\d+)')
NAME_LABEL = re.compile(r'monitor_name="((?:[^"\\]|\\.)*)"')


async def fetch(ctx):
    key = ctx.env.get("KUMA_API_KEY")
    if not key:
        raise RuntimeError("KUMA_API_KEY is not set in hub/.env")

    resp = await ctx.http.get(KUMA_URL, auth=("", key))
    if resp.status_code == 401:
        raise RuntimeError("Kuma rejected the API key (401)")
    resp.raise_for_status()

    monitors = {}
    for line in resp.text.splitlines():
        match = STATUS_LINE.match(line)
        if not match:
            continue
        name = NAME_LABEL.search(match["labels"])
        if name:
            monitors[name.group(1).replace('\\"', '"')] = STATES.get(match["value"], "unknown")

    up = sum(1 for state in monitors.values() if state == "up")
    return {
        "monitors": monitors,
        "up": up,
        "total": len(monitors),
        "not_up": sorted(name for name, state in monitors.items() if state != "up"),
    }
