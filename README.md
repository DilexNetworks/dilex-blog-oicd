# GitHub → AWS OIDC (CDK) quickstart

This is a companion github repo for the article posted here on the Dilex 
Networks website.


**Prereqs**
- AWS CDK installed and bootstrapped for your account/region
- `aws` CLI authenticated (SSO or long-lived creds)
- `gh` CLI authenticated (`gh auth login`)
- `jq` installed

**Configure**
1. Create an example config (or regenerate if needed):
   ```bash
   ./setup_oicd.sh --init
   cp oidc.config.json.example oidc.config.json
   ```
2. Edit `oidc.config.json`:
    - `githubOrg`: your GitHub org/owner (e.g., "your-org")
    - `githubRepo`: your repository name (e.g., "your-repo")
    - `environment`: GitHub Environment to target (e.g., `dev`)
    - Tool paths under `tools` are pre-filled from your system; adjust if needed
   Optional tool overrides:
   ```json
   { "tools": { "gh": "/usr/local/bin/gh", "aws": "/usr/local/bin/aws", "jq": "/opt/homebrew/bin/jq", "cdk": "/opt/homebrew/bin/cdk" } }
   ```

**Tool discovery**
- The script auto-discovers `gh`, `aws`, `jq`, and `cdk` from your `$PATH` and common prefixes (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`).
- If you set an absolute path in `tools`, it will use that exact binary.

**Deploy**
```bash
./setup_oicd.sh            # reads ./oidc.config.json, shows config, asks to confirm
```
This deploys the CDK stack, reads `GitHubOidcRoleArn` from `outputs.json`, and stores it as `ROLE_ARN` in the chosen GitHub Environment.

**Notes**
- The CDK app should output `GitHubOidcRoleArn`.
- The script passes `--context githubOrg=... --context githubRepo=...` to CDK.
- Use `./setup_oicd.sh path/to/config.json` for alternate config locations.
