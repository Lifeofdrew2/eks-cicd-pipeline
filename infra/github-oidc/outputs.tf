output "deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN variable in GitHub."
  value       = aws_iam_role.deploy.arn
}

output "github_variables" {
  description = "Repository variables to create under Settings > Secrets and variables > Actions > Variables."
  value = {
    AWS_DEPLOY_ROLE_ARN = aws_iam_role.deploy.arn
    AWS_REGION          = var.region
    EKS_CLUSTER_NAME    = var.cluster_name
    ECR_REPOSITORY      = var.ecr_repository
  }
}
