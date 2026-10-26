variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "name" {
  description = "Short name used in the IAM role name."
  type        = string
  default     = "demo-api"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy, in owner/name form."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the owner/name form, e.g. octocat/eks-cicd-pipeline."
  }
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster (from the aws-eks-platform repo)."
  type        = string
}

variable "ecr_repository" {
  description = "Name of the existing ECR repository (from the aws-eks-platform repo)."
  type        = string
  default     = "demo-platform/demo-api"
}

variable "namespaces" {
  description = "Kubernetes namespaces the pipeline may deploy into."
  type        = list(string)
  default     = ["demo-staging", "demo-production"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if your AWS account already has one."
  type        = bool
  default     = true
}
