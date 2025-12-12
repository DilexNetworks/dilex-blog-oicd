#!/bin/sh

set -e

# Usage:
#   ./setup_oicd.sh [CONFIG_FILE]
#   ./setup_oicd.sh --init            # write oidc.config.json.example to CWD (no deploy)
#   ./setup_oicd.sh --print-readme    # print a README section (no deploy)
#
# If CONFIG_FILE is omitted, defaults to ./oidc.config.json.

# ==========================================
# GitHub → AWS OIDC setup helper (CDK)
# - Reads settings from a JSON config file (default: ./oidc.config.json)
# - Shows the configuration and asks for confirmation before doing anything
# - Resolves CLI tool paths automatically (overridable via config)
# - Deploys CDK app and extracts the Role ARN from the outputs file
# ==========================================

CONFIG_FILE="${1:-./oidc.config.json}"
OUTPUTS_FILE="outputs.json"

# --- helpers ---------------------------------------------------------------
red() { printf "\033[31m%s\033[0m\n" "$1"; }
grn() { printf "\033[32m%s\033[0m\n" "$1"; }
yel() { printf "\033[33m%s\033[0m\n" "$1"; }
err() { red "Error: $1" 1>&2; }

die() { err "$1"; exit 1; }

# Find a CLI path: prefer explicit override, else PATH, else common prefixes
find_cmd() {
  _override="$1"; shift
  _name="$1"
  # 1) explicit override
  if [ -n "$_override" ] && [ -x "$_override" ]; then
    printf "%s" "$_override"
    return 0
  fi
  # 2) PATH lookup
  _p=$(command -v "$_name" 2>/dev/null || true)
  if [ -n "$_p" ] && [ -x "$_p" ]; then
    printf "%s" "$_p"
    return 0
  fi
  # 3) common install prefixes (macOS Homebrew & typical Unix)
  for base in /opt/homebrew/bin /usr/local/bin /usr/bin; do
    if [ -x "$base/$_name" ]; then
      printf "%s" "$base/$_name"
      return 0
    fi
  done
  printf ""  # not found
}

require_cmd() {
  _path="$1"; _name="$2"
  if [ -x "$_path" ]; then
    return 0
  fi
  case "$_name" in
    gh)  die "'gh' not found. Install: brew install gh (macOS) or see https://cli.github.com/manual/installation" ;;
    aws) die "'aws' not found. Install AWS CLI v2: brew install awscli (macOS) or https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" ;;
    jq)  die "'jq' not found. Install: brew install jq (macOS) or your package manager" ;;
    cdk) die "'cdk' not found. Install AWS CDK: npm i -g aws-cdk" ;;
    *)   die "$_name is not found or not executable at '$_path'" ;;
  esac
}

# Ensure a GitHub environment exists (idempotent). Requires repo admin/maintainer rights.
ensure_github_environment() {
  _repo="$1"; _env="$2"
  # Create/update the environment via REST API (PUT is idempotent)
  "$GH" api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
       "repos/${_repo}/environments/${_env}" >/dev/null 2>&1 || true

  # Now ensure AWS_REGION environment variable is present
  _region="${AWS_REGION:-us-east-1}"
  yel "Ensuring environment variable AWS_REGION=$_region is set for '${_env}' ..."
  "$GH" api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "repos/${_repo}/environments/${_env}" \
    -f "deployment_branch_policy[protected_branches]=true" \
    -f "deployment_branch_policy[custom_branch_policies]=false" \
    -f "environment_variables[AWS_REGION]=$_region" >/dev/null 2>&1 || true
}

# Return 0 if the GitHub environment exists
github_env_exists() {
  _repo="$1"; _env="$2"
  "$GH" api -H "Accept: application/vnd.github+json" "repos/${_repo}/environments/${_env}" >/dev/null 2>&1
}

# Print the token scopes (if available) to help debug permission issues
print_token_scopes() {
  yel "Inspecting GitHub token scopes (from response headers)..."
  scopes=$("$GH" api -i rate_limit 2>/dev/null | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}')
  if [ -n "$scopes" ]; then
    grn "Token scopes: $scopes"
  else
    yel "Could not determine token scopes via headers. If using a fine-grained PAT, ensure it has repo access plus Actions: Read/Write and Environments: Read/Write for $REPO."
  fi
}

# Emit the JSON config template (used by --init and missing-config help)
json_template() {
  cat <<CFG
{
  "cdkAppPath": "./cdk.out",
  "environment": "dev",
  "githubOrg": "your-org",
  "githubRepo": "your-repo",
  "tools": {
    "gh": "${GH_EX}",
    "aws": "${AWS_EX}",
    "jq": "${JQ_EX}",
    "cdk": "${CDK_EX}"
  }
}
CFG
}

# Emit a ready-to-paste README section (used by --print-readme)
readme_section() {
  cat <<'MD'
## GitHub → AWS OIDC (CDK) quickstart

**Prereqs**
- AWS CDK installed and bootstrapped for your account/region
- `aws` CLI authenticated (SSO or long-lived creds)
- `gh` CLI authenticated (`gh auth login`)
- `jq` installed

**Configure**
1. Initialize a config template:
   ```bash
   ./setup_oicd.sh --init
   cp oidc.config.json.example oidc.config.json
   ```
2. Edit `oidc.config.json`:
   - `githubOrg`: your GitHub org/owner (e.g., "your-org")
   - `githubRepo`: your repository name (e.g., "your-repo")
   - `environment`: GitHub Environment to target (e.g., `dev`)
   - Tool paths under `tools` are pre-filled from your system; adjust if needed

**Deploy**
```bash
./setup_oicd.sh            # reads ./oidc.config.json, shows config, asks to confirm
```
This will deploy the CDK stack, read `GitHubOidcRoleArn` from `outputs.json`,
and put it into your GitHub environment secrets as `ROLE_ARN`.

**Notes**
- The CDK app should output `GitHubOidcRoleArn`.
- The script passes `--context githubOrg=... --context githubRepo=...` to CDK.
- Use `./setup_oicd.sh path/to/config.json` to point at a different config file.
MD
}

# --- early utility modes ---------------------------------------------------
case "$CONFIG_FILE" in
  --init)
    if [ -e "oidc.config.json.example" ]; then
      yel "oidc.config.json.example already exists; not overwriting."
    else
      yel "Detecting tool paths and writing oidc.config.json.example ..."
      GH_EX="$(find_cmd "" gh)"  || GH_EX=""
      AWS_EX="$(find_cmd "" aws)" || AWS_EX=""
      JQ_EX="$(find_cmd "" jq)"   || JQ_EX=""
      CDK_EX="$(find_cmd "" cdk)" || CDK_EX=""
      json_template > oidc.config.json.example
      grn "Wrote oidc.config.json.example"
    fi
    exit 0
    ;;
  --print-readme)
    readme_section
    exit 0
    ;;
esac

# --- ensure jq exists for initial read ------------------------------------
JQ="$(find_cmd "" jq)"
require_cmd "$JQ" jq

# tool overrides (can be empty)
OVR_GH=$($JQ -r '.tools.gh // ""' "$CONFIG_FILE")
OVR_AWS=$($JQ -r '.tools.aws // ""' "$CONFIG_FILE")
OVR_JQ=$($JQ -r '.tools.jq // ""' "$CONFIG_FILE")
OVR_CDK=$($JQ -r '.tools.cdk // ""' "$CONFIG_FILE")

# Respect JQ override if provided
if [ -n "$OVR_JQ" ]; then
  JQ="$(find_cmd "$OVR_JQ" jq)"
  require_cmd "$JQ" jq
fi

# Resolve actual binaries
GH="$(find_cmd "$OVR_GH" gh)"
AWS="$(find_cmd "$OVR_AWS" aws)"
CDK="$(find_cmd "$OVR_CDK" cdk)"

# --- config load -----------------------------------------------------------
[ -f "$CONFIG_FILE" ] || { json_template | sed '1s/^/\n/'; die "Config file '$CONFIG_FILE' not found. Create it like the example above and rerun."; }

CDK_APP_PATH=$($JQ -r '.cdkAppPath // "./cdk.out"' "$CONFIG_FILE")
ENVIRONMENT=$($JQ -r '.environment // "dev"' "$CONFIG_FILE")

# Read raw values (support alias `gihubRepo` for `githubRepo`)
RAW_REPO=$($JQ -r '.repo // ""' "$CONFIG_FILE")
RAW_ORG=$($JQ -r '.githubOrg // ""' "$CONFIG_FILE")
RAW_REPO_NAME=$($JQ -r '(.githubRepo // .gihubRepo // "")' "$CONFIG_FILE")

# Normalize: allow either `repo` or `githubOrg`+`githubRepo` and derive the other
REPO="$RAW_REPO"
GITHUB_ORG="$RAW_ORG"
GITHUB_REPO="$RAW_REPO_NAME"

# Derive org/repo from `repo` if needed
if [ -n "$REPO" ] && { [ -z "$GITHUB_ORG" ] || [ -z "$GITHUB_REPO" ]; }; then
  GITHUB_ORG="${REPO%%/*}"
  GITHUB_REPO="${REPO#*/}"
fi

# Derive `repo` from org+repo if needed
if [ -z "$REPO" ] && [ -n "$GITHUB_ORG" ] && [ -n "$GITHUB_REPO" ]; then
  REPO="$GITHUB_ORG/$GITHUB_REPO"
fi

# Consistency check if all are set
if [ -n "$REPO" ] && [ -n "$GITHUB_ORG" ] && [ -n "$GITHUB_REPO" ]; then
  _org_from_repo="${REPO%%/*}"
  _name_from_repo="${REPO#*/}"
  if [ "$_org_from_repo" != "$GITHUB_ORG" ] || [ "$_name_from_repo" != "$GITHUB_REPO" ]; then
    die "Config mismatch: 'repo'=$REPO does not match githubOrg/githubRepo=$GITHUB_ORG/$GITHUB_REPO"
  fi
fi

# Validate minimum required values before showing the summary
[ -n "$REPO" ] || die "Missing 'repo' in $CONFIG_FILE"
[ -n "$GITHUB_ORG" ] || die "Missing 'githubOrg' in $CONFIG_FILE"
[ -n "$GITHUB_REPO" ] || die "Missing 'githubRepo' in $CONFIG_FILE"

# Check tools exist
require_cmd "$GH" gh
require_cmd "$AWS" aws
require_cmd "$JQ" jq
require_cmd "$CDK" cdk

# --- show configuration ----------------------------------------------------
cat <<INFO

Configuration (from $CONFIG_FILE):
  CDK app path     : $CDK_APP_PATH
  Repo (owner/name): $REPO
  GitHub env       : $ENVIRONMENT
  GitHub org/repo  : $GITHUB_ORG / $GITHUB_REPO
  Tools:
    gh  : $GH
    aws : $AWS
    jq  : $JQ
    cdk : $CDK
INFO

printf "Proceed with these settings? [y/N]: "
read ans
case "${ans:-N}" in
  y|Y|yes|YES) ;;
  *) die "Aborted by user." ;;
esac

# --- connectivity checks ---------------------------------------------------
yel "Checking GitHub CLI authentication..."
if ! "$GH" auth status >/dev/null 2>&1; then
  die "GitHub CLI is not authenticated. Run: gh auth login"
fi

grn "GitHub CLI is authenticated."

yel "Checking AWS CLI connectivity..."
AWS_IDENTITY=$("$AWS" sts get-caller-identity --output json 2>/dev/null) || die "Failed to connect to AWS. Check credentials and network."
AWS_ACCOUNT_ID=$(printf "%s" "$AWS_IDENTITY" | "$JQ" -r '.Account')
AWS_USER_ARN=$(printf "%s" "$AWS_IDENTITY" | "$JQ" -r '.Arn')
AWS_USER_NAME=$(printf "%s" "$AWS_USER_ARN" | awk -F/ '{print $NF}')

grn "Connected to AWS:\n  Account ID: $AWS_ACCOUNT_ID\n  IAM Role/User Name: $AWS_USER_NAME"

# --- deploy CDK ------------------------------------------------------------
yel "Deploying CDK stack..."
"$CDK" deploy \
  --app "$CDK_APP_PATH" \
  --outputs-file "$OUTPUTS_FILE" \
  --context githubOrg="$GITHUB_ORG" \
  --context githubRepo="$GITHUB_REPO" \
  --require-approval never || die "CDK deployment failed"

grn "CDK deployment complete."

# Extract the (single) stack name key from outputs.json
STACK_NAME=$("$JQ" -r 'keys[0]' "$OUTPUTS_FILE")
[ -n "$STACK_NAME" ] || die "Failed to retrieve the stack name from $OUTPUTS_FILE"

yel "CDK Stack Name: $STACK_NAME"

# The CDK stack exports 'GitHubOidcRoleArn' in the outputs; read it directly
ROLE_ARN=$("$JQ" -r --arg s "$STACK_NAME" '.[$s].GitHubOidcRoleArn' "$OUTPUTS_FILE")
[ "$ROLE_ARN" != "null" ] || ROLE_ARN=""
[ -n "$ROLE_ARN" ] || die "Failed to retrieve the GitHubOidcRoleArn from $OUTPUTS_FILE"

# --- ensure env exists, verify, then save secret ----------------------------
yel "Ensuring GitHub environment '$ENVIRONMENT' exists in '$REPO'..."
ensure_github_environment "$REPO" "$ENVIRONMENT"

if github_env_exists "$REPO" "$ENVIRONMENT"; then
  grn "Environment '$ENVIRONMENT' exists."
else
  err "Could not verify environment '$ENVIRONMENT' in repo '$REPO'."
  print_token_scopes
  err "If using a fine-grained PAT, grant: Actions (Read/Write) and Environments (Read/Write) for this repo."
  die "Cannot proceed without a GitHub environment named '$ENVIRONMENT'."
fi

yel "Uploading ROLE_ARN secret to GitHub environment '$ENVIRONMENT' for repo '$REPO'..."
if "$GH" secret set ROLE_ARN --body "$ROLE_ARN" --repo "$REPO" --env "$ENVIRONMENT"; then
  grn "Successfully saved ROLE_ARN to environment '$ENVIRONMENT' in GitHub Secrets."

  # --- set AWS_REGION as an environment variable (not a secret) ------------
  AWS_REGION_VALUE="${AWS_REGION:-us-east-1}"
  yel "Setting AWS_REGION=$AWS_REGION_VALUE in GitHub environment '$ENVIRONMENT'..."
  if "$GH" variable set AWS_REGION --body "$AWS_REGION_VALUE" --repo "$REPO" --env "$ENVIRONMENT"; then
    grn "Set AWS_REGION in environment '$ENVIRONMENT'."
  else
    yel "Could not set environment-level AWS_REGION; falling back to repository variable."
    if "$GH" variable set AWS_REGION --body "$AWS_REGION_VALUE" --repo "$REPO"; then
      grn "Set AWS_REGION as a repository variable ($AWS_REGION_VALUE)."
    else
      err "Failed to set AWS_REGION as environment or repository variable."
     fi
  fi
else
  err "Failed to upload ROLE_ARN to GitHub environment secrets. Diagnostics:"
  "$GH" api -H "Accept: application/vnd.github+json" "repos/$REPO/environments/$ENVIRONMENT" || true
  print_token_scopes
  die "Failed to upload ROLE_ARN to GitHub Secrets"
fi

grn "All done."
