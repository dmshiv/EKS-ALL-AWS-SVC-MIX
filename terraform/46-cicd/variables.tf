variable "github_repository" {
  description = "GitHub repo allowed to deploy, as OWNER/REPO (e.g. myorg/cloudcart). EMPTY = CI role is not created."
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "Only workflows running on this branch may assume the deploy role."
  type        = string
  default     = "main"
}

variable "create_github_oidc_provider" {
  description = "true = create the GitHub OIDC identity provider. false = it already exists in this account (only ONE per URL is allowed) and is looked up."
  type        = bool
  default     = true
}

variable "deploy_namespace" {
  description = "Namespace the pipeline may modify in the cluster."
  type        = string
  default     = "cloudcart"
}
