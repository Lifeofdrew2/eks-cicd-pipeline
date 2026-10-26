# Setup guide

## Prerequisites

- The EKS cluster and ECR repository from **aws-eks-platform** (`terraform apply` done)
- AWS CLI v2, Terraform ≥ 1.6, kubectl, admin access to the cluster
- This repository pushed to your GitHub account

## Step 1 — Create the namespaces (once, as cluster admin)

```bash
aws eks update-kubeconfig --region eu-west-1 --name demo-platform-dev
kubectl apply -f k8s/namespaces.yaml
```

## Step 2 — Create the GitHub OIDC role

```bash
cd infra/github-oidc
cp terraform.tfvars.example terraform.tfvars   # set github_repository to owner/name
terraform init
terraform apply
terraform output github_variables
```

If `apply` fails with *EntityAlreadyExists* for the OIDC provider, your account
already has one: set `create_oidc_provider = false` and apply again.

## Step 3 — Configure GitHub

In the repository: **Settings → Secrets and variables → Actions → Variables**, add
the four values printed by `terraform output github_variables`:

| Variable | Example |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-actions-demo-api-deploy` |
| `AWS_REGION` | `eu-west-1` |
| `EKS_CLUSTER_NAME` | `demo-platform-dev` |
| `ECR_REPOSITORY` | `demo-platform/demo-api` |

These are variables, not secrets — none of them are sensitive, because access
is controlled by the IAM trust policy, not by a stored credential.

Then **Settings → Environments**:

1. Create `staging` (no protection rules).
2. Create `production` → enable **Required reviewers** and add yourself.
   Optionally restrict **Deployment branches** to `main`.

Finally **Settings → Branches → Add rule** for `main`: require the `ci` checks to pass before merging.

## Step 4 — Run it

1. Open a pull request that changes `app/main.py` → `ci` runs.
2. Merge it → `cd` builds, scans, pushes, deploys to staging.
3. Approve the production deployment in the **Actions** tab.

## Step 5 — Prove the rollback works (good for screenshots)

1. Change `/readyz` in `app/main.py` to always return 503, merge.
2. Staging rollout never becomes ready → `deploy.sh` times out and runs `rollout undo` automatically.
3. Revert the change.

## Teardown

```bash
kubectl delete namespace demo-staging demo-production
terraform -chdir=infra/github-oidc destroy
```

Then destroy the platform from the **aws-eks-platform** repository.
