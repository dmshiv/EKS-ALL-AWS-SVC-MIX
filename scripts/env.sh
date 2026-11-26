#!/usr/bin/env bash
# Source this file:  source scripts/env.sh
# It resolves the account, region and state bucket ONCE so every other script/command agrees.
# No credentials are stored: authenticate first with `aws sso login --profile <p>` or an equivalent.
export PROJECT="${PROJECT:-cloudcart}"
export ENVIRONMENT="${ENVIRONMENT:-lab}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

if ! ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
  echo "ERROR: AWS credentials are not valid. Run 'aws sso login' or export a profile, then re-source." >&2
  return 1 2>/dev/null || exit 1
fi
export ACCOUNT_ID
export TF_STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}-${AWS_REGION}"

# Picked up automatically by Terraform in every folder.
export TF_VAR_state_bucket="$TF_STATE_BUCKET"
export TF_VAR_project="$PROJECT"
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_region="$AWS_REGION"
export CLUSTER_NAME="${PROJECT}-${ENVIRONMENT}"

echo "account=$ACCOUNT_ID region=$AWS_REGION env=$ENVIRONMENT bucket=$TF_STATE_BUCKET cluster=$CLUSTER_NAME"
