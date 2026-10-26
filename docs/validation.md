# Validation

## Offline checks

| Check | Tool | Result |
|---|---|---|
| Unit tests (6) with coverage gate ≥ 80% | pytest + pytest-cov | ✅ 95% coverage |
| Python lint | ruff | ✅ pass |
| Dockerfile lint | hadolint | ✅ pass |
| Workflows (ci, cd, rollback) | actionlint | ✅ pass |
| Staging and production overlays (7 objects each) | kustomize + kubeconform `-strict`, K8s 1.33 | ✅ valid |
| Overlay rendering with a real image + change-cause annotation | `kustomize edit` as used by `deploy.sh` | ✅ image and namespace set correctly |
| Kubernetes security scan of both overlays | Checkov | 180 passed, 4 accepted (image digest / pull policy, see below) |
| OIDC Terraform: fmt + validate | Terraform / AWS provider v6 | ✅ valid |
| OIDC Terraform security scan | Checkov | ✅ 30 passed, 0 failed |
| Smoke test against a running instance | `scripts/smoke-test.sh` | ✅ all checks pass; **fails correctly** when the running version ≠ expected |

Accepted findings: images are referenced by immutable git-SHA tag rather
than digest, and `imagePullPolicy: IfNotPresent` is safe because ECR tags
cannot be overwritten.

## Live pipeline checklist

Capture screenshots of each for `docs/evidence/`:

- [ ] PR run of `ci` with all three jobs green
- [ ] `cd` run: build → staging → **waiting for approval** → production
- [ ] Job summary showing the pushed image URI
- [ ] `kubectl -n demo-production rollout history deployment/demo-api` with change-cause per commit
- [ ] A deliberately broken deploy (see [setup.md](setup.md#step-5--prove-the-rollback-works-good-for-screenshots)) that rolls itself back
- [ ] A PR attempting to assume the AWS role fails (OIDC trust policy rejects it)
