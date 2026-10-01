# SCP Region Restriction Quick Reference for LZA

## TL;DR

**When using Control Tower region restrictions with LZA, always ensure CloudFormation is allowed globally.**

---

## The Problem

Region restriction SCPs often block CloudFormation in us-east-1, breaking LZA deployment:

```json
{
  "Effect": "Deny",
  "NotAction": [
    "iam:*",
    "s3:GetBucketLocation",
    "route53:*"
    // ❌ Missing "cloudformation:*"
  ],
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["eu-central-1"]
    }
  }
}
```

**Result:** CDK bootstrap fails with AccessDenied in us-east-1.

---

## The Fix

### Option 1: Add CloudFormation to Global Services (Recommended)

```json
{
  "Effect": "Deny",
  "NotAction": [
    "cloudformation:*",  // ← ADD THIS
    "iam:*",
    "route53:*",
    "cloudfront:*",
    "organizations:*",
    "sts:*",
    "kms:*",
    "s3:GetBucketLocation",
    "s3:GetBucketPolicyStatus",
    "s3:GetAccountPublicAccessBlock",
    "s3:ListAllMyBuckets"
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

### Option 2: Move Infrastructure Accounts to Exempt OU

```
Root
├── Infrastructure OU (no region restrictions)
│   └── External Pipeline Account ← Move here
└── Workloads OU (region restrictions enabled)
```

---

## Essential Global Services for LZA

Add these to `NotAction` in region restriction SCPs:

```json
"NotAction": [
  "cloudformation:*",      // ← CRITICAL for LZA
  "iam:*",                 // ← Required for IAM roles
  "sts:*",                 // ← Required for AssumeRole
  "organizations:*",       // ← Required for AWS Organizations
  "kms:*",                 // ← Required for encryption keys
  "route53:*",             // ← Required for DNS
  "route53domains:*",      // ← Required for domain registration
  "cloudfront:*",          // ← Required for CDN
  "waf:*",                 // ← Required for WAF
  "wafv2:*",               // ← Required for WAFv2
  "globalaccelerator:*",   // ← Required for Global Accelerator
  "shield:*",              // ← Required for Shield
  "pricing:*",             // ← Pricing API (global)
  "support:*",             // ← AWS Support (global)
  "trustedadvisor:*",      // ← Trusted Advisor (global)
  "health:*",              // ← AWS Health (global)
  "account:*",             // ← Account management (global)
  "billing:*",             // ← Billing console (global)
  "ce:*",                  // ← Cost Explorer (global)
  "cur:*",                 // ← Cost & Usage Reports (global)
  "budgets:*",             // ← AWS Budgets (global)
  "aws-portal:*",          // ← AWS Portal access
  
  // S3 global operations
  "s3:GetAccountPublicAccessBlock",
  "s3:PutAccountPublicAccessBlock",
  "s3:GetBucketLocation",
  "s3:GetBucketPolicyStatus",
  "s3:ListAllMyBuckets",
  "s3:CreateMultiRegionAccessPoint",
  "s3:DeleteMultiRegionAccessPoint",
  "s3:DescribeMultiRegionAccessPointOperation",
  "s3:GetMultiRegionAccessPoint",
  "s3:GetMultiRegionAccessPointPolicy",
  "s3:ListMultiRegionAccessPoints",
  "s3:PutMultiRegionAccessPointPolicy",
  
  // CloudTrail lookup (view events globally)
  "cloudtrail:LookupEvents",
  
  // EC2 global operations
  "ec2:DescribeRegions",
  "ec2:DescribeTransitGateways",
  "ec2:DescribeVpnGateways",
  
  // Config global operations
  "config:*",
  
  // SSO operations
  "sso:*"
]
```

---

## Testing Your SCP

### Test 1: Verify CloudFormation Access in us-east-1

```bash
# Should return stacks or "no stacks", NOT AccessDenied
aws cloudformation describe-stacks \
  --region us-east-1

# If you get AccessDenied, CloudFormation is blocked
```

### Test 2: Verify IAM Access (Global)

```bash
# Should work (IAM is global, uses us-east-1 endpoint)
aws iam list-roles --max-items 1

# If this fails, your SCP is too restrictive
```

### Test 3: Test CDK Bootstrap (Dry Run)

```bash
# Try to describe the CDK Toolkit stack
aws cloudformation describe-stacks \
  --stack-name AWSAccelerator-CDKToolkit \
  --region us-east-1

# Should return "Stack not found" or stack details
# NOT AccessDenied
```

---

## Common Mistakes

### ❌ Mistake 1: Blocking All Non-Primary Regions

**Wrong:**
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["eu-central-1"]
    }
  }
}
```

**Why:** Blocks everything in us-east-1, including global services.

---

### ❌ Mistake 2: Forgetting CloudFormation in NotAction

**Wrong:**
```json
{
  "NotAction": [
    "iam:*",
    "route53:*"
    // Missing cloudformation:*
  ]
}
```

**Why:** LZA needs to deploy stacks to us-east-1.

---

### ❌ Mistake 3: Only Exempting AWSControlTowerExecution

**Wrong:**
```json
{
  "Condition": {
    "ArnNotLike": {
      "aws:PrincipalARN": [
        "arn:*:iam::*:role/AWSControlTowerExecution"
      ]
    }
  }
}
```

**Why:** LZA installer role also needs access, not just Control Tower's role.

---

## Best Practice SCP Template

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAccessOutsideAllowedRegions",
      "Effect": "Deny",
      "NotAction": [
        "cloudformation:*",
        "iam:*",
        "sts:*",
        "organizations:*",
        "kms:*",
        "route53:*",
        "route53domains:*",
        "cloudfront:*",
        "waf:*",
        "wafv2:*",
        "shield:*",
        "globalaccelerator:*",
        "pricing:*",
        "support:*",
        "health:*",
        "account:*",
        "billing:*",
        "ce:*",
        "cur:*",
        "budgets:*",
        "aws-portal:*",
        "trustedadvisor:*",
        "config:*",
        "sso:*",
        "cloudtrail:LookupEvents",
        "ec2:DescribeRegions",
        "ec2:DescribeTransitGateways",
        "ec2:DescribeVpnGateways",
        "s3:GetAccountPublicAccessBlock",
        "s3:PutAccountPublicAccessBlock",
        "s3:GetBucketLocation",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": [
            "eu-central-1"  // Your primary region
          ]
        },
        "ArnNotLike": {
          "aws:PrincipalARN": [
            "arn:*:iam::*:role/AWSControlTowerExecution",
            "arn:aws:iam::*:role/*-installer-admin-role"  // LZA installer roles
          ]
        }
      }
    }
  ]
}
```

---

## OU Structure Recommendation

```
Root
├── Security OU (minimal restrictions)
│   ├── Log Archive Account
│   └── Audit Account
│
├── Infrastructure OU (minimal restrictions)
│   ├── External Pipeline Account
│   ├── Network Account
│   └── Shared Services Account
│   └── SCP: Allow global services, allow us-east-1
│
├── Workloads OU (region restrictions enabled)
│   ├── Production Accounts
│   └── SCP: Restrict to eu-central-1, but allow global services
│
└── Sandbox OU (strict restrictions)
    ├── Developer Sandbox Accounts
    └── SCP: Strict region restrictions
```

---

## Checklist Before Deploying LZA

- [ ] us-east-1 is governed by Control Tower
- [ ] `cloudformation:*` is in SCP NotAction list OR
- [ ] External Pipeline Account is in OU without region restrictions
- [ ] IAM, STS, Organizations allowed globally
- [ ] Route53, CloudFront allowed globally (if used)
- [ ] Tested CloudFormation access in us-east-1

---

## Quick Diagnosis

**Symptom:** CDK bootstrap fails with AccessDenied in us-east-1

**Diagnosis Steps:**

1. Check if account is in a region-restricted OU:
   ```bash
   aws organizations list-parents --child-id 128315352917
   ```

2. Check which SCPs are attached:
   ```bash
   aws organizations list-policies-for-target --target-id ou-xxxxx \
     --filter SERVICE_CONTROL_POLICY
   ```

3. Check if CloudFormation is blocked:
   ```bash
   aws cloudformation describe-stacks --region us-east-1
   ```

4. Check SCP content for cloudformation:*:
   ```bash
   aws organizations describe-policy --policy-id p-xxxxx \
     --query 'Policy.Content' --output text | jq '.Statement[].NotAction' | grep cloudformation
   ```

**Fix:** Add `cloudformation:*` to NotAction or move account to Infrastructure OU.

---

## Related Documentation

- [Control Tower us-east-1 Governance Requirement](control-tower-us-east-1-governance-requirement.md)
- [LZA Deployment Runbook](../source/deployment-runbook-external-pipeline-s3.md)

---

**Last Updated:** 2026-10-01  
**Applies to:** LZA 1.15.5+, Control Tower with region restrictions
