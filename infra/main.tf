terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Backend configuration should be provided via backend config file or CLI
    # Example: terraform init -backend-config=backend-dev.hcl
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.tags,
      {
        Environment = var.environment
        ManagedBy   = "Terraform"
        Project     = var.project_name
      }
    )
  }
}

#--- Locals ---#
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

#--- Secrets Manager for Slack Webhook URLs ---#
resource "aws_secretsmanager_secret" "slack_webhook_urls" {
  name                    = "/${var.project_name}/${var.environment}/slack-webhook-urls"
  description             = "Slack webhook URLs for CloudWatch alarms"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.name_prefix}-slack-webhooks"
  }
}

resource "REDACTED_TOKEN" "slack_webhook_urls" {
  secret_id     = aws_secretsmanager_secret.slack_webhook_urls.id
  secret_string = jsonencode(var.slack_webhook_urls)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#--- CloudWatch to Slack Module ---#
module "cloudwatch_slack_alerts" {
  source  = "REDACTED_TOKEN"
  version = "~> 1.0"

  environment        = var.environment
  alarms_config_path = var.alarms_config_path
  slack_webhook_urls = var.slack_webhook_urls

  # Optional VPC configuration for Lambda
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-alarms"
    }
  )
}

#--- CloudWatch Log Groups ---#
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.enable_enhanced_logging ? 1 : 0

  name              = "/aws/lambda/${module.cloudwatch_slack_alerts.lambda_function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_log_encryption ? aws_kms_key.logs[0].arn : null

  tags = {
    Name = "${local.name_prefix}-lambda-logs"
  }
}

#--- KMS Key for Log Encryption ---#
resource "aws_kms_key" "logs" {
  count = var.enable_log_encryption ? 1 : 0

  description             = "KMS key for ${local.name_prefix} log encryption"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = {
    Name = "${local.name_prefix}-logs-key"
  }
}

resource "aws_kms_alias" "logs" {
  count = var.enable_log_encryption ? 1 : 0

  name          = "alias/${local.name_prefix}-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

resource "aws_kms_key_policy" "logs" {
  count = var.enable_log_encryption ? 1 : 0

  key_id = aws_kms_key.logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.cloudwatch_slack_alerts.lambda_function_name}"
          }
        }
      }
    ]
  })
}

#--- CloudWatch Alarms for Lambda Monitoring ---#
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-errors"
  alarm_description   = "Alert when Lambda function has errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.lambda_error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.cloudwatch_slack_alerts.lambda_function_name
  }

  alarm_actions = var.alarm_notification_arns

  tags = {
    Name = "${local.name_prefix}-lambda-errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-throttles"
  alarm_description   = "Alert when Lambda function is throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.cloudwatch_slack_alerts.lambda_function_name
  }

  alarm_actions = var.alarm_notification_arns

  tags = {
    Name = "${local.name_prefix}-lambda-throttles"
  }
}

resource "aws_cloudwatch_metric_alarm" "sns_failed_notifications" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-sns-failed-notifications"
  alarm_description   = "Alert when SNS fails to deliver notifications to Lambda"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = 300
  statistic           = "Sum"
  threshold           = var.sns_failure_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    TopicName = split(":", module.cloudwatch_slack_alerts.sns_topic_arn)[5]
  }

  alarm_actions = var.alarm_notification_arns

  tags = {
    Name = "${local.name_prefix}-sns-failures"
  }
}

#--- CloudWatch Dashboard ---#
resource "aws_cloudwatch_dashboard" "slack_integration" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-slack-integration"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Lambda Invocations" }],
            [".", "Errors", { stat = "Sum", label = "Lambda Errors" }],
            [".", "Throttles", { stat = "Sum", label = "Lambda Throttles" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Function Health"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfNotificationsDelivered", { stat = "Sum", label = "Delivered" }],
            [".", "NumberOfNotificationsFailed", { stat = "Sum", label = "Failed" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "SNS Notification Status"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for alarm_name in keys(module.cloudwatch_slack_alerts.cloudwatch_alarms) : [
              "AWS/CloudWatch", "AlarmState", {
                stat  = "Maximum"
                label = alarm_name
              }
            ]
          ]
          period = 300
          stat   = "Maximum"
          region = var.aws_region
          title  = "Alarm States"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/lambda/${module.cloudwatch_slack_alerts.lambda_function_name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region  = var.aws_region
          title   = "Recent Lambda Errors"
          stacked = false
        }
      }
    ]
  })
}

#--- Data Sources ---#
data "aws_caller_identity" "current" {}
