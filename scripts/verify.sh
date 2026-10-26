#!/usr/bin/env bash
# Run every offline check for this repository (no AWS account needed).
# Requires: python3, terraform, kustomize, kubeconform, hadolint, actionlint, checkov
# Usage: ./scripts/verify.sh | tee docs/evidence/offline-validation.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TF="${TF:-terraform}"
failures=0

step() { echo; echo "=== $1"; }
run() { "$@"; local rc=$?; [[ $rc -eq 0 ]] && echo "--> PASS" || { echo "--> FAIL (exit $rc)"; failures=$((failures + 1)); }; }

echo "verify.sh - eks-cicd-pipeline"
echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)"

step "App: lint (ruff), unit tests with coverage gate >= 80% (pytest-cov)"
run bash -c "cd app && ruff check . && python3 -m pytest -q -p no:cacheprovider --disable-warnings --cov=main --cov-report=term-missing --cov-fail-under=80 && rm -f .coverage"

step "Dockerfile lint (hadolint)"
run hadolint app/Dockerfile

step "Kustomize overlays render and validate (K8s 1.33)"
for env in staging production; do
  echo "--- $env"
  run bash -c "kustomize build k8s/overlays/$env | kubeconform -strict -summary -kubernetes-version 1.33.0 -"
done
run kubeconform -strict -summary k8s/namespaces.yaml

step "Pipeline image substitution (what deploy.sh does)"
run bash -c '
  w=$(mktemp -d); cp -r k8s "$w/"; cd "$w/k8s/overlays/staging"
  kustomize edit set image demo-api=123456789012.dkr.ecr.eu-west-1.amazonaws.com/demo-platform/demo-api:abc1234
  kustomize edit add annotation --force "kubernetes.io/change-cause:deploy abc1234 run 1"
  out=$(kustomize build .)
  echo "$out" | grep -E "image: .*demo-api:abc1234" && echo "$out" | grep -m1 "change-cause"'

step "Smoke test against a locally running app (expected version passes, wrong version fails)"
if command -v uvicorn >/dev/null; then
  (cd app && exec env APP_VERSION=abc1234 uvicorn main:app --port 18081 >/dev/null 2>&1) &
  APP_PID=$!
  for _ in $(seq 1 20); do curl -fs localhost:18081/healthz >/dev/null && break; sleep 0.5; done
  run env BASE_URL=http://127.0.0.1:18081 ./scripts/smoke-test.sh local abc1234
  if BASE_URL=http://127.0.0.1:18081 ./scripts/smoke-test.sh local wrong123 >/dev/null; then
    echo "--> FAIL (wrong version was accepted)"; failures=$((failures + 1))
  else
    echo "--> PASS (wrong version correctly rejected)"
  fi
  kill "$APP_PID" 2>/dev/null; wait "$APP_PID" 2>/dev/null || true
else
  echo "uvicorn not installed - skipped"
fi

step "GitHub OIDC Terraform: fmt + validate"
run "$TF" fmt -check infra/github-oidc
if [[ -n "${TF_VALIDATE_CMD:-}" ]]; then
  run $TF_VALIDATE_CMD infra/github-oidc
else
  run bash -c "$TF -chdir=infra/github-oidc init -backend=false -input=false >/dev/null && $TF -chdir=infra/github-oidc validate"
fi

step "Security scan: OIDC Terraform (checkov)"
checkov -d infra/github-oidc --framework terraform --compact --quiet 2>&1 | grep -E 'Passed checks|Check:' || true

step "GitHub Actions workflows (actionlint)"
run actionlint .github/workflows/*.yml

echo
[[ $failures -eq 0 ]] && echo "RESULT: all checks passed" || echo "RESULT: $failures check(s) failed"
exit "$failures"
