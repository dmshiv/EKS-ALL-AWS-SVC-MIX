# =============================================================================
# 04-ecr : private container registry
# =============================================================================
#
#   developer -> docker build -> docker push -> ECR repo <- kubelet pull (node IAM role) <- Pod
#
# HOW EKS PULLS: the kubelet (not the Pod) authenticates to ECR with the NODE's IAM role
#   (AmazonEC2ContainerRegistryReadOnly / PullOnly attached in 10-node-groups). Pod Identity/IRSA are NOT
#   involved in image pulls. Layers come from S3 behind ECR, so private subnets need the S3 gateway endpoint.
# FAILURE MODES: ImagePullBackOff = (a) tag does not exist, (b) node role lacks ecr:*, (c) no route to
#   ecr.api/ecr.dkr/S3 (NAT or endpoints), (d) wrong region/account in the image URL.

# WHY:    One repository per service so each can have its own lifecycle, scan results and (later) pull policy.
# IMMUTABLE TAGS: a tag like v1.0.1 can never be overwritten. A deployment that names v1.0.1 is therefore
#         the SAME bytes on every node, every time, forever. With mutable tags (":latest") two nodes can pull
#         different bytes, and a rollback becomes impossible.
# scan_on_push: free "basic" CVE scan (Clair-based) on every push.
# KMS: images encrypted at rest with the data CMK from 16-kms.
# COST: $0.10 per GB-month of storage. Data transfer to nodes in the same region is free via the S3 endpoint.
resource "aws_ecr_repository" "this" {
  for_each = var.services

  name                 = "${var.project}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = data.terraform_remote_state.kms.outputs.data_key_arn
  }

  tags = { Name = "${var.project}-${each.key}" }
}

# WHY:    Without lifecycle rules ECR grows forever (every CI build adds an image) and you pay for it.
# NOTE:   "any" rules must have the LAST (highest) priority number.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent ${var.keep_last_images} tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
