# Connecting GitHub Actions To AWS with OpenID


# Requirements
  + AWS Account and Access Keys
  + AWS CDK CLI installed
  + GitHub Repo

# Steps

1) Install everything, configure access keys, cdk bootstrap your AWS account

mkdir infra
cd infra
cdk init --language typescript --app OpenId
cdk bootstrap (wait for this to finish)

cdk init --language typescript --app OpenId
# edit open-id-stack.ts
cdk synth
cdk deploy --context githubOrg=DilexNetworks --githubRepo=dilex-blog-oicd





in the [GitHub Documentation][^1] and [here][^2]
also [this][^open-id]



[^open-id]: <https://openid.net/developers/how-connect-works/>
"OpenID Connect"

[^1]: <https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect>
"GitHub - Security Hardening with OpenID Connect"

[^2]: <https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services>
"Github - Configuring OpenID Connect in Amazon Web Services"
