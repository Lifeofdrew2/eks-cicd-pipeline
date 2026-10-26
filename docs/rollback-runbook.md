# Rollback runbook

## Automatic rollback (no action needed)

`scripts/deploy.sh` rolls back on its own when:

- the rollout does not complete within 5 minutes (pods crash or never become ready), or
- the smoke test fails (bad status code, or the wrong version is running).

The workflow job then fails, so production is never reached from a bad staging deploy.

## Manual rollback from GitHub

Use when a problem is found *after* a successful deployment.

1. **Actions → rollback → Run workflow**
2. Choose the environment.
3. Either:
   - leave **image_tag** empty to go back one revision, or
   - enter a known-good 7-character commit SHA to redeploy that exact image.
4. For `production`, approve the job when prompted.

## Manual rollback from a terminal (break-glass)

```bash
aws eks update-kubeconfig --region eu-west-1 --name demo-platform-dev

# What is running and what ran before
kubectl -n demo-production rollout history deployment/demo-api

# Back one revision
kubectl -n demo-production rollout undo deployment/demo-api

# Or to a specific revision number from the history
kubectl -n demo-production rollout undo deployment/demo-api --to-revision=4

kubectl -n demo-production rollout status deployment/demo-api
./scripts/smoke-test.sh demo-production
```

## After any rollback

- Revert or fix the offending commit on `main`; otherwise the next merge redeploys it.
- Record what happened: which SHA, symptoms, how it was detected, time to recover.
