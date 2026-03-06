#################################################################
# 変数定義 (Variable Declarations)
# 
# このプロジェクトで使用する変数の型やデフォルト値を定義します。
# 実際の値（プロジェクトIDやトークン等）は、本ファイルではなく
# `terraform.tfvars` に記述してください。
#
# 注意:
# 秘密情報（Slackトークン等）を含む変数は `sensitive = true` 
# を設定し、コンソール出力時に値が表示されないようにしています。
#################################################################
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  default = "asia-northeast1"
  type    = string
}

variable "dataset_id" {
  default = "weather_data"
  type    = string
}

variable "queue_id" {
  description = "Cloud Tasks Queue ID"
  type        = string
  default     = "weather-import-queue"
}

variable "lat" {
  description = "緯度"
  type        = string
  default     = "35.6895"
}

variable "lon" {
  description = "経度"
  type        = string
  default     = "139.6917"
}

variable "table_id" {
  type    = string
  default = "raw_weather_data"
}

variable "slack_bot_token" {
  description = "Slack Bot Token (xoxb-...)"
  type        = string
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Slack Signing Secret"
  type        = string
  sensitive   = true
}
