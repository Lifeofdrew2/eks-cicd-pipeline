#!/usr/bin/env bash
# Post-deployment smoke test. Reaches the in-cluster Service through
# `kubectl port-forward`, so the cluster does not need to be public.
#
# Usage: scripts/smoke-test.sh <namespace> [expected-version]
# With BASE_URL set, it tests that URL directly instead (used for local runs).
set -euo pipefail

NAMESPACE="${1:?namespace required}"
EXPECTED_VERSION="${2:-}"
PORT="${PORT:-18080}"
PF_PID=""

cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT

if [[ -z "${BASE_URL:-}" ]]; then
  kubectl -n "$NAMESPACE" port-forward svc/demo-api "$PORT:80" >/dev/null 2>&1 &
  PF_PID=$!
  BASE_URL="http://127.0.0.1:$PORT"
fi

# Wait up to 30s for the endpoint to answer.
for _ in $(seq 1 30); do
  curl -fsS "$BASE_URL/healthz" >/dev/null 2>&1 && break
  sleep 1
done

fail=0
check() {
  local name="$1" path="$2" expected_status="$3"
  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$path")"
  if [[ "$status" == "$expected_status" ]]; then
    echo "  PASS  $name ($path -> $status)"
  else
    echo "  FAIL  $name ($path -> $status, expected $expected_status)"
    fail=1
  fi
}

check "liveness"        /healthz          200
check "readiness"       /readyz           200
check "list orders"     /api/orders       200
check "missing order"   /api/orders/999   404
check "metrics"         /metrics          200

if [[ -n "$EXPECTED_VERSION" ]]; then
  running="$(curl -fsS "$BASE_URL/" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
  if [[ "$running" == "$EXPECTED_VERSION" ]]; then
    echo "  PASS  version ($running)"
  else
    echo "  FAIL  version (running $running, expected $EXPECTED_VERSION)"
    fail=1
  fi
fi

exit "$fail"
