# Control Tower us-east-1 Governance Requirement

## Date: 2026-10-01

## Critical Learning

**us-east-1 MUST be governed by Control Tower for LZA to function properly**, even if your primary deployment region is elsewhere (e.g., eu-central-1).

---

## Background

During LZA external pipeline deployment, we encountered a failure during CDK bootstrap for us-east-1:

```
❌ Environment aws://128315352917/us-east-1 failed bootstrapping: 
AccessDenied: User: arn:aws:sts::128315352917:assumed-role/prod-installer-admin-role/...
is not authorized to perform: cloudformation:DescribeStacks 
with an explicit deny in a service control policy
```

## Root Cause

A Control Tower managed SCP with region restriction guardrail was blocking **all** operations in us-east-1 except a predefined list of global services. **CloudFormation was NOT in that allowed list.**

The SCP statement (GRREGIONDENY) was:

```json
{
  "Sid": "GRREGIONDENY",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["eu-central-1"]
    },
    "ArnNotLike": {
      "aws:PrincipalARN": ["arn:*:iam::*:role/AWSControlTowerExecution"]
    }
  },
  "Effect": "Deny",
  "NotAction": [
    "iam:*",
    "route53:*",
    "cloudfront:*",
    "s3:GetBucketLocation",
    // ... other global services ...
    // ❌ "cloudformation:*" was NOT in this list
  ]
}
```

---

## Why LZA Requires us-east-1

### LZA Architecture

LZA deploys CloudFormation stacks to **two regions** in AWS Organizations:

1. **Primary/Home Region** (e.g., eu-central-1)
   - Main LZA pipeline
   - Regional resources (VPCs, EC2, RDS, etc.)
   - Account-level configurations

2. **Global Region** (us-east-1 for 'aws' partition)
   - IAM resources (roles, policies, identity providers)
   - CloudFront distributions
   - Route53 hosted zones
   - WAF (Classic) resources
   - AWS Organizations integrations
   - Control Tower integrations

### Evidence from Code

From `source/packages/@aws-accelerator/installer/lib/installer-stack.ts` (line 1003):

```typescript
./lib/bash/bootstrap-management.sh \
  ${acceleratorPrefix} \
  ${cdk.Aws.REGION} \        // Your deployment region (eu-central-1)
  ${cdk.Aws.ACCOUNT_ID} \
  ${globalRegion} \          // Always us-east-1 for 'aws' partition
  $FORCE_BOOTSTRAP
```

The bootstrap script is explicitly called with **both** the deployment region and the global region.

### Global Services That Require us-east-1 CloudFormation Stacks

| Service | Why us-east-1 | LZA Use Case |
|---------|---------------|--------------|
| **IAM** | Technically global, but CloudFormation IAM stacks deploy to us-east-1 | Account roles, policies, SAML providers |
| **CloudFront** | Global CDN, API endpoint in us-east-1 | Content delivery, WAF integration |
| **Route53** | Global DNS, operations via us-east-1 | Hosted zones, DNS records |
| **WAF Classic** | Legacy global WAF in us-east-1 | Web application firewall rules |
| **Cost & Usage Reports** | Only available in us-east-1 | Billing and cost tracking |
| **AWS Organizations** | Some features deploy stacks to us-east-1 | Delegated administrators, service integrations |

---

## The Control Tower Governance Requirement

### Why us-east-1 Must Be Governed by Control Tower

1. **Control Tower's Own Architecture**
   - Control Tower itself deploys stacks to us-east-1 for global resources
   - Control Tower's CloudTrail, Config, and logging use us-east-1

2. **IAM and Organizations Integration**
   - IAM roles created by LZA need to integrate with Control Tower's governance model
   - Organizations SCPs and policies are managed globally via us-east-1

3. **Guardrail Enforcement**
   - Control Tower guardrails (SCPs) must allow CloudFormation in us-east-1
   - Blocking us-east-1 breaks the Control Tower + LZA integration

4. **AWS Service Design**
   - Many AWS services treat us-east-1 as the "global" API endpoint
   - CloudFormation uses us-east-1 for global resource types

### What "Governed" Means

**us-east-1 must be:**
- ✅ Included in Control Tower's governed regions
- ✅ Allowed in SCP region restrictions (if any)
- ✅ Accessible for CloudFormation operations
- ✅ Available for IAM, Route53, CloudFront operations

**us-east-1 does NOT need to be:**
- ❌ Your primary deployment region
- ❌ Used for workload resources (EC2, RDS, etc.)
- ❌ The region where your users/applications run

---

## SCP Design Implications

### ❌ INCORRECT: Blocking us-east-1 Entirely

```json
{
  "Effect": "Deny",
  "NotAction": [
    "iam:*",
    "route53:*",
    "cloudfront:*"
    // ❌ Missing "cloudformation:*"
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["eu-central-1"]  // Blocks us-east-1
    }
  }
}
```

**Problem:** This breaks LZA's CDK bootstrap and global service stack deployments.

### ✅ CORRECT: Allow CloudFormation Globally

```json
{
  "Effect": "Deny",
  "NotAction": [
    "cloudformation:*",  // ← REQUIRED for LZA
    "iam:*",
    "route53:*",
    "cloudfront:*",
    "organizations:*",
    "sts:*",
    "kms:*",
    // ... other global services ...
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["eu-central-1"]
    },
    "ArnNotLike": {
      "aws:PrincipalARN": [
        "arn:*:iam::*:role/AWSControlTowerExecution"
      ]
    }
  }
}
```

### ✅ ALTERNATIVE: Exempt Infrastructure Accounts

Move infrastructure/tooling accounts to an OU without region restrictions:

```
Root
├── Security OU (no region restrictions)
├── Infrastructure OU (no region restrictions) ← External Pipeline Account here
├── Workloads OU (region restrictions: eu-central-1 only)
└── Sandbox OU (strict region restrictions)
```

---

## Resolution

### Immediate Fix

For the External Pipeline Account (128315352917), one of these approaches:

1. **Move to Infrastructure OU** (recommended)
   - Create or identify an OU without region restriction guardrails
   - Move the External Pipeline Account to that OU
   - Infrastructure accounts need flexibility to deploy globally

2. **Modify Control Tower Guardrail**
   - Update the region restriction guardrail to include `cloudformation:*` in NotAction
   - Apply to the OU containing the External Pipeline Account

3. **Add Exemption to SCP**
   - Add the installer role ARN to the exemption list in the SCP condition
   - Pattern: `arn:aws:iam::128315352917:role/*-installer-admin-role`

### Best Practice Architecture

```
AWS Organization
├── Root
    ├── Security OU
    │   ├── Log Archive Account (565393027582)
    │   └── Audit Account (565393027583)
    │   └── Guardrails: Minimal (needs global access for logging/auditing)
    │
    ├── Infrastructure OU  ← RECOMMENDED for External Pipeline Account
    │   ├── External Pipeline Account (128315352917)
    │   └── Guardrails: Minimal (needs CloudFormation globally)
    │
    ├── Workloads-Production OU
    │   └── Guardrails: Region restriction to eu-central-1
    │
    └── Sandbox OU
        └── Guardrails: Strict region restriction
```

---

## Control Tower Region Configuration

When setting up Control Tower or updating region governance:

### Control Tower Console → Settings → Region Management

**Governed Regions Should Include:**
- ✅ Your primary region (e.g., eu-central-1)
- ✅ us-east-1 (required for global services)
- ✅ Any additional regions you want governed

**Example Configuration:**
```
Home Region: eu-central-1
Governed Regions:
  - us-east-1 (required for global services)
  - eu-central-1 (primary deployment region)
  - eu-west-1 (optional additional region)
```

### What This Enables

When us-east-1 is governed by Control Tower:
- ✅ Control Tower can deploy its own global resources
- ✅ LZA can deploy IAM, CloudFront, Route53 stacks
- ✅ CDK bootstrap works in both regions
- ✅ AWS Config and CloudTrail work across all regions
- ✅ SCPs are enforced consistently

---

## Testing After Fix

### Verify us-east-1 Access

```bash
# In External Pipeline Account (128315352917)
# Test CloudFormation access in us-east-1
aws cloudformation describe-stacks \
  --region us-east-1 \
  --no-cli-pager

# Should return stack list or "No stacks found", NOT AccessDenied

# Test CDK bootstrap (dry-run)
aws cloudformation describe-stacks \
  --stack-name AWSAccelerator-CDKToolkit \
  --region us-east-1 \
  --no-cli-pager

# If stack doesn't exist yet, this should return 
# "Stack with id AWSAccelerator-CDKToolkit does not exist"
# NOT an AccessDenied error
```

### Verify eu-central-1 Access

```bash
# Test CloudFormation access in primary region
aws cloudformation describe-stacks \
  --region eu-central-1 \
  --no-cli-pager

# Should work normally
```

### Verify SCP Exemptions

```bash
# In Management Account
# Get the SCP details
aws organizations describe-policy \
  --policy-id p-gpo18fs6 \
  --query 'Policy.Content' \
  --output text | jq '.Statement[] | select(.Sid == "GRREGIONDENY")'

# Verify cloudformation:* is in NotAction list
# OR verify your installer role is in the exemption condition
```

---

## Common Misunderstandings

### ❌ Misconception: "We only use eu-central-1, so we can block all other regions"

**Reality:** Even if your workloads only run in eu-central-1, **us-east-1 is required for global AWS services** that underpin your infrastructure.

### ❌ Misconception: "We can add us-east-1 to Control Tower governance later"

**Reality:** us-east-1 should be governed **from the start** of Control Tower setup. Retrofitting is complex and may require recreating Control Tower landing zone.

### ❌ Misconception: "Region restrictions apply only to workload resources"

**Reality:** CloudFormation is subject to region restrictions in SCPs. If CloudFormation is blocked, **infrastructure deployment fails**, not just workload deployment.

### ❌ Misconception: "Control Tower only needs the home region"

**Reality:** Control Tower needs both:
- **Home Region** - Where Control Tower management resources are deployed
- **us-east-1** - Where global service integrations and IAM resources are deployed

---

## Documentation References

### AWS Official Documentation

- [Control Tower Region Governance](https://docs.aws.amazon.com/controltower/latest/userguide/region-how.html)
- [AWS Global Infrastructure](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
- [CloudFormation Stack Sets and Global Resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-concepts.html)

### LZA Documentation

- [LZA Architecture Diagram](https://github.com/awslabs/landing-zone-accelerator-on-aws#architecture)
- [LZA Developer Guide - Global Resources](https://docs.aws.amazon.com/solutions/latest/landing-zone-accelerator-on-aws/global-resources.html)

---

## Key Takeaways

1. **us-east-1 is the global region** for AWS services, regardless of your primary deployment region

2. **Control Tower must govern us-east-1** for proper integration with AWS Organizations, IAM, and global services

3. **SCPs with region restrictions must allow CloudFormation globally** or exempt infrastructure accounts

4. **Infrastructure/tooling accounts should be in OUs with minimal guardrails** to enable cross-region deployment capabilities

5. **LZA requires CloudFormation access to both deployment region AND us-east-1** for proper operation

---

## Related Issues

- **Issue:** CDK bootstrap fails in us-east-1 with AccessDenied
- **Root Cause:** SCP blocks CloudFormation outside primary region
- **Resolution:** Add `cloudformation:*` to SCP NotAction or move account to Infrastructure OU

---

## Version History

| Version | Date       | Changes                                           |
|---------|------------|---------------------------------------------------|
| 1.0     | 2026-10-01 | Initial documentation of us-east-1 governance requirement |

---

**Document Owner:** Infrastructure Team  
**Last Updated:** 2026-10-01  
**LZA Version:** 1.15.5+  
**Related:** [AcceleratorQualifier Constraints](accelerator-qualifier-constraints.md), [Deployment Runbook](../source/deployment-runbook-external-pipeline-s3.md)
