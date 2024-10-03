# Connecting GitHub Actions To AWS with OpenID

This is a companion github repo for the article posted here on the Dilex 
Networks website:



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
