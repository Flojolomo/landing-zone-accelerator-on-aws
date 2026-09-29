DEPLOYMENT_REGION=eu-central-1
PIPELINE_ACCOUNT_ID=128315352917

aws cloudformation create-stack \
  --stack-name LZA-CrossAccount-PipelineRole \
  --template-body file://templates/management-account-pipeline-role.yaml \
  --parameters ParameterKey=ExternalPipelineAccountId,ParameterValue=$PIPELINE_ACCOUNT_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $DEPLOYMENT_REGION

aws cloudformation wait stack-create-complete --stack-name LZA-CrossAccount-PipelineRole

aws cloudformation describe-stacks \
  --stack-name LZA-CrossAccount-PipelineRole \
  --query 'Stacks[0].Outputs' \
  --region $DEPLOYMENT_REGION