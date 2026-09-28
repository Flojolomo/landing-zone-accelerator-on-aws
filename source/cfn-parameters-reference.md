# LZA Installer Stack - CloudFormation Parameters Reference

## Overview
This document provides a comprehensive reference for all CloudFormation parameters in the Landing Zone Accelerator (LZA) Installer Stack.

---

## Core Parameters

### Source Code Repository Configuration

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **RepositorySource** | String | Location to host the LZA source code | `github` | `github`, `codecommit`, `s3`* | `ACCELERATOR_REPOSITORY_SOURCE` |
| **RepositoryOwner** | String | Owner of the repository containing accelerator code (GitHub only) | `awslabs` | - | `ACCELERATOR_REPOSITORY_OWNER` |
| **RepositoryName** | String | Name of the git repository hosting accelerator code | `landing-zone-accelerator-on-aws` | - | `ACCELERATOR_REPOSITORY_NAME` |
| **RepositoryBranchName** | String | Git branch name for installation | `release/v{version}` | Non-empty (`.+`) | `ACCELERATOR_REPOSITORY_BRANCH_NAME` |

*S3 option only available when `useS3Source` context flag is enabled.

---

### Pipeline Configuration

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **EnableApprovalStage** | String | Add manual approval stage to accelerator pipeline | `Yes` | `Yes`, `No` | `ACCELERATOR_ENABLE_APPROVAL_STAGE` |
| **ApprovalStageNotifyEmailList** | String | Comma-separated email list for approval notifications | - | Valid email list pattern: `^$\|^[^\s@]+@[^\s@]+\.[^\s@]+(\\s*,\\s*[^\s@]+@[^\s@]+\.[^\s@]+)*$` | `APPROVAL_STAGE_NOTIFY_EMAIL_LIST` |

**Validation Rule**: `ApprovalStageNotifyEmailList` is **required** when `EnableApprovalStage = Yes`

---

### Mandatory Accounts Configuration

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **ManagementAccountEmail** | String | Management (primary) account email | - | `[^\s@]+@[^\s@]+\.[^\s@]+` | `MANAGEMENT_ACCOUNT_EMAIL` |
| **LogArchiveAccountEmail** | String | Log archive account email | - | `[^\s@]+@[^\s@]+\.[^\s@]+` | `LOG_ARCHIVE_ACCOUNT_EMAIL` |
| **AuditAccountEmail** | String | Security audit account email | - | `[^\s@]+@[^\s@]+\.[^\s@]+` | `AUDIT_ACCOUNT_EMAIL` |

**Note**: All email addresses must match AWS Organizations account email addresses exactly.

---

### Environment Configuration

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **ControlTowerEnabled** | String | Deploying to Control Tower environment | `Yes` | `Yes`, `No` | `CONTROL_TOWER_ENABLED` |
| **AcceleratorPrefix** | String | Prefix for accelerator deployed resources | `AWSAccelerator` | `[A-Za-z0-9-]+`, max 15 chars | `ACCELERATOR_PREFIX` |
| **EnableDiagnosticsPack** | String | Enable diagnostics pack for pipeline failure diagnosis | `Yes` | `Yes`, `No` | `ENABLE_DIAGNOSTICS_PACK` |

**Important Notes**:
- `AcceleratorPrefix` cannot be changed after initial installation (causes stack failure)
- Non-default prefix cannot start with "aws" or "ssm"
- Trailing dash (-) in non-default value is ignored

---

### Configuration Repository Settings

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **ConfigurationRepositoryLocation** | String | Location to host LZA configuration files | - | `codecommit`, `s3`, `codeconnection` | `CONFIG_REPOSITORY_LOCATION` |
| **UseExistingConfigRepo** | String | Use existing configuration repository | `No` | `Yes`, `No` | `USE_EXISTING_CONFIG_REPO` |
| **ExistingConfigRepositoryName** | String | Name of existing LZA configuration repository | `''` | - | `EXISTING_CONFIG_REPOSITORY_NAME` |
| **ExistingConfigRepositoryBranchName** | String | Branch name of existing configuration repository | `''` | - | `EXISTING_CONFIG_REPOSITORY_BRANCH_NAME` |
| **ExistingConfigRepositoryOwner** | String | Owner/namespace of configuration repository (CodeConnection) | `''` | - | `EXISTING_CONFIG_REPOSITORY_OWNER` |
| **ConfigCodeConnectionArn** | String | AWS CodeConnection ARN for existing repository | `''` | - | `CODECONNECTION_ARN` |

#### Configuration Repository Validation Rules

1. **When `ConfigurationRepositoryLocation = codeconnection`**:
   - `ConfigCodeConnectionArn` must be provided
   - `UseExistingConfigRepo` must be `Yes`
   - `ExistingConfigRepositoryOwner` must be provided

2. **When `UseExistingConfigRepo = Yes`**:
   - `ExistingConfigRepositoryName` must be provided
   - `ExistingConfigRepositoryBranchName` must be provided

3. **When `ConfigurationRepositoryLocation = s3`**:
   - `ExistingConfigRepositoryName` must be empty
   - `ExistingConfigRepositoryBranchName` must be empty
   - `UseExistingConfigRepo` must be `No`

---

## Conditional Parameters

### External Pipeline Account Parameters
**Created when**: `useExternalPipelineAccount = true`

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **AcceleratorQualifier** | String | Names resources in external deployment account (must be unique per pipeline) | - | `^[a-z]+[a-z0-9-]{1,61}[a-z0-9]+$` (cannot be "aws-accelerator") | `ACCELERATOR_QUALIFIER` |
| **ManagementAccountId** | String | Target management account ID | - | - | `MANAGEMENT_ACCOUNT_ID` |
| **ManagementAccountRoleName** | String | Target management account role name | - | - | `MANAGEMENT_ACCOUNT_ROLE_NAME` |

**Purpose**: These parameters enable deploying the LZA pipeline from an external AWS account separate from the management account.

---

### S3 Source Parameters
**Created when**: `useS3Source = true`

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **RepositoryBucketName** | String | Versioned S3 bucket containing accelerator code | - | - | `ACCELERATOR_REPOSITORY_BUCKET_NAME` |
| **RepositoryBucketObject** | String | Full path to accelerator code zip in S3 | `release/v{version}.zip` | - | `ACCELERATOR_REPOSITORY_BUCKET_OBJECT` |
| **RepositoryBucketKmsKeyArn** | String | KMS key for encrypted S3 bucket (optional) | `{s3SourceKmsKeyArn}` | - | `ACCELERATOR_REPOSITORY_BUCKET_KMS_KEY_ARN` |

**Purpose**: Enables using an existing S3 bucket as the source for LZA code instead of GitHub/CodeCommit.

---

### Permission Boundary Parameter
**Created when**: `usePermissionBoundary = true`

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **AcceleratorPermissionBoundary** | String | Permission boundary policy name (management account only) | - | - | `ACCELERATOR_PERMISSION_BOUNDARY` |

**Logical ID Override**: `PermissionBoundaryPolicyName`

---

### Region-by-Region Deployment Parameter
**Created when**: `enableRegionByRegionDeployment = true`

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **RegionByRegionDeployOrder** | String | Comma-separated list of AWS regions for deployment order | - | - | `REGION_BY_REGION_DEPLOYMENT_ORDER` |

**Validation Rule**: When `RegionByRegionDeployOrder` is provided, `EnableApprovalStage` must be `Yes`

---

### Node Version Parameter
**Created when**: `setNodeVersion = true`

| Parameter | Type | Description | Default | Validation | Environment Variable |
|-----------|------|-------------|---------|------------|---------------------|
| **AcceleratorNodeVersion** | String | Node.js version for the solution (e.g., 20) | - | - | `ACCELERATOR_NODE_VERSION` |

**Purpose**: Allows overriding the default Node.js version used in Lambda functions and CodeBuild projects.

---

## Parameter Groups (CloudFormation UI Organization)

### 1. Source Code Repository Configuration
- RepositorySource
- RepositoryOwner
- RepositoryName
- RepositoryBranchName

*When S3 source is enabled, S3 parameters appear here and Git parameters move to a separate group.*

### 2. Pipeline Configuration
- EnableApprovalStage
- ApprovalStageNotifyEmailList

### 3. Mandatory Accounts Configuration
- ManagementAccountEmail
- LogArchiveAccountEmail
- AuditAccountEmail

### 4. Environment Configuration
- ControlTowerEnabled
- AcceleratorPrefix
- EnableDiagnosticsPack

### 5. Config Repository Configuration
- ConfigurationRepositoryLocation
- UseExistingConfigRepo
- ExistingConfigRepositoryName
- ExistingConfigRepositoryBranchName
- ExistingConfigRepositoryOwner
- ConfigCodeConnectionArn

### 6. Target Environment Configuration (External Pipeline Only)
- AcceleratorQualifier
- ManagementAccountId
- ManagementAccountRoleName

### 7. Node Version Configuration (Conditional)
- AcceleratorNodeVersion

### 8. Region By Region Deployment Configuration (Conditional)
- RegionByRegionDeployOrder

### 9. Permission Boundary Configuration (Conditional)
- AcceleratorPermissionBoundary

---

## Resource Naming Impact

The following parameters directly affect resource naming throughout the stack:

| Parameter | Resource Naming Impact |
|-----------|----------------------|
| **AcceleratorPrefix** | Base prefix for all resources (e.g., `AWSAccelerator-Pipeline`, `aws-accelerator-config`) |
| **AcceleratorQualifier** | Replaces prefix when using external pipeline account (e.g., `{qualifier}-pipeline`, `{qualifier}-installer-project`) |

### Standard Deployment Resource Names
```
Pipeline: {AcceleratorPrefix}-Pipeline
Installer Pipeline: {AcceleratorPrefix}-Installer
Installer Project: {AcceleratorPrefix}-InstallerProject
Secure Bucket: {lowerCasePrefix}-installer-{AccountId}-{Region}
Access Logs Bucket: {lowerCasePrefix}-s3-logs-{AccountId}-{Region}
KMS Key Alias: alias/{oneWordPrefix}/installer/kms/key
```

### External Pipeline Account Resource Names
```
Pipeline: {AcceleratorQualifier}-pipeline
Installer Pipeline: {AcceleratorQualifier}-installer
Installer Project: {AcceleratorQualifier}-installer-project
Secure Bucket: {AcceleratorQualifier}-installer-{AccountId}-{Region}
Access Logs Bucket: {AcceleratorQualifier}-s3-logs-{AccountId}-{Region}
KMS Key Alias: alias/{oneWordPrefix}/{AcceleratorQualifier}/installer/kms/key
```

---

## SSM Parameters Created

The installer stack creates several SSM parameters for use by the accelerator pipeline:

| SSM Parameter Name | Value | Purpose |
|-------------------|-------|---------|
| `/{prefix}/{stackName}/stack-id` | Stack ID | Reference to installer stack |
| `/{prefix}/{stackName}/version` | LZA version | Track deployed version |
| `/{prefix}/installer/kms/key-arn` | KMS Key ARN | Installer encryption key |
| `/{prefix}/installer-access-logs-bucket-name` | Bucket name | S3 access logs bucket |

*Note: `{prefix}` is `oneWordPrefix` derived from `AcceleratorPrefix` or `AcceleratorQualifier`*

---

## Pipeline Selection Logic

The installer stack creates three mutually exclusive pipelines based on `RepositorySource`:

| RepositorySource Value | Pipeline Created | Condition |
|----------------------|------------------|-----------|
| `codecommit` | CodeCommitPipeline | `UseCodeCommitCondition` |
| `github` | GitHubPipeline | `UseGitHubCondition` |
| `s3` | S3Pipeline | `UseS3Condition` |

Only the resources for the selected pipeline are created; others are conditionally excluded.

---

## Best Practices

### Email Addresses
- ✅ Use email addresses that match AWS Organizations account emails exactly
- ✅ Ensure approval notification emails are accessible by appropriate personnel
- ❌ Don't use distribution lists that may drop CloudFormation notifications

### AcceleratorPrefix
- ✅ Use the default `AWSAccelerator` unless you have a specific naming requirement
- ✅ Choose a unique prefix if deploying multiple LZA instances in one account
- ❌ Don't change the prefix after initial deployment (causes stack failure)
- ❌ Don't use prefixes starting with "aws" or "ssm"

### External Pipeline Account
- ✅ Use `AcceleratorQualifier` to deploy multiple LZA pipelines in a single external account
- ✅ Choose descriptive qualifiers like "prod", "dev", "app1"
- ❌ Don't use "aws-accelerator" as the qualifier

### Configuration Repository
- ✅ Start with CodeCommit for simplicity
- ✅ Use existing repositories only when you have pre-configured LZA configs
- ✅ Use CodeConnection for GitHub Enterprise or GitLab integrations
- ✅ Use S3 for air-gapped or highly secured environments

### Approval Stage
- ✅ Enable approval stage for production deployments
- ✅ Provide multiple email addresses for approval notifications (comma-separated)
- ⚠️ Disable only for fully automated non-production environments

---

## Troubleshooting

### Common Parameter Validation Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "Approval Stage notification email list is required" | `EnableApprovalStage=Yes` but no emails provided | Provide email addresses in `ApprovalStageNotifyEmailList` |
| "existingConfigRepositoryName parameter must be provided" | `UseExistingConfigRepo=Yes` but repository name missing | Provide the repository name |
| "codeconnectionArn parameter must be provided" | `ConfigurationRepositoryLocation=codeconnection` but ARN missing | Create CodeConnection and provide ARN |
| "Review notification setting is required" | `RegionByRegionDeployOrder` provided but `EnableApprovalStage=No` | Set `EnableApprovalStage=Yes` |
| "Existing configuration repository parameters cannot be provided" | Config repo location is S3 but existing repo params provided | Clear existing repository parameters |

### Parameter Update Restrictions

| Parameter | Can Be Updated? | Notes |
|-----------|----------------|-------|
| **AcceleratorPrefix** | ❌ No | Changing causes stack failure; requires redeployment |
| **AcceleratorQualifier** | ⚠️ Risky | May cause resource naming conflicts |
| **ManagementAccountEmail** | ✅ Yes | Must match AWS Organizations |
| **RepositorySource** | ⚠️ Limited | Switching requires proper pipeline setup |
| **EnableApprovalStage** | ✅ Yes | Can enable/disable as needed |
| **RepositoryBranchName** | ✅ Yes | Update to use different release versions |

---

## Related Documentation

- [LZA Installation Guide](https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/installation.html)
- [LZA Configuration Guide](https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/configuration-files.html)
- [External Pipeline Account Setup](https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/external-pipeline-account.html)

---

*Document generated from: `packages/@aws-accelerator/installer/lib/installer-stack.ts`*  
*Last updated: 2026-09-28*
