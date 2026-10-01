# AcceleratorQualifier Parameter Constraints

## Overview

For **external pipeline deployments** (`useExternalPipelineAccount: true`), the `AcceleratorQualifier` parameter has specific validation rules and constraints enforced at both CloudFormation and runtime (Lambda) levels.

## Purpose

The `AcceleratorQualifier` names resources in the external deployment account and enables multiple LZA pipeline deployments in a single external account. It is distinct from `AcceleratorPrefix`, which names the actual LZA resources in the management account.

## Source Code References

- **CloudFormation Parameter Definition**: `source/packages/@aws-accelerator/installer/lib/installer-stack.ts` (lines 480-488)
- **SSM Parameter Construction**: `source/packages/@aws-accelerator/installer/lib/resource-name-prefixes.ts` (lines 233-235)
- **Runtime Validation Logic**: `source/packages/@aws-accelerator/installer/lib/resource-name-prefixes.ts` (Lambda inline code, lines 44-159)

---

## Validation Rules

### 1. CloudFormation Pattern Validation

**Allowed Pattern (Regular Expression):**
```regex
^[a-z]+[a-z0-9-]{1,61}[a-z0-9]+$
```

**Constraint Description:**
> "Qualifier must include lowercase letters and numbers only and cannot be aws-accelerator"

#### Rules:
- ✅ **Must start** with one or more lowercase letters (`[a-z]+`)
- ✅ **Middle characters** can be lowercase letters, numbers, or hyphens (`[a-z0-9-]{1,61}`)
- ✅ **Must end** with lowercase letter or number (`[a-z0-9]+`)
- ✅ **Total length**: 3-63 characters
- ❌ **Cannot contain**: uppercase letters, underscores, special characters (except hyphen)
- ❌ **Cannot start with**: numbers or hyphens
- ❌ **Cannot end with**: hyphens
- ⚠️ **Discouraged**: "aws-accelerator" or similar values that could be confused with the prefix

#### Valid Examples:
```
✅ "prod"
✅ "dev"
✅ "lza"
✅ "test-1"
✅ "env-production"
✅ "my-app-2"
```

#### Invalid Examples:
```
❌ "Prod"              (uppercase letter)
❌ "PROD"              (all uppercase)
❌ "env_1"             (underscore)
❌ "1-prod"            (starts with number)
❌ "prod-"             (ends with hyphen)
❌ "-prod"             (starts with hyphen)
❌ "my environment"    (space)
❌ "app.1"             (period)
❌ "pr"                (too short - minimum 3 chars)
```

---

### 2. Runtime Validation (Lambda)

#### For CREATE Operations:

The Lambda function validates during stack creation:

1. **Prefix starting with "aws" or "ssm" is blocked** (for `AcceleratorPrefix`, not Qualifier)
   - Exception: "AWSAccelerator" is allowed as the default prefix
   - Located in: `resource-name-prefixes.ts` lines 98-103

2. **Existing deployment detection**
   - Checks if pipeline stack version SSM parameter exists
   - Prevents changing prefix for existing deployments
   - Located in: `resource-name-prefixes.ts` lines 106-120

#### For UPDATE Operations:

The Lambda function validates during stack updates:

1. **SSM Parameter Must Exist**
   - Looks for: `/accelerator/{qualifier}/lza-prefix`
   - If parameter not found → Stack UPDATE fails
   - Error message: `"LZA prefix ssm parameter /accelerator/{qualifier}/lza-prefix not found!!! Recreate the parameter with existing AcceleratorPrefix parameter value to fix the issue"`
   - Located in: `resource-name-prefixes.ts` lines 70-93

2. **Prefix Value Must Match**
   - Reads value from SSM parameter
   - Compares with `AcceleratorPrefix` parameter
   - If mismatch → Stack UPDATE fails
   - Error message: `"LZA does not allow changing AcceleratorPrefix parameter value after initial deploy !!!"`
   - Located in: `resource-name-prefixes.ts` lines 76-81

#### For DELETE Operations:

The Lambda function deletes the SSM parameter:
- Deletes: `/accelerator/{qualifier}/lza-prefix`
- Ignores `ParameterNotFound` errors
- Located in: `resource-name-prefixes.ts` lines 140-156

---

## SSM Parameter Naming Convention

### With AcceleratorQualifier (External Pipeline):
```
/accelerator/{qualifier}/lza-prefix
/accelerator/{qualifier}-pipeline-stack-{accountId}-{region}/version
/accelerator/{qualifier}/AWSAccelerator-InstallerStack/stack-id
/accelerator/{qualifier}/AWSAccelerator-InstallerStack/version
/accelerator/{qualifier}/installer-access-logs-bucket-name
/accelerator/{qualifier}/installer/kms/key-arn
```

**Example with `AcceleratorQualifier: "lza"`:**
```
/accelerator/lza/lza-prefix
/accelerator/lza-pipeline-stack-128315352917-eu-central-1/version
/accelerator/lza/AWSAccelerator-InstallerStack/stack-id
/accelerator/lza/AWSAccelerator-InstallerStack/version
/accelerator/lza/installer-access-logs-bucket-name
/accelerator/lza/installer/kms/key-arn
```

### Without AcceleratorQualifier (Standard Deployment):
```
/accelerator/lza-prefix
/accelerator/AWSAccelerator-PipelineStack-{accountId}-{region}/version
```

---

## Resource Naming Convention

Resources created in the external pipeline account use the qualifier as a prefix:

### S3 Buckets:
```
{qualifier}-installer-{accountId}-{region}
{qualifier}-s3-logs-{accountId}-{region}
```

**Example with `AcceleratorQualifier: "lza"`:**
```
lza-installer-128315352917-eu-central-1
lza-s3-logs-128315352917-eu-central-1
```

### IAM Roles:
```
{qualifier}-installer-admin-role
{qualifier}-installer-codepipeline-role
{qualifier}-installer-codebuild-role
```

### KMS Keys:
```
alias/accelerator/{qualifier}/installer/kms/key
```

### CodePipeline:
```
{qualifier}-installer
```

### CodeBuild Projects:
```
{qualifier}-installer-project
```

---

## Common Issues and Troubleshooting

### Issue 1: "aws-accelerator" Value Blocked

**Symptom:**
CloudFormation accepts the value but documentation discourages it.

**Root Cause:**
The `allowedPattern` regex technically permits "aws-accelerator", but the description explicitly warns against using it.

**Resolution:**
Use a different qualifier that doesn't resemble "aws-accelerator":
- ✅ Use: "lza", "prod", "dev", "main"
- ❌ Avoid: "aws-accelerator", "accelerator", "aws-lza"

### Issue 2: Parameter Not Found During Update

**Symptom:**
```
Received response status [FAILED] from custom resource.
Message: LZA prefix ssm parameter /accelerator/{qualifier}/lza-prefix not found!!!
```

**Root Cause:**
Attempting to UPDATE the stack with a different `AcceleratorQualifier` value, but the SSM parameter for the new qualifier doesn't exist.

**Example Scenario:**
- Stack currently has: `AcceleratorQualifier: "prod"`
- SSM parameter exists: `/accelerator/prod/lza-prefix`
- Update attempts to change to: `AcceleratorQualifier: "lza"`
- Lambda looks for: `/accelerator/lza/lza-prefix` (doesn't exist)
- Update fails

**Resolution Options:**

**Option A: Create Missing SSM Parameter (Workaround)**
```bash
aws ssm put-parameter \
  --name "/accelerator/{new-qualifier}/lza-prefix" \
  --value "AWSAccelerator" \
  --type String \
  --region {region}
```

**Option B: Keep Existing Qualifier (Recommended)**
Revert the parameter file to use the existing qualifier value.

**Option C: Delete and Recreate Stack (Clean Slate)**
```bash
# 1. Delete stack
aws cloudformation delete-stack \
  --stack-name AWSAccelerator-InstallerStack \
  --region {region}

# 2. Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name AWSAccelerator-InstallerStack \
  --region {region}

# 3. Clean up SSM parameters
aws ssm delete-parameters \
  --names \
    "/accelerator/{old-qualifier}/lza-prefix" \
    "/accelerator/{old-qualifier}/AWSAccelerator-InstallerStack/stack-id" \
    "/accelerator/{old-qualifier}/AWSAccelerator-InstallerStack/version" \
  --region {region}

# 4. Recreate with new qualifier
aws cloudformation create-stack \
  --stack-name AWSAccelerator-InstallerStack \
  --template-url "https://{bucket}.s3.{region}.amazonaws.com/templates/AWSAccelerator-InstallerStack-{version}.template.json" \
  --parameters file://lza-installer-params-updated.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region {region}
```

### Issue 3: Invalid Pattern During Deployment

**Symptom:**
```
Parameter validation failed: Parameter value does not match the allowed pattern
```

**Root Cause:**
The qualifier value contains invalid characters or doesn't meet pattern requirements.

**Resolution:**
Review the validation rules above and adjust the qualifier value:
- Remove uppercase letters, underscores, spaces
- Ensure it starts with lowercase letter(s)
- Ensure it ends with lowercase letter or number
- Keep length between 3-63 characters

---

## Best Practices

### 1. Choose Meaningful, Descriptive Names
```
✅ Good: "prod", "dev", "test", "staging"
✅ Good: "lza-prod", "app-dev"
❌ Poor: "x", "temp", "aaa"
```

### 2. Use Environment-Based Naming
```
✅ "prod" - Production environment
✅ "dev" - Development environment
✅ "qa" - QA/Testing environment
✅ "sandbox" - Sandbox/Experimentation
```

### 3. Use Application-Based Naming (Multi-App Deployments)
```
✅ "app1" - First application
✅ "app2" - Second application
✅ "payments" - Payments application
✅ "analytics" - Analytics application
```

### 4. Plan for Multiple Deployments
If you plan to deploy multiple LZA instances in the same external pipeline account:
- Use distinct, non-overlapping qualifiers
- Document which qualifier maps to which management account
- Consider naming convention: `{env}-{app}` (e.g., "prod-app1", "dev-app2")

### 5. Avoid Reserved or Confusing Names
```
❌ Avoid: "aws-accelerator" (conflicts with default prefix)
❌ Avoid: "accelerator" (too similar to prefix)
❌ Avoid: "awsaccelerator" (confusing lowercase version)
❌ Avoid: "lza-prefix" (confusing with SSM parameter names)
```

### 6. Document Your Qualifier
In your deployment documentation, record:
- Qualifier value used
- Target management account ID
- Deployment date
- Purpose/environment

**Example:**
```yaml
# LZA Deployment Configuration
AcceleratorQualifier: "lza"
ManagementAccountId: "565393027581"
Purpose: "Production LZA Deployment"
DeploymentDate: "2026-10-01"
Region: "eu-central-1"
```

---

## Immutability Considerations

### ⚠️ AcceleratorQualifier is Effectively Immutable

While CloudFormation technically allows updating the `AcceleratorQualifier` parameter, doing so requires:
1. The old SSM parameter to exist
2. Manual creation of the new SSM parameter
3. Careful coordination to avoid resource conflicts

**In practice, treat `AcceleratorQualifier` as immutable after initial deployment.**

### Changing the Qualifier

If you must change the qualifier:

1. **Backup Configuration**
   - Export all SSM parameters
   - Document all resource names
   - Save configuration files

2. **Delete Existing Stack**
   - Use CloudFormation console or CLI
   - Clean up retained S3 buckets if desired
   - Delete SSM parameters

3. **Deploy with New Qualifier**
   - Update parameter file with new qualifier
   - Create fresh stack
   - Verify all resources created with new naming

4. **Restore Configuration**
   - Upload configuration files to new config bucket
   - Trigger installer pipeline
   - Verify main pipeline deployment

---

## Testing and Validation

### Pre-Deployment Validation

Before deploying, validate your qualifier value:

```bash
# Test pattern matching with grep (returns 0 if valid)
echo "lza" | grep -E '^[a-z]+[a-z0-9-]{1,61}[a-z0-9]+$' && echo "✅ Valid" || echo "❌ Invalid"

# Check length (should be 3-63 characters)
QUALIFIER="lza"
LENGTH=${#QUALIFIER}
if [ $LENGTH -ge 3 ] && [ $LENGTH -le 63 ]; then
  echo "✅ Length valid: $LENGTH characters"
else
  echo "❌ Length invalid: $LENGTH characters (must be 3-63)"
fi
```

### Post-Deployment Validation

After deployment, verify SSM parameters were created:

```bash
QUALIFIER="lza"
REGION="eu-central-1"

# Check for expected SSM parameters
aws ssm get-parameter \
  --name "/accelerator/${QUALIFIER}/lza-prefix" \
  --region ${REGION} \
  --query 'Parameter.[Name,Value]' \
  --output table

# List all parameters for this qualifier
aws ssm get-parameters-by-path \
  --path "/accelerator/${QUALIFIER}/" \
  --recursive \
  --region ${REGION} \
  --query 'Parameters[].[Name,Value]' \
  --output table
```

---

## Diagnostic Commands

### Check Current Qualifier

```bash
REGION="eu-central-1"

# Get current qualifier from stack parameters
aws cloudformation describe-stacks \
  --stack-name AWSAccelerator-InstallerStack \
  --region ${REGION} \
  --query 'Stacks[0].Parameters[?ParameterKey==`AcceleratorQualifier`].ParameterValue' \
  --output text
```

### List All Qualifiers in Account

```bash
REGION="eu-central-1"

# Find all accelerator SSM parameter paths (indicates deployed qualifiers)
aws ssm describe-parameters \
  --region ${REGION} \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=/accelerator/" \
  --query 'Parameters[].Name' \
  --output json | jq -r '.[]' | sed 's|/accelerator/||' | cut -d'/' -f1 | sort -u
```

### Check Resource Naming

```bash
REGION="eu-central-1"

# List installer pipelines (names include qualifier)
aws codepipeline list-pipelines \
  --region ${REGION} \
  --query 'pipelines[?contains(name, `installer`)].name' \
  --output table

# List installer S3 buckets (names include qualifier)
aws s3api list-buckets \
  --query 'Buckets[?contains(Name, `installer`) || contains(Name, `s3-logs`)].Name' \
  --output table
```

---

## Related Documentation

- [LZA Deployment Runbook](deployment-runbook-external-pipeline-s3.md)
- [CloudFormation Template Parameters](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/parameters-section-structure.html)
- [AWS SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)

---

## Version History

| Version | Date       | Changes                                      |
|---------|------------|----------------------------------------------|
| 1.0     | 2026-10-01 | Initial documentation of qualifier constraints |

---

**Document Owner:** Infrastructure Team  
**Last Updated:** 2026-10-01  
**LZA Version:** 1.15.5+
