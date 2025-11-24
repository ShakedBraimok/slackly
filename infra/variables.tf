variable "environment" {
  description = "Environment name (e.g., dev, staging, prod, qa, etc.)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cloudwatch-slack"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alarms_config_path" {
  description = "Path to the alarms configuration JSON file"
  type        = string
  default     = "../alarms.json"
}

variable "slack_webhook_urls" {
  description = "Map of Slack webhook URLs for different channels (will be stored in Secrets Manager)"
  type        = map(string)
  sensitive   = true
  default     = {}
}

# VPC Configuration (optional)
variable "vpc_id" {
  description = "VPC ID for Lambda function (optional, for private networking)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for Lambda function (optional, required if vpc_id is set)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security Group IDs to attach to the Lambda (optional, required if vpc_id is set)"
  type        = list(string)
  default     = []
}

# Logging
variable "log_retention_days" {
  description = "CloudWatch Logs retention period (days)"
  type        = number
  default     = 30
}

variable "enable_log_encryption" {
  description = "Enable KMS encryption for CloudWatch Logs"
  type        = bool
  default     = true
}

variable "enable_enhanced_logging" {
  description = "Enable enhanced CloudWatch logging for Lambda function"
  type        = bool
  default     = true
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable CloudWatch alarms and dashboard for Lambda and SNS monitoring"
  type        = bool
  default     = true
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 5
}

variable "sns_failure_threshold" {
  description = "Threshold for SNS notification failures alarm"
  type        = number
  default     = 1
}

variable "alarm_notification_arns" {
  description = "List of SNS topic ARNs for alarm notifications (separate from Slack)"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
