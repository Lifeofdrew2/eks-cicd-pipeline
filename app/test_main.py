from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_root_reports_service_and_version():
    body = client.get("/").json()
    assert body["service"] == "demo-api"
    assert "version" in body


def test_health_and_readiness():
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").json() == {"status": "ready"}


def test_list_orders():
    body = client.get("/api/orders").json()
    assert body["count"] == len(body["orders"]) > 0


def test_get_order_found_and_missing():
    assert client.get("/api/orders/1").json()["id"] == 1
    assert client.get("/api/orders/999").status_code == 404


def test_simulated_error_and_success():
    assert client.get("/api/simulate/error?rate=1").status_code == 500
    assert client.get("/api/simulate/error?rate=0").status_code == 200


def test_metrics_use_route_templates():
    client.get("/api/orders/2")
    text = client.get("/metrics").text
    assert "http_requests_total" in text
    assert 'route="/api/orders/{order_id}"' in text
    assert 'route="/metrics"' not in text
