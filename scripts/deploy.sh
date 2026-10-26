#!/usr/bin/env bash
# Deploy an image to one environment, verify it, and roll back automatically
# if the rollout or the smoke test fails.
#
# Usage: scripts/deploy.sh <staging|production> <image-uri>
# Requires: kubectl configured for the target cluster, kustomize.
set -euo pipefail

ENVIRONMENT="${1:?environment required (staging|production)}"
IMAGE="${2:?image URI required, e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com/demo-platform/demo-api:abc1234}"
NAMESPACE="demo-${ENVIRONMENT}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/k8s/overlays/$ENVIRONMENT"
EXPECTED_VERSION="${IMAGE##*:}"

[[ -d "$OVERLAY" ]] || { echo "Unknown environment: $ENVIRONMENT" >&2; exit 2; }

# Record the revision currently running so we can report what we roll back to.
PREVIOUS_IMAGE="$(kubectl -n "$NAMESPACE" get deployment demo-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo none)"
echo "==> $ENVIRONMENT: $PREVIOUS_IMAGE -> $IMAGE"

# Render manifests with the new image into a temp copy (the repo stays unchanged).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$ROOT/k8s" "$WORK/"
(
  cd "$WORK/k8s/overlays/$ENVIRONMENT"
  kustomize edit set image "demo-api=$IMAGE"
  # Recorded in `kubectl rollout history`, so each revision maps to a commit and run.
  kustomize edit add annotation --force \
    "kubernetes.io/change-cause:deploy ${EXPECTED_VERSION} run ${GITHUB_RUN_ID:-local}"
)

kustomize build "$WORK/k8s/overlays/$ENVIRONMENT" > "$WORK/rendered.yaml"
kubectl apply -f "$WORK/rendered.yaml"

rollback() {
  echo "!! $1 - rolling back $ENVIRONMENT to the previous revision" >&2
  kubectl -n "$NAMESPACE" rollout undo deployment/demo-api
  kubectl -n "$NAMESPACE" rollout status deployment/demo-api --timeout=5m
  echo "!! Rolled back. Running image: $(kubectl -n "$NAMESPACE" get deployment demo-api \
    -o jsonpath='{.spec.template.spec.containers[0].image}')" >&2
  exit 1
}

echo "==> Waiting for rollout"
kubectl -n "$NAMESPACE" rollout status deployment/demo-api --timeout=5m \
  || rollback "rollout did not complete"

echo "==> Smoke testing"
"$ROOT/scripts/smoke-test.sh" "$NAMESPACE" "$EXPECTED_VERSION" \
  || rollback "smoke test failed"

echo "==> $ENVIRONMENT is healthy on $EXPECTED_VERSION"
kubectl -n "$NAMESPACE" rollout history deployment/demo-api | tail -n 5
