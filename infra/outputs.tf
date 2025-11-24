output "sns_topic_arn" {
  description = "ARN of the SNS topic used for CloudWatch alarms"
  value       = module.cloudwatch_slack_alerts.sns_topic_arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function that sends notifications to Slack"
  value       = module.cloudwatch_slack_alerts.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.cloudwatch_slack_alerts.lambda_function_name
}

output "cloudwatch_alarms" {
  description = "Map of CloudWatch alarm names to their ARNs"
  value       = module.cloudwatch_slack_alerts.cloudwatch_alarms
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing Slack webhook URLs"
  value       = aws_secretsmanager_secret.slack_webhook_urls.arn
}

output "kms_key_id" {
  description = "KMS key ID for log encryption"
  value       = var.enable_log_encryption ? aws_kms_key.logs[0].id : null
}

output "kms_key_arn" {
  description = "KMS key ARN for log encryption"
  value       = var.enable_log_encryption ? aws_kms_key.logs[0].arn : null
}

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value = var.enable_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.name_prefix}-slack-integration" : null
}

output "deployment_summary" {
  description = "Deployment summary information"
  value = {
    environment        = var.environment
    project_name       = var.project_name
    region             = var.aws_region
    alarms_count       = length(module.cloudwatch_slack_alerts.cloudwatch_alarms)
    log_encryption     = var.enable_log_encryption
    monitoring         = var.enable_monitoring
    lambda_in_vpc      = var.vpc_id != null
    sns_topic_name     = split(":", module.cloudwatch_slack_alerts.sns_topic_arn)[5]
    lambda_dlq_enabled = true
    xray_enabled       = true
  }
}
