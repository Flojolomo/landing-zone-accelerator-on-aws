# AcceleratorQualifier Implementation Changes Summary

## Date: 2026-10-01

## Overview

Updated AWS LZA external pipeline deployment to require explicit `AcceleratorQualifier` parameter in the Management Account cross-account IAM role, ensuring consistency between the Management Account role and External Pipeline Account installer resources.

---

## Problem Statement

Previously, the Management Account pipeline role was hardcoded as `AWSAccelerator-PipelineRole`, while the External Pipeline Account used a dynamic qualifier-based naming pattern (`{qualifier}-installer-admin-role`). This created:

1. **Naming inconsistency** - Role names didn't follow a unified pattern
2. **Configuration errors** - Easy to deploy with mismatched role names causing "Access Denied" failures
3. **Poor documentation** - Users weren't aware of the critical relationship between parameters

---

## Solution

Introduced mandatory `AcceleratorQualifier` parameter to the Management Account role CloudFormation template, creating consistent naming across both accounts.

---

## Files Modified

### 1. `source/templates/management-account-pipeline-role.yaml`

**Changes:**
- Added `AcceleratorQualifier` parameter with validation pattern
- Changed hardcoded role name from `AWSAccelerator-PipelineRole` to `!Sub '${AcceleratorQualifier}-installer-admin-role'`
- Added comprehensive parameter description explaining consistency requirement

**Before:**
```yaml
Resources:
  PipelineRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: AWSAccelerator-PipelineRole
```

**After:**
```yaml
Parameters:
  AcceleratorQualifier:
    Type: String
    Description: |
      CRITICAL: Must match the AcceleratorQualifier used in the Installer Stack...
    AllowedPattern: '^[a-z]+[a-z0-9-]{1,61}[a-z0-9]+$'
    Default: prod

Resources:
  PipelineRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${AcceleratorQualifier}-installer-admin-role'
```

### 2. `source/deployment-runbook-external-pipeline-s3.md`

**Changes:**

#### Step 1: Deploy Cross-Account Role
- Added detailed explanation of `AcceleratorQualifier` parameter
- Added examples showing qualifier-to-role-name mapping
- Updated CLI deployment commands to include qualifier parameter
- Added warning to save qualifier value for Step 3

**Key Additions:**
```bash
ACCELERATOR_QUALIFIER=prod  # MUST match Step 4 Installer Stack parameter

aws cloudformation create-stack \
  --parameters \
    ParameterKey=AcceleratorQualifier,ParameterValue=$ACCELERATOR_QUALIFIER
```

#### Step 3: Deploy LZA Installer Stack
- Updated parameter file generation to use qualifier variable
- Changed `ManagementAccountRoleName` from hardcoded to dynamic pattern
- Added pre-deployment consistency checks
- Added critical parameters section emphasizing qualifier matching

**Key Changes:**
```bash
# ⚠️ CRITICAL: Get the AcceleratorQualifier from Step 1 (MUST match exactly)
ACCELERATOR_QUALIFIER="prod"

# Role name uses qualifier pattern
"ManagementAccountRoleName": "${ACCELERATOR_QUALIFIER}-installer-admin-role"
```

#### Step 4: Verify Installer Stack Deployment
- Added verification commands to check qualifier was applied correctly
- Added resource naming examples showing qualifier prefix

**Key Additions:**
```bash
# Check that resources were created with your qualifier
aws codepipeline get-pipeline --name "${QUALIFIER}-installer"
aws iam get-role --role-name "${QUALIFIER}-installer-admin-role"
```

#### Troubleshooting Section
- Updated "Access Denied" troubleshooting to include qualifier mismatch
- Added commands to verify qualifier consistency

### 3. `source/templates/lza-installer-params.json`

**Changes:**
- Fixed duplicate `ManagementAccountId` and `ManagementAccountRoleName` entries
- Updated `ManagementAccountRoleName` from `AWSAccelerator-PipelineRole` to `prod-installer-admin-role`
- Added inline comments explaining critical parameters and their relationships

**Before:**
```json
{
  "ParameterKey": "AcceleratorQualifier",
  "ParameterValue": "prod"
},
{
  "ParameterKey": "ManagementAccountRoleName",
  "ParameterValue": "AWSAccelerator-PipelineRole"
}
```

**After:**
```json
{
  "ParameterKey": "AcceleratorQualifier",
  "ParameterValue": "prod",
  "_comment": "CRITICAL: Must match Step 1 Management Account role parameter"
},
{
  "ParameterKey": "ManagementAccountRoleName",
  "ParameterValue": "prod-installer-admin-role",
  "_comment": "CRITICAL: Must match pattern {qualifier}-installer-admin-role"
}
```

---

## Documentation Created

### New Documentation Files

1. **`docs/accelerator-qualifier-constraints.md`**
   - Comprehensive constraint documentation
   - Pattern validation rules and examples
   - SSM parameter naming conventions
   - Resource naming conventions
   - Common issues and troubleshooting
   - Diagnostic commands

2. **`docs/accelerator-qualifier-usage-map.md`**
   - Complete resource usage mapping
   - All 8 resource categories affected by qualifier
   - Multi-deployment isolation examples
   - Troubleshooting commands
   - Resource naming cheat sheet

---

## Naming Pattern

### Pattern: `{qualifier}-installer-admin-role`

| Qualifier | Management Account Role | External Pipeline Role |
|-----------|------------------------|------------------------|
| `prod` | `prod-installer-admin-role` | `prod-installer-admin-role` |
| `lza` | `lza-installer-admin-role` | `lza-installer-admin-role` |
| `dev` | `dev-installer-admin-role` | `dev-installer-admin-role` |

### Affected Resources in External Pipeline Account

All resources use the qualifier as a prefix:
- S3 Buckets: `{qualifier}-installer-*`, `{qualifier}-s3-logs-*`
- CodePipeline: `{qualifier}-installer`
- CodeBuild: `{qualifier}-installer-project`
- IAM Role: `{qualifier}-installer-admin-role`
- KMS Key: `alias/accelerator/{qualifier}/installer/kms/key`
- SSM Parameters: `/accelerator/{qualifier}/*`

---

## Migration Guide

### For Existing Deployments

If you have an existing deployment with the old hardcoded role name:

**Option 1: Leave Existing Deployment (Recommended)**
- Keep using `AWSAccelerator-PipelineRole` for existing deployments
- Use the new pattern only for new deployments

**Option 2: Migrate Existing Deployment**
1. Update Management Account role stack with `AcceleratorQualifier` parameter
2. Update Installer Stack parameters to match new role name
3. Redeploy Installer Stack

**⚠️ Warning:** Changing role names may cause temporary deployment failures during the transition.

### For New Deployments

Follow the updated runbook exactly:
1. Deploy Management Account role with `AcceleratorQualifier` parameter (Step 1)
2. Note the qualifier value
3. Use the same qualifier in Installer Stack parameters (Step 3)
4. Verify qualifier was applied correctly (Step 4)

---

## Validation Rules

### AcceleratorQualifier Pattern

**Allowed Pattern:**
```regex
^[a-z]+[a-z0-9-]{1,61}[a-z0-9]+$
```

**Rules:**
- ✅ Must start with lowercase letter(s)
- ✅ Can contain lowercase letters, numbers, hyphens
- ✅ Must end with lowercase letter or number
- ✅ Length: 3-63 characters
- ❌ No uppercase, underscores, or special characters (except hyphen)
- ❌ Cannot start with number or hyphen
- ❌ Cannot end with hyphen

**Valid Examples:**
- `prod`, `lza`, `dev`, `staging`
- `env-production`, `app-1`, `test-2`

**Invalid Examples:**
- `Prod` (uppercase)
- `env_1` (underscore)
- `1-prod` (starts with number)
- `prod-` (ends with hyphen)
- `pr` (too short)

---

## Testing Checklist

After implementing these changes, verify:

- [ ] Management Account role created with qualifier parameter
- [ ] Role name follows pattern: `{qualifier}-installer-admin-role`
- [ ] Installer Stack deployed successfully
- [ ] CodePipeline created with name: `{qualifier}-installer`
- [ ] S3 buckets created with qualifier prefix
- [ ] SSM parameters created under `/accelerator/{qualifier}/`
- [ ] Cross-account deployment successful
- [ ] Main pipeline deployed to Management Account

---

## Breaking Changes

### ⚠️ BREAKING CHANGE: Management Account Role Template

The Management Account role CloudFormation template now **requires** the `AcceleratorQualifier` parameter.

**Impact:**
- Existing deployments using stack updates will fail if parameter not provided
- New deployments must provide the parameter
- Role name changes from `AWSAccelerator-PipelineRole` to `{qualifier}-installer-admin-role`

**Mitigation:**
- For existing deployments: Continue using old template or update with new parameter
- For new deployments: Follow updated runbook

---

## Benefits

1. **Consistency** - Unified naming pattern across both accounts
2. **Error Prevention** - CloudFormation validates parameter, catching typos early
3. **Documentation** - Clear relationship between parameters across deployment steps
4. **Multi-Environment** - Easier to deploy multiple LZA environments from single External Pipeline Account
5. **Troubleshooting** - Easier to identify which resources belong to which deployment

---

## Related Documentation

- [AcceleratorQualifier Constraints](accelerator-qualifier-constraints.md)
- [AcceleratorQualifier Usage Map](accelerator-qualifier-usage-map.md)
- [LZA Deployment Runbook](../source/deployment-runbook-external-pipeline-s3.md)

---

## Questions and Support

For questions about these changes:
1. Review the deployment runbook Step 1 and Step 3 sections
2. Check the accelerator-qualifier-constraints.md for validation rules
3. Check the accelerator-qualifier-usage-map.md for usage examples
4. Review troubleshooting section in deployment runbook

---

**Document Owner:** Infrastructure Team  
**Last Updated:** 2026-10-01  
**LZA Version:** 1.15.5+
