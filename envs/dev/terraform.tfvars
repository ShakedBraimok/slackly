# Terraform variables

environment = "dev"
project_name = "cloudwatch-slack"
aws_region = "us-east-1"
alarms_config_path = "../alarms.json"
slack_webhook_urls = null
vpc_id = null
subnet_ids = null
security_group_ids = null
log_retention_days = 30
enable_log_encryption = true
enable_enhanced_logging = true
enable_monitoring = true
lambda_error_threshold = 5
sns_failure_threshold = 1
alarm_notification_arns = null
tags = null
