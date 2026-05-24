Bootstrap aws deploy role:

aws cloudformation deploy \
  --stack-name github-actions-sam-deploy-role-bose \
  --template-file bootstrap-deploy-role.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile default \
  --region eu-north-1 \
  --parameter-overrides \
    GitHubOrg=ChiliMonanta \
    GitHubRepo=bose-soundTouch-10-radio-bridge \
    RoleName=GitHubActionsSAMDeployRoleBose \
    ManagedPolicyName=bose-soundtouch