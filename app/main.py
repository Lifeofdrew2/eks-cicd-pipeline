"""demo-api: a small stateless HTTP service used to demonstrate the platform.

It exposes health endpoints for Kubernetes probes, a synthetic "orders" API,
and Prometheus metrics so the same container can be used across the
platform, CI/CD and observability demonstrations.
"""

import os
import random
import socket
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import PlainTextResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

APP_NAME = os.getenv("APP_NAME", "demo-api")
APP_VERSION = os.getenv("APP_VERSION", "dev")

app = FastAPI(title=APP_NAME, version=APP_VERSION)

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "route", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
INFO = Gauge("app_info", "Application build information", ["version"])
INFO.labels(version=APP_VERSION).set(1)

# Synthetic data only - no real customer or client data is used anywhere.
ORDERS = [
    {"id": i, "item": item, "quantity": qty, "status": status}
    for i, (item, qty, status) in enumerate(
        [
            ("widget", 3, "shipped"),
            ("gadget", 1, "processing"),
            ("sprocket", 12, "delivered"),
            ("gizmo", 5, "processing"),
        ],
        start=1,
    )
]

_ready = {"value": True}


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        # Use the route template (e.g. /api/orders/{order_id}) to keep label cardinality low.
        route_label = getattr(route, "path", "unmatched")
        if route_label != "/metrics":
            REQUESTS.labels(request.method, route_label, str(status)).inc()
            LATENCY.labels(request.method, route_label).observe(time.perf_counter() - start)


@app.get("/")
def root():
    return {"service": APP_NAME, "version": APP_VERSION, "host": socket.gethostname()}


@app.get("/healthz")
def healthz():
    """Liveness: the process is up and serving."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Readiness: the instance can accept traffic."""
    if not _ready["value"]:
        raise HTTPException(status_code=503, detail="not ready")
    return {"status": "ready"}


@app.get("/api/orders")
def list_orders():
    return {"orders": ORDERS, "count": len(ORDERS)}


@app.get("/api/orders/{order_id}")
def get_order(order_id: int):
    for order in ORDERS:
        if order["id"] == order_id:
            return order
    raise HTTPException(status_code=404, detail="order not found")


@app.get("/api/simulate/latency")
def simulate_latency(ms: int = 250):
    """Sleep for `ms` milliseconds (capped at 5s) to exercise latency alerts."""
    time.sleep(min(max(ms, 0), 5000) / 1000)
    return {"slept_ms": ms}


@app.get("/api/simulate/error")
def simulate_error(rate: float = 1.0):
    """Return HTTP 500 with probability `rate` to exercise error-rate alerts."""
    if random.random() < rate:
        raise HTTPException(status_code=500, detail="simulated failure")
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)
