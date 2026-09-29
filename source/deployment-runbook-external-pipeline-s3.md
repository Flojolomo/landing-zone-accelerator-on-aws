# LZA Deployment Runbook - External Pipeline with S3 Configuration

## Prerequisites

### AWS Accounts Required
- **External Pipeline Account** - Hosts the LZA CodePipeline infrastructure
- **Management Account** - Target AWS Organizations management account
- **Log Archive Account** - Must exist with email address
- **Audit Account** - Must exist with email address

### Pre-Deployment Requirements

1. **AWS Accounts**
   - External Pipeline Account (with CloudFormation deployment permissions)
   - Management Account (AWS Organizations management account)
   - Log Archive Account (existing with registered email)
   - Audit Account (existing with registered email)

2. **Account Information**
   - Management Account ID
   - External Pipeline Account ID
   - All three email addresses (must match AWS Organizations exactly)

3. **Development Tools (if building from source)**
   - Node.js 18.x or 20.x
   - Yarn 1.x (Classic) - **Required for LZA builds**
     ```bash
     # Install Yarn 1 globally
     npm install -g yarn@1
     
     # Verify Yarn version (should be 1.x)
     yarn --version
     ```

4. **LZA Source Code**
   - Download or build LZA source code zip (see "Preparing LZA Source Code" section below)
   - Prepared for upload to S3 in Step 2

5. **Initial Configuration Files**
   - Download from https://github.com/aws/lza-universal-configuration
   - Or use minimal templates from this runbook (see "Configuration File Templates" section)
   - Must be customized with your account IDs and email addresses
   - Ready for upload to S3 in Step 2

---

## Preparing LZA Source Code

### Option 1: Download Pre-Built Release (Recommended)

Download the official release from GitHub - **dependencies NOT included**, CodeBuild will install them.

```bash
# Set your desired version
LZA_VERSION="v1.15.5"

# Download release source code
wget https://github.com/awslabs/landing-zone-accelerator-on-aws/archive/refs/tags/${LZA_VERSION}.zip \
  -O landing-zone-accelerator-on-aws-${LZA_VERSION}.zip

# Verify download
unzip -l landing-zone-accelerator-on-aws-${LZA_VERSION}.zip | head -20
```

**Expected structure inside zip:**
```
landing-zone-accelerator-on-aws-1.15.5/
├── source/
│   ├── packages/
│   │   ├── @aws-accelerator/
│   │   ├── @aws-cdk-extensions/
│   ├── package.json
│   ├── yarn.lock
├── reference/
├── .gitignore
└── README.md
```

### Option 2: Build from Source

If you need to customize LZA before deployment or want to deploy in a separate account.

**Prerequisites:**
- Node.js 18.x or 20.x
- Yarn 1.x (Classic) - **NOT Yarn 2+**

```bash
# Verify prerequisites
node --version    # Should show v18.x or v20.x
yarn --version    # Should show 1.x (e.g., 1.22.19)

# If Yarn not installed or wrong version
npm install -g yarn@1

# Set version
LZA_VERSION="v1.15.5"

# Clone repository into a working directory
git clone https://github.com/awslabs/landing-zone-accelerator-on-aws.git
cd landing-zone-accelerator-on-aws

# Checkout specific version
git checkout ${LZA_VERSION}

# Build (this installs dependencies and compiles TypeScript)
cd source
yarn install
yarn build

# Go back to repo root
cd ..

# Create deployment zip OUTSIDE the repo directory
# The zip will be created in the parent directory (where you cloned from)
zip -r ../lza-custom-${LZA_VERSION}.zip . \
  -x "*.git*" \
  -x "*node_modules*" \
  -x "*.terraform*" \
  -x "*dist/*" \
  -x "*cdk.out/*"

# Verify the zip was created in parent directory
ls -lh ../lza-custom-${LZA_VERSION}.zip
```

### What Goes in the Zip?

**✅ Include:**
- Source code (`source/` directory with all TypeScript/JavaScript files)
- `package.json` and `yarn.lock` (dependency manifests)
- `reference/` directory (sample configurations and documentation)
- Root-level configuration files (`.gitignore`, `README.md`, etc.)

**❌ Exclude:**
- `node_modules/` - Dependencies are installed by CodeBuild using `yarn install`
- `.git/` - Git history not needed
- `dist/`, `cdk.out/` - Build artifacts regenerated during deployment
- `.terraform/` - Terraform state (if present)

### Why Dependencies Are NOT Included

The LZA installer pipeline CodeBuild project:
1. **Downloads** the zip from S3
2. **Extracts** it to the build environment
3. **Runs** `yarn install` to download dependencies based on `package.json`
4. **Builds** TypeScript to JavaScript
5. **Synthesizes** CDK to CloudFormation
6. **Deploys** the main pipeline

Including `node_modules/` would:
- ❌ Make zip unnecessarily large (100s of MB vs few MB)
- ❌ Risk architecture mismatches (local machine vs CodeBuild Linux x64)
- ❌ Include dev dependencies not needed for deployment
- ❌ Violate LZA's expected build process

### Verify Zip Structure

```bash
# For downloaded zip
unzip -l landing-zone-accelerator-on-aws-${LZA_VERSION}.zip | grep -E "(package.json|source/)"
ls -lh landing-zone-accelerator-on-aws-${LZA_VERSION}.zip

# For custom-built zip
unzip -l lza-custom-${LZA_VERSION}.zip | grep -E "(package.json|source/)"
ls -lh lza-custom-${LZA_VERSION}.zip
```

**Expected size:** 2-8 MB (source code only)  
**Too large (>50 MB):** Likely includes `node_modules/` - recreate zip without them

**Directory Structure Summary:**
```
your-working-directory/
├── landing-zone-accelerator-on-aws/    # Git repo (DO NOT zip this directory itself)
│   ├── source/                         # Build happens here
│   ├── .git/                          # Excluded from zip
│   └── node_modules/                   # Excluded from zip
└── lza-custom-${LZA_VERSION}.zip      # Zip created here (contains CONTENTS of repo)
```

The zip is created **outside** the repo directory but **contains** the repo's contents.

**Note:** The cross-account role and S3 buckets are created during deployment steps, not prerequisites.

---

## Deployment Steps

### Step 1: Deploy Cross-Account Role in Management Account

Deploy the cross-account IAM role in the **Management Account** that allows the external pipeline to deploy.

**Template File:** `templates/management-account-pipeline-role.yaml`

**Parameters Required:**
- `ExternalPipelineAccountId`: Your External Pipeline Account ID (12 digits)

**⚠️ Security Note:** This template uses `AdministratorAccess` for simplicity. For production, consider scoping permissions to specific LZA operations (see Security Considerations section).

**Deployment via AWS CLI:**

```bash
DEPLOYMENT_REGION = us-east-1
PIPELINE_ACCOUNT_ID = 123456789012

aws cloudformation create-stack \
  --stack-name LZA-CrossAccount-PipelineRole \
  --template-body file://templates/management-account-pipeline-role.yaml \
  --parameters ParameterKey=ExternalPipelineAccountId,ParameterValue=$PIPELINE_ACCOUNT_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $DEPLOYMENT_REGION

aws cloudformation wait stack-create-complete \
   --stack-name LZA-CrossAccount-PipelineRole \
   --region $DEPLOYMENT_REGION

# Get outputs and save to variables
PIPELINE_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name LZA-CrossAccount-PipelineRole \
  --query 'Stacks[0].Outputs[?OutputKey==`PipelineRoleArn`].OutputValue' \
  --output text \
  --region $DEPLOYMENT_REGION)

PIPELINE_ROLE_NAME=$(aws cloudformation describe-stacks \
  --stack-name LZA-CrossAccount-PipelineRole \
  --query 'Stacks[0].Outputs[?OutputKey==`PipelineRoleName`].OutputValue' \
  --output text \
  --region $DEPLOYMENT_REGION)

# Display outputs
echo "Pipeline Role ARN: ${PIPELINE_ROLE_ARN}"
echo "Pipeline Role Name: ${PIPELINE_ROLE_NAME}"
```

**Deployment via Console:**
1. Navigate to CloudFormation in Management Account
2. Create Stack → Upload template file: `templates/management-account-pipeline-role.yaml`
3. Stack name: `LZA-CrossAccount-PipelineRole`
4. Enter parameter: `ExternalPipelineAccountId`
5. Acknowledge IAM capabilities
6. Create stack

---

### Step 2: Deploy S3 Buckets in External Pipeline Account

Deploy S3 buckets in the **External Pipeline Account** for LZA source code and configuration files.

**Template File:** `templates/lza-s3-buckets.yaml`

**Parameters Required:**
- `BucketBaseName`: Base name for all buckets (e.g., `lza-prod`)
- `EnableKMSEncryption`: `Yes` (recommended) or `No`

**Bucket Naming Convention:**
Uses AWS account-regional namespaces with format: `{basename}-{purpose}-{accountid}-{region}-an`

**Example bucket names:**
- Source: `lza-prod-source-123456789012-us-east-1-an`
- Config: `lza-prod-config-123456789012-us-east-1-an`
- Logs: `lza-prod-logs-123456789012-us-east-1-an`

**Resources Created:**
- Source code bucket (with versioning and KMS encryption)
- Configuration bucket (with versioning and KMS encryption)
- Access logs bucket (for audit trail)
- KMS key and alias (if encryption enabled)

**Deployment via AWS CLI:**

```bash
# Set variables
DEPLOYMENT_REGION="us-east-1"
BUCKET_BASE_NAME="lza-prod"

# Deploy stack
aws cloudformation create-stack \
  --stack-name LZA-S3-Buckets \
  --template-body file://templates/lza-s3-buckets.yaml \
  --parameters \
    ParameterKey=BucketBaseName,ParameterValue=${BUCKET_BASE_NAME} \
    ParameterKey=EnableKMSEncryption,ParameterValue=Yes \
  --region ${DEPLOYMENT_REGION}

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name LZA-S3-Buckets \
  --region ${DEPLOYMENT_REGION}

# Get outputs (save KMS Key ARN for Step 3)
aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs' \
  --region ${DEPLOYMENT_REGION}

# Save outputs to variables for later use
KMS_KEY_ARN=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`KMSKeyArn`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})

# Get actual bucket names (with --region--x-s3 suffix)
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})

CONFIG_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigBucketName`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})
```

**Deployment via Console:**
1. Navigate to CloudFormation in External Pipeline Account
2. Create Stack → Upload template file: `templates/lza-s3-buckets.yaml`
3. Stack name: `LZA-S3-Buckets`
4. Enter parameters:
   - `BucketBaseName`: e.g., `lza-prod`
   - `EnableKMSEncryption`: `Yes`
5. Create stack
6. **Save the KMS Key ARN from Outputs** (needed for Step 3)

**Post-Deployment - Upload Files:**

```bash
# Set LZA version
LZA_VERSION="v1.15.5"

# Set source zip filename based on how you prepared it:
# Option 1: Downloaded from GitHub
LZA_SOURCE_ZIP="landing-zone-accelerator-on-aws-${LZA_VERSION}.zip"
# Option 2: Built from source
# LZA_SOURCE_ZIP="lza-custom-${LZA_VERSION}.zip"

# Upload LZA source code to S3
# Target path format: release/{version}.zip
aws s3 cp ${LZA_SOURCE_ZIP} \
  s3://${SOURCE_BUCKET}/release/${LZA_VERSION}.zip

# Verify source code upload
aws s3 ls s3://${SOURCE_BUCKET}/release/

# Upload configuration files
# LZA sample configs are now in a separate repository
# These MUST be customized for your environment before uploading

# Option 1: Download sample configurations from AWS
# Clone the LZA Universal Configuration repository
git clone https://github.com/aws/lza-universal-configuration.git

# Copy the base configuration (simplest starting point)
cp -r lza-universal-configuration/modules/base/default/ ./lza-config/

# OR choose a different module based on your needs:
# - modules/base/default/              # Standard AWS Organizations setup
# - modules/workloads/network-hub/     # Network hub architecture
# - modules/compliance/nist-800-53/    # NIST compliance baseline
# See repository README for all available modules

# Option 2: Use minimal config templates from this runbook
# See "Configuration File Templates" section below

# Customize the configs with YOUR values:
# - Account IDs and email addresses (MUST match AWS Organizations)
# - Region preferences
# - Organizational structure
# - Security baselines
# Edit files in ./lza-config/ before uploading

# CRITICAL: Validate configuration before uploading
# See "Validating Configuration Files" section for detailed instructions

# Quick validation: Check YAML syntax
cd lza-config/
for file in *.yaml; do
  python -c "import yaml; yaml.safe_load(open('$file'))" && echo "✓ $file" || echo "✗ $file has syntax errors"
done

# Full validation: Use LZA config validator (recommended - see validation section)
# Requires LZA source code to be built first

# If validation passes, proceed with upload
cd ..
aws s3 sync ./lza-config/ s3://${CONFIG_BUCKET}/

# Verify config upload
aws s3 ls s3://${CONFIG_BUCKET}/
```

**⚠️ Configuration Files Are NOT Optional:**

LZA **requires** these configuration files to deploy:
- `global-config.yaml` - Regions, logging, control tower settings
- `accounts-config.yaml` - Account definitions with YOUR email addresses
- `organization-config.yaml` - OU structure
- `security-config.yaml` - Security controls
- `network-config.yaml` - VPC and networking setup

**Why Customize?**
- Sample configs contain **placeholder values**
- You must provide **actual account IDs and email addresses**
- Default security settings may not meet your requirements
- Network CIDR ranges must not conflict with existing infrastructure

**Two Options:**
1. **Use AWS Universal Configuration** - Clone from https://github.com/aws/lza-universal-configuration
   - Production-ready reference architectures
   - Multiple patterns (Standard, GovCloud, Multi-Region, etc.)
   - Comprehensive security baselines
2. **Use minimal templates** - Provided in this runbook's "Configuration File Templates" section
   - Simplest starting point
   - Expand as needed

**Resource:** LZA Universal Configuration Repository
- URL: https://github.com/aws/lza-universal-configuration
- Contains multiple reference configurations
- Includes industry compliance baselines (NIST, PCI-DSS, etc.)

---

## Validating Configuration Files

**Why Validate?**
- Catch syntax errors before deployment
- Verify required fields are present
- Check cross-references between config files
- Validate account IDs and email formats
- Prevent pipeline failures due to config issues

**Validation Methods:**

### Method 1: Using LZA Source Code Validator (Recommended)

The config validator is built into the LZA source code:

```bash
# Prerequisites: LZA source code and Node.js/Yarn installed

# If you haven't already, download and set up LZA source
LZA_VERSION="v1.15.5"
wget https://github.com/awslabs/landing-zone-accelerator-on-aws/archive/refs/tags/${LZA_VERSION}.zip
unzip ${LZA_VERSION}.zip
cd landing-zone-accelerator-on-aws-*

# Install dependencies
cd source
yarn install
yarn build

# Run config validator
cd packages/@aws-accelerator/accelerator
yarn run ts-node --transpile-only lib/config-validator.ts \
  --config-dir /absolute/path/to/lza-config

# OR from the source root directory:
cd ../../../..  # Back to repo root
node source/packages/@aws-accelerator/accelerator/lib/config-validator.js \
  /absolute/path/to/lza-config
```

**Note:** You must provide an **absolute path** to your config directory.

### Method 2: Manual YAML Validation

Basic syntax checking before running the full validator:

```bash
# Install yamllint (optional but helpful)
pip install yamllint

# Check YAML syntax
cd lza-config
for file in *.yaml; do
  echo "Validating $file..."
  yamllint "$file" || echo "⚠️  Syntax error in $file"
done
```

### Method 3: Validate During Deployment

The LZA pipeline automatically validates configurations during the first stage, but catching errors early saves deployment time (20-30 minutes per failed attempt).

**Common Validation Errors:**

| Error | Cause | Fix |
|-------|-------|-----|
| "Invalid email format" | Email doesn't match AWS pattern | Use exact email from AWS Organizations |
| "Account ID must be 12 digits" | Incorrect account ID format | Verify account IDs are exactly 12 digits |
| "Region not enabled" | Region not in enabled regions list | Add region to `global-config.yaml` |
| "Duplicate organizational unit" | OU name appears multiple times | Ensure unique OU names |
| "Invalid CIDR range" | Overlapping or malformed CIDR | Check VPC CIDR blocks don't overlap |
| "Missing required field" | Required config parameter omitted | Check schema documentation |

**Best Practices:**
- ✅ Always validate after editing configs
- ✅ Validate before each upload to S3
- ✅ Keep validation output for troubleshooting
- ✅ Test configs in a non-production environment first

---

### Step 3: Deploy LZA Installer Stack in External Pipeline Account

Deploy the official LZA Installer Stack in the **External Pipeline Account**.

**Template Source:** Download from AWS Solutions Library or GitHub:
- https://github.com/awslabs/landing-zone-accelerator-on-aws/releases

**Parameters Template:** `templates/lza-installer-params.json` (customize before use)

**⚠️ CRITICAL PARAMETER NOTES:**

1. **ApprovalStageNotifyEmailList** - Do NOT include when `EnableApprovalStage = No`
2. **RepositoryBucketKmsKeyArn** - Use KMS Key ARN from Step 2 outputs (if encryption enabled)
3. **Bucket Names** - Use actual bucket names from Step 2
4. **Account IDs & Emails** - Must match your actual accounts

**Prepare Parameters File:**

Edit `templates/lza-installer-params.json` with your values:

```bash
# Get values from previous steps
DEPLOYMENT_REGION="us-east-1"
MGMT_ACCOUNT_ID="123456789012"  # Your Management Account ID

# Get bucket names and KMS key from Step 2 stack outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})

CONFIG_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigBucketName`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})

KMS_KEY_ARN=$(aws cloudformation describe-stacks \
  --stack-name LZA-S3-Buckets \
  --query 'Stacks[0].Outputs[?OutputKey==`KMSKeyArn`].OutputValue' \
  --output text \
  --region ${DEPLOYMENT_REGION})

# Update the parameters file with your values
# Edit templates/lza-installer-params.json manually or use jq:
cat > lza-installer-params-updated.json <<EOF
[
  {"ParameterKey": "AcceleratorQualifier", "ParameterValue": "prod"},
  {"ParameterKey": "ManagementAccountId", "ParameterValue": "${MGMT_ACCOUNT_ID}"},
  {"ParameterKey": "ManagementAccountRoleName", "ParameterValue": "AWSAccelerator-PipelineRole"},
  {"ParameterKey": "RepositorySource", "ParameterValue": "s3"},
  {"ParameterKey": "RepositoryBucketName", "ParameterValue": "${SOURCE_BUCKET}"},
  {"ParameterKey": "RepositoryBucketObject", "ParameterValue": "release/v1.15.5.zip"},
  {"ParameterKey": "RepositoryBucketKmsKeyArn", "ParameterValue": "${KMS_KEY_ARN}"},
  {"ParameterKey": "EnableApprovalStage", "ParameterValue": "No"},
  {"ParameterKey": "ManagementAccountEmail", "ParameterValue": "aws-management@example.com"},
  {"ParameterKey": "LogArchiveAccountEmail", "ParameterValue": "aws-log-archive@example.com"},
  {"ParameterKey": "AuditAccountEmail", "ParameterValue": "aws-audit@example.com"},
  {"ParameterKey": "ControlTowerEnabled", "ParameterValue": "Yes"},
  {"ParameterKey": "EnableDiagnosticsPack", "ParameterValue": "Yes"},
  {"ParameterKey": "AcceleratorPrefix", "ParameterValue": "AWSAccelerator"},
  {"ParameterKey": "ConfigurationRepositoryLocation", "ParameterValue": "s3"},
  {"ParameterKey": "UseExistingConfigRepo", "ParameterValue": "No"}
]
EOF
```

**Deployment via AWS CLI:**

```bash
# Download LZA Installer template
LZA_VERSION="v1.15.5"
wget https://github.com/awslabs/landing-zone-accelerator-on-aws/releases/download/${LZA_VERSION}/AWSAccelerator-InstallerStack.template.json

# Deploy stack
aws cloudformation create-stack \
  --stack-name AWSAccelerator-InstallerStack \
  --template-body file://AWSAccelerator-InstallerStack.template.json \
  --parameters file://lza-installer-params-updated.json \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${DEPLOYMENT_REGION}

# Monitor stack creation
aws cloudformation wait stack-create-complete \
  --stack-name AWSAccelerator-InstallerStack \
  --region ${DEPLOYMENT_REGION}

# Get outputs
aws cloudformation describe-stacks \
  --stack-name AWSAccelerator-InstallerStack \
  --query 'Stacks[0].Outputs' \
  --region ${DEPLOYMENT_REGION}
```

**Deployment via Console:**
1. Download official LZA Installer template
2. Navigate to CloudFormation in External Pipeline Account
3. Create Stack → Upload template file
4. Stack name: `AWSAccelerator-InstallerStack`
5. Enter parameters from your customized JSON file
6. **CRITICAL**: Leave `ApprovalStageNotifyEmailList` field **completely blank**
7. Acknowledge IAM capabilities
8. Create stack

---

## Post-Deployment Verification

### Step 4: Verify Installer Stack Deployment

**Check Stack Outputs in External Pipeline Account:**

Expected CloudFormation Outputs:
- `PipelineName`: `prod-installer`
- `InstallerKey`: KMS Key ARN for installer encryption
- `InstallerLogsBucket`: Access logs bucket name
- `InstallerSecureBucket`: Secure bucket for pipeline artifacts

**Verify Created Resources:**

Navigate to AWS Console and verify:

1. **CodePipeline**
   - Pipeline name: `prod-installer`
   - Status: Should show pipeline structure

2. **CodeBuild**
   - Project: `prod-installer-project`

3. **S3 Buckets**
   - `prod-installer-{AccountId}-{Region}` (secure bucket)
   - `prod-s3-logs-{AccountId}-{Region}` (logs bucket)

4. **KMS Keys**
   - Alias: `alias/accelerator/prod/installer/kms/key`

5. **IAM Roles**
   - `prod-installer-codepipeline-role`
   - `prod-installer-codebuild-role`

6. **SSM Parameters**
   - `/accelerator/AWSAccelerator-InstallerStack/stack-id`
   - `/accelerator/AWSAccelerator-InstallerStack/version`
   - `/accelerator/installer/kms/key-arn`

---

### Step 5: Trigger Initial Pipeline Execution

**Manual Trigger via Console:**
1. Navigate to CodePipeline in External Pipeline Account
2. Select pipeline: `prod-installer`
3. Click "Release change" button
4. Confirm execution

**Monitor Pipeline Stages:**

1. **Source Stage**
   - Downloads source code from S3 bucket
   - Validates zip file exists at specified path
   - Check: S3 object version ID appears in execution details

2. **Install Stage**
   - CodeBuild project `prod-installer-project` executes
   - Runs CDK bootstrap in Management Account
   - Synthesizes main pipeline CloudFormation template
   - Check: Build logs show successful CDK synthesis

3. **Deploy Stage**
   - Deploys `prod-pipeline-stack` to Management Account
   - Creates main accelerator pipeline
   - Check: CloudFormation stack shows CREATE_COMPLETE

**Expected Timeline:**
- Source: 1-2 minutes
- Install: 10-15 minutes (includes CDK bootstrap)
- Deploy: 5-10 minutes
- **Total**: ~20-30 minutes for first run

---

### Step 6: Verify Main Pipeline Deployment in Management Account

Switch to **Management Account** and verify:

**CloudFormation Stack:**
- Stack name: `prod-pipeline-stack`
- Status: `CREATE_COMPLETE`
- Outputs should include main pipeline name

**CodePipeline:**
- Pipeline name: `prod-pipeline`
- Status: Pipeline structure visible
- Note: Pipeline may auto-trigger for first run

**S3 Configuration Source:**
- Pipeline source action should reference S3 bucket from External Pipeline Account
- Verify cross-account access is working

---

## Configuration Management

### Updating LZA Configuration Files

LZA configuration files are stored in the S3 bucket created in Step 2.

**Required Configuration Files:**
```
s3://lza-config-bucket/
├── global-config.yaml
├── accounts-config.yaml
├── organization-config.yaml
├── security-config.yaml
├── network-config.yaml
└── iam-config.yaml (optional)
```

**Update Process:**

1. **Prepare Updated Configuration**
   - Modify configuration files locally
   - Validate YAML syntax
   - Review changes against LZA documentation

2. **Upload to S3 via Console**
   - Navigate to S3 Console
   - Select config bucket: `lza-config-bucket`
   - Upload modified files
   - Verify new versions are created

3. **Trigger Pipeline**
   - Navigate to CodePipeline in Management Account
   - Select pipeline: `prod-pipeline`
   - Click "Release change"
   - Monitor execution through all stages

---

### Updating LZA Version

**Process:**

1. **Upload New Version to Source Bucket**
   - Download new LZA release zip from GitHub
   - Upload to S3 source bucket at path: `release/v{new-version}.zip`
   - Verify file uploaded successfully

2. **Update Installer Stack Parameters**
   - Navigate to CloudFormation in External Pipeline Account
   - Select stack: `AWSAccelerator-InstallerStack`
   - Update stack using existing template
   - Change parameter `RepositoryBucketObject` to new version path
   - Keep all other parameters unchanged

3. **Execute Update**
   - Review changes in change set
   - Execute update
   - Monitor stack update progress

4. **Trigger Installer Pipeline**
   - After stack update completes
   - Navigate to CodePipeline
   - Select `prod-installer`
   - Release change to deploy new version

---

## Expected Resource Naming

With `AcceleratorQualifier = prod`:

### In External Pipeline Account
- Pipeline (Installer): `prod-installer`
- CodeBuild Project: `prod-installer-project`
- Secure Bucket: `prod-installer-{AccountId}-{Region}`
- Access Logs Bucket: `prod-s3-logs-{AccountId}-{Region}`
- KMS Key Alias: `alias/accelerator/prod/installer/kms/key`

### In Management Account
- Pipeline Stack: `prod-pipeline-stack`
- Pipeline (Main): `prod-pipeline`
- SSM Parameters: `/accelerator/prod/*`
- LZA Stacks: Multiple stacks prefixed with `AWSAccelerator-`

---

## Troubleshooting

### Issue: ApprovalStageNotifyEmailList Validation Error

**Error Message:**
```
Parameter validation failed: Approval Stage notification email list is required when EnableApprovalStage is Yes
```

**Root Cause:** 
- Parameter validation rule enforces email list when `EnableApprovalStage = Yes`
- Email addresses provided when `EnableApprovalStage = No`

**Solution:**
1. If using Console: Leave `ApprovalStageNotifyEmailList` field **completely blank**
2. If using parameters file: Do NOT include this parameter in the JSON
3. Verify `EnableApprovalStage` is set to `No`

---

### Issue: S3 Source Bucket Access Denied

**Symptoms:** 
- Pipeline fails at Source stage
- Error: "Access Denied" or "403 Forbidden"

**Root Cause:** 
- Pipeline role lacks permission to read from source bucket
- Bucket policy not configured correctly

**Solution - Add Bucket Policy:**

Update the source bucket policy via CloudFormation:

```yaml
SourceBucketPolicy:
  Type: AWS::S3::BucketPolicy
  Properties:
    Bucket: !Ref SourceBucket
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Sid: AllowPipelineAccess
          Effect: Allow
          Principal:
            AWS: !Sub 'arn:aws:iam::${AWS::AccountId}:role/prod-installer-codepipeline-role'
          Action:
            - 's3:GetObject'
            - 's3:GetObjectVersion'
            - 's3:ListBucket'
          Resource:
            - !GetAtt SourceBucket.Arn
            - !Sub '${SourceBucket.Arn}/*'
```

Update the S3 bucket stack with this additional resource.

---

### Issue: Cross-Account Assume Role Failure

**Symptoms:**
- Installer pipeline fails at Deploy stage
- Error: "User is not authorized to perform: sts:AssumeRole"

**Root Cause:**
- Trust policy in Management Account role doesn't allow External Pipeline Account
- Role name mismatch between parameter and actual role

**Solution:**

1. **Verify Role Name**
   - In Management Account, check IAM role: `AWSAccelerator-PipelineRole`
   - Verify it matches `ManagementAccountRoleName` parameter exactly

2. **Verify Trust Policy**
   - Check trust policy allows External Pipeline Account ID
   - Update role trust policy if needed via CloudFormation stack update

3. **Verify Account ID**
   - Confirm `ManagementAccountId` parameter matches actual Management Account ID
   - Check for typos or old account IDs

---

### Issue: Configuration Files Not Found

**Symptoms:**
- Main pipeline fails during configuration stage
- Error: "Configuration file not found in S3"

**Root Cause:**
- Configuration files not uploaded to S3 bucket
- Incorrect S3 bucket reference in pipeline

**Solution:**

1. **Verify Files Uploaded**
   - Check S3 config bucket contains all required YAML files
   - Verify file names match exactly (case-sensitive)

2. **Verify Pipeline Source Configuration**
   - Check main pipeline source action references correct bucket
   - Verify cross-account access if bucket is in different account

3. **Upload Missing Files**
   - Use sample configuration from LZA repository
   - Upload to S3 config bucket root directory

---

### Issue: Stack Creation Fails - AcceleratorPrefix Immutable

**Symptoms:**
```
AcceleratorPrefix parameter cannot be updated after stack creation
```

**Root Cause:**
- Attempted to change `AcceleratorPrefix` or `AcceleratorQualifier` after initial deployment
- These parameters are immutable

**Solution:**
1. **For External Pipeline**: `AcceleratorQualifier` cannot be changed
2. **Only Option**: Delete stack completely and redeploy with new qualifier
3. **Warning**: This will destroy all pipeline infrastructure
4. **Recommendation**: Plan qualifier name carefully before initial deployment

---

## Security Considerations

### 1. S3 Bucket Security

**Encryption:**
- ✅ Enable KMS encryption on source and config buckets
- ✅ Use dedicated KMS key with proper key policies
- ✅ Enable encryption in-transit (HTTPS only)

**Access Control:**
- ✅ Block all public access
- ✅ Use restrictive bucket policies
- ✅ Enable versioning for audit trail
- ✅ Enable access logging

**CloudFormation Enhancement:**
```yaml
SourceBucketPolicy:
  Type: AWS::S3::BucketPolicy
  Properties:
    Bucket: !Ref SourceBucket
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Sid: DenyInsecureTransport
          Effect: Deny
          Principal: '*'
          Action: 's3:*'
          Resource:
            - !GetAtt SourceBucket.Arn
            - !Sub '${SourceBucket.Arn}/*'
          Condition:
            Bool:
              'aws:SecureTransport': 'false'
```

### 2. IAM Role Security

**Cross-Account Role:**
- ✅ Use least-privilege permissions (consider alternatives to AdministratorAccess)
- ✅ Add external ID for additional security
- ✅ Enable CloudTrail logging for all assume-role calls
- ✅ Regular audit of role usage

**Enhanced Trust Policy:**
```yaml
AssumeRolePolicyDocument:
  Version: '2012-10-17'
  Statement:
    - Effect: Allow
      Principal:
        AWS: !Sub 'arn:aws:iam::${ExternalPipelineAccountId}:root'
      Action: 'sts:AssumeRole'
      Condition:
        StringEquals:
          'sts:ExternalId': 'unique-external-id-here'
```

### 3. Pipeline Security

**Considerations:**
- ⚠️ No manual approval stage means automatic deployments
- ⚠️ Any change to S3 config triggers deployment immediately
- ✅ Consider enabling approval stage for production environments
- ✅ Implement change review process before uploading to S3
- ✅ Use separate buckets for dev/test/prod configurations

### 4. Monitoring and Alerting

**CloudWatch Alarms:**
- Pipeline failure notifications
- Unauthorized S3 access attempts
- Cross-account role assumption monitoring

**CloudTrail:**
- Enable in all accounts
- Monitor for security-relevant events
- Alert on high-risk actions

---

## Next Steps After Successful Deployment

### Immediate Actions (Day 1)

1. ✅ **Verify Control Tower Integration**
   - Check AWS Control Tower dashboard
   - Verify LZA registered as a managed application
   - Review Service Catalog portfolio access

2. ✅ **Review Initial Pipeline Execution**
   - Monitor main pipeline first run
   - Review CloudFormation stacks deployed
   - Check for any failures or warnings

3. ✅ **Backup Configuration**
   - Export current S3 configuration to version control
   - Document any manual changes made
   - Establish configuration change process

### Configuration Phase (Week 1)

4. ✅ **Configure Organizational Structure**
   - Update `accounts-config.yaml` with OUs and accounts
   - Define account vending process
   - Configure email addresses for new accounts

5. ✅ **Define Security Baseline**
   - Update `security-config.yaml`
   - Configure AWS Config rules
   - Define Security Hub standards
   - Configure GuardDuty settings

6. ✅ **Design Network Architecture**
   - Update `network-config.yaml`
   - Define VPC design and CIDR ranges
   - Configure Transit Gateway
   - Set up centralized networking

7. ✅ **Configure Global Settings**
   - Update `global-config.yaml`
   - Define logging strategy
   - Configure CloudTrail organization trail
   - Set up centralized logging account structure

### Testing and Validation (Week 2)

8. ✅ **Deploy Configuration Changes Incrementally**
   - Upload one config file at a time
   - Trigger pipeline after each upload
   - Validate deployment success before next change

9. ✅ **Test Account Vending**
   - Create test account via `accounts-config.yaml`
   - Verify account baseline deployment
   - Validate security controls applied

10. ✅ **Verify Security Controls**
    - Test GuardDuty findings
    - Verify Security Hub compliance scores
    - Check AWS Config rule compliance

### Ongoing Operations

11. ✅ **Establish Change Management Process**
    - Define approval process for configuration changes
    - Document testing procedures
    - Create rollback procedures

12. ✅ **Monitor and Maintain**
    - Regular pipeline execution monitoring
    - Review CloudFormation drift detection
    - Update LZA version quarterly
    - Review and update configurations based on AWS best practices

---

## Configuration File Templates

### Minimal `global-config.yaml` Example

```yaml
homeRegion: us-east-1
enabledRegions:
  - us-east-1
  - us-west-2
managementAccountAccessRole: AWSControlTowerExecution
cloudwatchLogRetentionInDays: 365
logging:
  account: LogArchive
  cloudtrail:
    enable: true
    organizationTrail: true
```

### Minimal `accounts-config.yaml` Example

```yaml
mandatoryAccounts:
  - name: Management
    description: Management account
    email: aws-management@example.com
    organizationalUnit: Root
  - name: LogArchive
    description: Log Archive account
    email: aws-log-archive@example.com
    organizationalUnit: Security
  - name: Audit
    description: Security Audit account
    email: aws-audit@example.com
    organizationalUnit: Security

workloadAccounts: []
```

---

## Reference Architecture

### Deployment Architecture

```
┌─────────────────────────────────────────────────┐
│         External Pipeline Account               │
│                                                 │
│  ┌─────────────────┐      ┌─────────────────┐ │
│  │  S3 Source      │      │  S3 Config      │ │
│  │  Bucket         │      │  Bucket         │ │
│  │  (LZA Code)     │      │  (YAML Files)   │ │
│  └────────┬────────┘      └────────┬────────┘ │
│           │                        │          │
│  ┌────────▼──────────────────────┐ │          │
│  │  prod-installer Pipeline      │ │          │
│  │  (Deploys Main Pipeline)      │ │          │
│  └───────────────┬────────────────┘ │          │
│                  │                   │          │
└──────────────────┼───────────────────┘          
                   │ Cross-Account                
                   │ AssumeRole                   
                   ▼                              
┌─────────────────────────────────────────────────┐
│         Management Account                      │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  prod-pipeline-stack (CloudFormation)    │  │
│  └──────────────────┬───────────────────────┘  │
│                     │                           │
│  ┌──────────────────▼───────────────────────┐  │
│  │  prod-pipeline (Main LZA Pipeline)       │  │
│  │  - Source: S3 Config Bucket              │  │
│  │  - Build: Validate & Synthesize          │  │
│  │  - Deploy: Multi-account deployment      │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-09-28  
**LZA Version:** 1.15.5+  
**Deployment Method:** CloudFormation Templates
