import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';

export class OpenIdStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get the GitHub organization and repo from CDK context
    const githubOrg = this.node.tryGetContext('githubOrg') || 'default-org';  // Default to 'default-org'
    const githubRepo = this.node.tryGetContext('githubRepo') || 'default-repo';  // Default to 'default-repo'

    // Create the OIDC provider and IAM role
    const oidcProvider = new iam.OpenIdConnectProvider(this, 'GitHubOidcProvider', {
      url: 'https://token.actions.githubusercontent.com',
      clientIds: ['sts.amazonaws.com'],
    });

    const githubOidcRole = new iam.Role(this, 'GitHubOidcRole', {
      assumedBy: new iam.FederatedPrincipal(
        oidcProvider.openIdConnectProviderArn,
        {
          'StringLike': {
            'token.actions.githubusercontent.com:sub': `repo:${githubOrg}/${githubRepo}:*`
          }
        },
        'sts:AssumeRoleWithWebIdentity'
      ),
      description: 'Role assumed by GitHub Actions using OIDC',
    });

    new cdk.CfnOutput(this, 'GitHubOidcRoleArn', {
      value: githubOidcRole.roleArn,
      description: 'The ARN of the role that GitHub Actions can assume via OIDC',
    });
  }
}
