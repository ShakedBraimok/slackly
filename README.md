# slackly

Get CloudWatch alerts in Slack without building the glue yourself. Define alarms in one alarms.json, run Terraform, and this template ships a secure Lambda-based notifier with channel routing, rich messages, retries/DLQ, and dashboards - so your team sees issues where they already work.

# Quick Start Guide

Get CloudWatch alarms delivered to Slack channels with step-by-step instructions and automated validation.

## Prerequisites Checklist

Before you start, ensure you have:

- [ ] AWS CLI installed and configured (`aws --version`)
- [ ] Terraform >= 1.0 installed (`terraform version`)
- [ ] AWS credentials configured (`aws sts get-caller-identity`)
- [ ] Slack workspace admin access (to create incoming webhooks)
- [ ] Appropriate AWS permissions (Lambda, SNS, CloudWatch, Secrets Manager, KMS, IAM)

## Step 1: Set Up Slack Webhooks

### Create Slack App and Webhooks

1. Go to https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. Name it (e.g., "AWS Alerts") and select your workspace
4. Navigate to **"Incoming Webhooks"** → Toggle **"Activate Incoming Webhooks"** to **On**
5. Click **"Add New Webhook to Workspace"** for each channel you want to alert:
   - `#alerts` → Copy webhook URL
   - `#critical` → Copy webhook URL
   - `#database` → Copy webhook URL
   - (Repeat for all channels you need)

**Save these webhook URLs** - you'll need them in Step 2.

### Webhook URL Format
```
https://hooks.slack.REDACTED_SECRETXXXXXXXXXXXXX
```

## Step 2: Configure Alarms

Create `alarms.json` in the project root with your CloudWatch alarms:

```bash
# Create your alarms file
cat > alarms.json << 'EOF'
[
  {
    "name": "lambda-errors",
    "metric": "Errors",
    "namespace": "AWS/Lambda",
    "statistic": "Sum",
    "period": 300,
    "threshold": 5,
    "comparison": "GreaterThanThreshold",
    "evaluation_periods": 2,
    "slack_channel": "alerts",
    "dimensions": {
      "FunctionName": "my-function"
    }
  }
]
EOF
```

**Example Alarm Structure:**
```json
[
  {
    "name": "lambda-errors",
    "metric": "Errors",
    "namespace": "AWS/Lambda",
    "statistic": "Sum",
    "period": 300,
    "threshold": 5,
    "comparison": "GreaterThanThreshold",
    "evaluation_periods": 2,
    "slack_channel": "alerts",
    "dimensions": {
      "FunctionName": "my-function"
    }
  },
  {
    "name": "database-cpu-high",
    "metric": "CPUUtilization",
    "namespace": "AWS/RDS",
    "statistic": "Average",
    "period": 300,
    "threshold": 80,
    "comparison": "GreaterThanThreshold",
    "evaluation_periods": 3,
    "slack_channel": "database"
  }
]
```

**Key Fields:**
- `slack_channel`: Must match channel name in webhook map (without `#`)
- `threshold`: When to trigger alarm
- `comparison`: `GreaterThanThreshold`, `LessThanThreshold`, etc.
- `dimensions`: Filters for specific resources

**AWS Documentation Resources:**
- [CloudWatch Alarms](https://docs.aws.amazon.REDACTED_TOKEN.html) - Creating and managing alarms
- [CloudWatch Metrics](https://docs.aws.amazon.REDACTED_TOKEN.html) - Available metrics by service
- [Alarm Comparison Operators](https://docs.aws.amazon.REDACTED_TOKEN.html#alarm-evaluation) - Understanding comparison operators

## Step 3: Configure Environment Variables

Create your environment configuration:

```bash
cd envs/dev
```

Edit `envs/dev/terraform.tfvars`:

```hcl
# Required
environment  = "dev"
project_name = "my-project"          # CHANGE THIS
aws_region   = "us-east-1"           # CHANGE THIS

# Slack Webhooks - CRITICAL: Map channel names to webhook URLs
slack_webhook_urls = jsonencode({
  "alerts"   = "https://hooks.slack.REDACTED_TOKEN"  # CHANGE THIS
  "critical" = "https://hooks.slack.REDACTED_TOKEN"  # CHANGE THIS
  "database" = "https://hooks.slack.REDACTED_TOKEN"  # CHANGE THIS
})

# Optional: VPC Configuration (if Lambda needs VPC access)
# vpc_id     = "vpc-xxxxx"
# subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

# Optional: Monitoring
enable_log_encryption = true
enable_monitoring     = true
log_retention_days    = 7

# Optional: Lambda Configuration
lambda_memory         = 256
lambda_timeout        = 60
reserved_concurrent_executions = 5
```

**IMPORTANT:** The `slack_channel` field in your `alarms.json` must match the keys in `slack_webhook_urls` map.

Example:
- Alarm has `"slack_channel": "alerts"`
- tfvars must have `"alerts" = "https://hooks.slack.com/..."`

## Step 4: Validate Configuration

```bash
# Validate alarms JSON
make validate-alarms ENV=dev

# Validate Terraform configuration
make validate ENV=dev
```

**Common Issues:**
- Invalid JSON syntax → Check for trailing commas, missing quotes
- Channel mismatch → Ensure alarm `slack_channel` matches webhook map keys
- Invalid webhook URL → URLs must start with `https://hooks.slack.com/services/`

## Step 5: Deploy

```bash
# See what will be created
make plan ENV=dev

# Deploy everything
make apply ENV=dev
```

**What gets created:**
- Lambda function with Python runtime
- SNS topics (one per alarm or shared)
- CloudWatch alarms from your JSON
- Secrets Manager secret for webhook URLs
- Dead Letter Queue for failed notifications
- CloudWatch dashboard for monitoring
- KMS keys for encryption
- IAM roles with least privilege

## Step 6: Test Slack Integration

```bash
# Send test message to Slack
make test-slack ENV=dev

# List all deployed alarms
make list-alarms ENV=dev

# List configured channels
make list-channels ENV=dev
```

You should see a test message appear in your Slack channels.

## Slack Message Format

When an alarm triggers, you'll receive a formatted message:

```
🔴 ALARM: lambda-errors

Status: ALARM
Reason: Threshold Crossed: 5 datapoints were greater than 5.0
Time: 2024-01-15 10:30:45 UTC

Metric: Errors
Namespace: AWS/Lambda
Dimensions: FunctionName=my-function

View in CloudWatch →
```

Colors:
- 🔴 Red: ALARM state
- 🟢 Green: OK state
- 🟡 Yellow: INSUFFICIENT_DATA state

## Next Steps

### Monitor Your Alarms

```bash
# View CloudWatch dashboard
make dashboard ENV=dev

# Check Lambda logs
make logs ENV=dev

# View Lambda metrics
make lambda-metrics ENV=dev
```

### Add More Alarms or Channels

1. Edit `alarms.json` to add more alarms
2. If using new channels, update `slack_webhook_urls` in tfvars
3. Run `make validate-alarms ENV=dev`
4. Run `make apply ENV=dev`

### Deploy to Staging/Production

```bash
# Create production Slack webhooks (recommended: separate workspace)
# Create production alarms file
cp alarms.json alarms-prod.json
# Edit alarms-prod.json with production thresholds

# Create production environment config
mkdir -p envs/prod
cp envs/dev/terraform.tfvars envs/prod/terraform.tfvars
# Edit prod tfvars (change environment = "prod", update webhooks)

# Deploy to production
make apply ENV=prod
```

## Common Alarm Patterns

### Lambda Function Errors
```json
{
  "name": "lambda-errors",
  "metric": "Errors",
  "namespace": "AWS/Lambda",
  "threshold": 5,
  "slack_channel": "alerts",
  "dimensions": {"FunctionName": "my-function"}
}
```

### RDS High CPU
```json
{
  "name": "rds-cpu-high",
  "metric": "CPUUtilization",
  "namespace": "AWS/RDS",
  "threshold": 80,
  "slack_channel": "database",
  "dimensions": {"DBInstanceIdentifier": "mydb"}
}
```

### ECS Service Memory
```json
{
  "name": "ecs-memory-high",
  "metric": "MemoryUtilization",
  "namespace": "AWS/ECS",
  "threshold": 85,
  "slack_channel": "alerts",
  "dimensions": {
    "ServiceName": "my-service",
    "ClusterName": "my-cluster"
  }
}
```

### API Gateway 5xx Errors
```json
{
  "name": "api-5xx-errors",
  "metric": "5XXError",
  "namespace": "AWS/ApiGateway",
  "threshold": 10,
  "slack_channel": "critical",
  "dimensions": {"ApiName": "my-api"}
}
```

### Log Metric Filter
```json
{
  "name": "application-errors",
  "metric": "ErrorCount",
  "namespace": "CustomApp",
  "threshold": 5,
  "slack_channel": "alerts"
}
```

## Troubleshooting

### Slack messages not appearing?

1. **Verify webhook URLs:**
   ```bash
   make list-channels ENV=dev
   ```

2. **Check Lambda execution:**
   ```bash
   make logs ENV=dev
   ```

3. **Test webhook manually:**
   ```bash
   curl -X POST "YOUR_WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d '{"text": "Test message"}'
   ```

4. **Check DLQ for failed messages:**
   ```bash
   aws sqs receive-message \
     --queue-url $(make outputs ENV=dev | grep dlq_url) \
     --max-number-of-messages 10
   ```

### Alarms not triggering?

1. **Verify alarm configuration:**
   ```bash
   make list-alarms ENV=dev
   ```

2. **Check CloudWatch console** to see alarm status and metric data

3. **Ensure dimensions match** your resources exactly

### Lambda timeout issues?

Increase timeout in tfvars:
```hcl
lambda_timeout = 120  # Increase to 2 minutes
```

### Channel name mismatch?

Error: `Channel 'alerts' not found in webhook configuration`

Fix: Ensure tfvars has:
```hcl
slack_webhook_urls = jsonencode({
  "alerts" = "https://..."  # Must match alarm's slack_channel
})
```

## Clean Up

To remove all resources:

```bash
make destroy ENV=dev
```

**Note:** This will delete:
- All CloudWatch alarms
- Lambda function
- SNS topics
- Secrets Manager secret (with 30-day recovery window)
- KMS keys (scheduled for deletion)

## Security Best Practices

1. **Webhook URLs are secrets** - Never commit them to git
2. **Use different webhooks per environment** (dev/staging/prod)
3. **Enable encryption** for logs and dead letter queue
4. **Review IAM permissions** - template uses least privilege
5. **Monitor the monitoring** - Check Lambda errors regularly
6. **Set up alerting on DLQ** - Get notified if messages fail

## Support

- Run `make help` to see all available commands and get help with common tasks
- Open a support ticket at [https://senora.dev/NewTicket](https://senora.dev/NewTicket)


## Environment Variables

This project uses environment-specific variable files in the `envs/` directory.

### dev
Variables are stored in `envs/dev/terraform.tfvars`



## GitHub Actions CI/CD

This project includes automated Terraform validation via GitHub Actions.

### Required GitHub Secrets

Configure these in Settings > Secrets > Actions:

- `AWS_ACCESS_KEY_ID`: Your AWS Access Key ID
- `AWS_SECRET_ACCESS_KEY`: Your AWS Secret Access Key
- `TF_STATE_BUCKET`: S3 bucket name for Terraform state
- `TF_STATE_KEY`: Path to state file in S3 bucket

💡 **Tip**: Check your `backend.tf` file for the bucket and key values.


---
*Generated by [Senora](https://senora.dev)*
