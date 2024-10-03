#!/bin/sh

## USER variables up here
CDK_APP_PATH="./path-to-your-cdk-app"
REPO="your-username/your-repo"
ENVIRONMENT="staging"  # Specify the GitHub environment here

# Define locations for tools that are used in this script
GH_CLI="/opt/homebrew/bin/gh"
AWS_CLI="/usr/local/bin/aws"
JQ="/opt/homebrew/bin/jq"

## Do NOT change anything below this line

# Let's make sure we have everything we need
check_command() {
    if [ ! -x "$1" ]; then
        echo "Error: $1 is not found - please install or check the path"
        exit 1;
    fi
}

check_command "$GH_CLI"
check_command "$AWS_CLI"
check_command "$JQ"

# Make sure that we are connected to GitHub
echo "Checking if GitHub CLI is authenticated..."
$GH_CLI auth status > /dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "GitHub CLI is not authenticated. Please run 'gh auth login'."
  exit 1
else
  echo "GitHub CLI is authenticated."
fi

# Make sure we can connect to AWS
echo "Checking AWS CLI connectivity..."
AWS_IDENTITY=$($AWS_CLI sts get-caller-identity --output json 2> /dev/null)

if [ $? -ne 0 ]; then
  echo "Failed to connect to AWS. Please check your AWS credentials and network connectivity."
  exit 1
fi

# Parse the identity information from the AWS CLI response
AWS_ACCOUNT_ID=$(echo "$AWS_IDENTITY" | $JQ -r '.Account')
AWS_USER_ARN=$(echo "$AWS_IDENTITY" | $JQ -r '.Arn')
AWS_USER_NAME=$(echo "$AWS_USER_ARN" | awk -F/ '{print $NF}')

echo "Connected to AWS:"
echo "Account ID: $AWS_ACCOUNT_ID"
echo "IAM Role/User Name: $AWS_USER_NAME"

echo "All checks passed. Proceeding with the script..."

# Deploy the CDK stack and capture the output
DEPLOY_OUTPUT=$(cdk deploy --app $CDK_APP_PATH --outputs-file outputs.json)

# Check if the deployment succeeded
if [ $? -ne 0 ]; then
  echo "CDK deployment failed"
  exit 1
fi

# Extract the stack name from the CDK deploy output
STACK_NAME=$(jq -r 'keys[0]' outputs.json)

# Validate that the stack name was retrieved
if [ -z "$STACK_NAME" ]; then
  echo "Failed to retrieve the stack name"
  exit 1
fi

echo "CDK Stack Name: $STACK_NAME"

# Get the Role ARN from the CloudFormation output using the stack name
ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArnOutput'].OutputValue" \
  --output text)

# Validate that the Role ARN was retrieved
if [ -z "$ROLE_ARN" ]; then
  echo "Failed to retrieve the Role ARN"
  exit 1
fi

# Upload the Role ARN as a GitHub Secret in the specified environment
gh secret set ROLE_ARN --body "$ROLE_ARN" --repo $REPO --env $ENVIRONMENT

if [ $? -eq 0 ]; then
  echo "Successfully uploaded ROLE_ARN to the $ENVIRONMENT environment in GitHub Secrets"
else
  echo "Failed to upload ROLE_ARN to GitHub Secrets"
fi

