#################################################################
# メイン構成ファイル (Main Infrastructure Definitions)
# 
# 本ファイルは、インフラリソース（GCP）を定義します。
# 
# 主な構築リソース:
# ・Cloud Functions: Slack受付(Receiver) & データ処理(Worker)
# ・Cloud Tasks: 関数間の非同期連携・リトライ管理
# ・BigQuery: 収集した気象データの格納用テーブル
# ・Secret Manager: Slack API等の機密情報の安全な管理
# ・IAM: 各サービス間の最小権限によるセキュアな連携設定
#################################################################

# ---------------------------------------------
# Google Cloud プロバイダの設定
# 操作対象のプロジェクトとデフォルトのリージョンを指定します
# ---------------------------------------------
provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------
# Cloud Functions 用のソースコード格納バケット
# 関数をデプロイするための ZIP ファイルを保持します
# ---------------------------------------------
resource "google_storage_bucket" "source_bucket" {
  name     = "${var.project_id}-functions-source"
  location = "ASIA-NORTHEAST1"
}

# ---------------------------------------------
# Cloud Tasks キューの作成
# ---------------------------------------------
resource "google_cloud_tasks_queue" "default" {
  name     = var.queue_id
  location = var.region
}

####################################################################
# ★ Receiver関数 (Slack受付用)
####################################################################

# ---------------------------------------------------------
# 1. ローカルのPythonソースをZIP圧縮
# ---------------------------------------------------------
data "archive_file" "receiver_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/receiver"
  output_path = "${path.module}/files/receiver.zip"
}

# ---------------------------------------------------------
# 2. 圧縮したファイルをCloud Storageへアップロード
# ---------------------------------------------------------
resource "google_storage_bucket_object" "receiver_archive" {
  name   = "receiver-${data.archive_file.receiver_zip.output_md5}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.receiver_zip.output_path
}

# ---------------------------------------------------------
# 3. Cloud Function(第一世代)の定義
# ---------------------------------------------------------
resource "google_cloudfunctions_function" "receiver" {
  # 基本設定（名前と言語）
  name        = "slack-receiver"
  runtime     = "python311"
  entry_point = "slack_receiver"
  
  # ソースコードの場所(先ほどアップロードした ZIPファイルをソースとして使用する)
  source_archive_bucket = google_storage_bucket.source_bucket.name
  source_archive_object = google_storage_bucket_object.receiver_archive.name
  # 公開設定(この関数に URL を発行し、インターネット（Slack）からアクセスできる)
  trigger_http          = true

  # 環境変数の作成(Python受け渡し用)
  environment_variables = {
    PROJECT_ID = var.project_id
    QUEUE_ID   = var.queue_id
    LOCATION   = var.region
    WORKER_URL = "https://${var.region}-${var.project_id}.cloudfunctions.net/weather-worker"
    SERVICE_ACCOUNT_EMAIL = google_service_account.functions_sa.email
  }

  # シークレットのマッピング
  secret_environment_variables {
    key     = "SLACK_BOT_TOKEN"
    secret  = "SLACK_BOT_TOKEN"
    version = "latest"
  }
  secret_environment_variables {
    key     = "SLACK_SIGNING_SECRET"
    secret  = "SLACK_SIGNING_SECRET"
    version = "latest"
  }
  # 実行サービスアカウント設定 ：「Cloud Tasks への タスク作成許可」の権限を持たせる
  service_account_email = google_service_account.functions_sa.email
}

# ---------------------------------------------------------
#  Cloud Function に対するアクセス許可設定
# ---------------------------------------------------------
resource "google_cloudfunctions_function_iam_member" "receiver_invoker" {
  project        = google_cloudfunctions_function.receiver.project
  region         = google_cloudfunctions_function.receiver.region
  cloud_function = google_cloudfunctions_function.receiver.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

####################################################################
# ★ Worker関数 (気象庁API処理用)
####################################################################

# ---------------------------------------------------------
# 1. ローカルのPythonソースをZIP圧縮
# ---------------------------------------------------------
data "archive_file" "worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../functions/worker"
  output_path = "${path.module}/files/worker.zip"
}

# ---------------------------------------------------------
# 2. 圧縮したファイルをCloud Storageへアップロード
# ---------------------------------------------------------
resource "google_storage_bucket_object" "worker_archive" {
  name   = "worker-${data.archive_file.worker_zip.output_md5}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.worker_zip.output_path
}

# ---------------------------------------------------------
# 3. Cloud Function(第一世代)の定義
# ---------------------------------------------------------
resource "google_cloudfunctions_function" "worker" {
  # 基本設定（名前と言語）
  name    = "weather-worker"
  runtime = "python311"
  entry_point = "fetch_weather_handler"

  # BigQuery処理も考慮し、メモリサイズ拡張(256MByte→1024MByte)
  available_memory_mb = 1024
  # タイムアウト延長(1分→5分)
  timeout             = 300

  # ソースコードの場所(先ほどアップロードした ZIPファイルをソースとして使用する)
  source_archive_bucket = google_storage_bucket.source_bucket.name
  source_archive_object = google_storage_bucket_object.worker_archive.name
  # 「この関数に外部や他のサービスからアクセスするための『窓口』を作る」という設定
  # 今回は「Cloud Tasks」から受けるのに必要
  trigger_http          = true

  # 環境変数の作成(Python受け渡し用)
  environment_variables = {
    PROJECT_ID = var.project_id
    DATASET_ID = google_bigquery_dataset.weather_dataset.dataset_id
    LAT        = var.lat
    LON        = var.lon
    TABLE_ID   = var.table_id
  }
  # 実行サービスアカウント設定 ：この関数に「BigQuery操作」などの専用権限を持たせる
  service_account_email = google_service_account.functions_sa.email

}

####################################################################
# ★ BigQuery リソース
####################################################################
# データ格納場所（データセット）の定義
resource "google_bigquery_dataset" "weather_dataset" {
  dataset_id                 = "weather_data"
  location                   = var.region
  delete_contents_on_destroy = true
}

# 格納するデータの定義
resource "google_bigquery_table" "weather_table" {
  # 基本設定
  dataset_id          = google_bigquery_dataset.weather_dataset.dataset_id
  table_id            = var.table_id
  deletion_protection = false
  
  # BigQueryのデータフォーマット定義
  schema = <<EOF
[
  {"name": "date",          "type": "DATE", "mode": "REQUIRED"},
  {"name": "temp_max",      "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "temp_min",      "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "humidity_mean", "type": "FLOAT", "mode": "NULLABLE"}
]
EOF
}

####################################################################
# ★ Secret Manager
####################################################################

# ---------------------------------------------------------
# Secret Manager の作成、定義
# ---------------------------------------------------------
resource "google_secret_manager_secret" "slack_secrets" {
  for_each  = toset(["SLACK_BOT_TOKEN", "SLACK_SIGNING_SECRET"])
  secret_id = each.key
  # Googleにお任せで、いつでもどこでも安全に秘密情報を読み取れる設定
  replication {
    auto {}
  }
}

# ---------------------------------------------------------
# Secret Manager に対する権限の設定
# ---------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "secret_access" {
  for_each  = google_secret_manager_secret.slack_secrets
  secret_id = each.value.id
  # 「シークレットの中身」を取得するための最小限の権限
  role      = "roles/secretmanager.secretAccessor"
  # Cloud Functions を実行する専用サービスアカウントにのみ権限を付与
  member    = "serviceAccount:${google_service_account.functions_sa.email}"
}

# ---------------------------------------------------------
# 秘密情報の割付(SLACK_BOT_TOKEN)
# ---------------------------------------------------------
resource "google_secret_manager_secret_version" "slack_bot_token_val" {
  secret      = google_secret_manager_secret.slack_secrets["SLACK_BOT_TOKEN"].id
  secret_data = var.slack_bot_token
}

# ---------------------------------------------------------
# 秘密情報の割付(SLACK_SIGNING_SECRET)
# ---------------------------------------------------------
resource "google_secret_manager_secret_version" "slack_signing_secret_val" {
  secret      = google_secret_manager_secret.slack_secrets["SLACK_SIGNING_SECRET"].id
  secret_data = var.slack_signing_secret
}

####################################################################
# ★ Service Account 関連
####################################################################

# ---------------------------------------------------------
# 関数実行用の専用サービスアカウントの作成
# ---------------------------------------------------------
resource "google_service_account" "functions_sa" {
  account_id   = "weather-app-sa"
  display_name = "Cloud Functions Execution Service Account"
}

# -------------------------------------------------------------------------------------
# --- 外部リソース(Cloud Tasks, BigQuery)に対して、権限（ロール）の付与
# -------------------------------------------------------------------------------------

# 1. Cloud Tasks へのタスク追加権限（Receiver関数が使用）
resource "google_project_iam_member" "cloud_tasks_enqueuer" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

# 2. BigQuery データへの書き込み権限（Worker関数が使用）
resource "google_project_iam_member" "bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

# 3. BigQuery の実行権限（Worker関数が使用）
resource "google_project_iam_member" "bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

# -------------------------------------------------------------------------------------
# --- 関数の呼び出し権限の設定
# -------------------------------------------------------------------------------------

# Worker関数を「作成した専用SA」からのみ呼び出せるよう制限し、未認証の外部アクセスを遮断します
resource "google_cloudfunctions_function_iam_member" "worker_invoker" {
  project        = google_cloudfunctions_function.worker.project
  region         = google_cloudfunctions_function.worker.region
  cloud_function = google_cloudfunctions_function.worker.name
  role           = "roles/cloudfunctions.invoker"
  # 作成した専用SAからの呼び出しのみ許可
  member = "serviceAccount:${google_service_account.functions_sa.email}"
}

# Cloud TasksがSAになり代わって、Workerを叩くために必要な権限です。
resource "google_service_account_iam_member" "sa_user_binding" {
  service_account_id = google_service_account.functions_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.functions_sa.email}"
}

