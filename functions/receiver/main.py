import os
import json
from slack_bolt import App
from slack_bolt.adapter.google_cloud_functions import SlackRequestHandler
from google.cloud import tasks_v2

# インスタンスをグローバルに定義し、コールドスタートを高速化
client = tasks_v2.CloudTasksClient()

#######################
# ◆機能ブロック1:「Bolt アプリの初期化」
#######################
# 1. Secret Manager から値を取得、環境変数にセット済(Terraform)
# 2. 環境変数から値を読み取り、署名検証(Signing Secret)の準備を行う
app = App(
    token=os.environ.get("SLACK_BOT_TOKEN"),
    signing_secret=os.environ.get("SLACK_SIGNING_SECRET"),
    # Cloud Functions で ack() を先に返すための設定
    process_before_response=True
)

##################################
# ◆機能ブロック2:「Cloud Functions 用のハンドラー作成」
##################################
handler = SlackRequestHandler(app)

#######################
# ◆機能ブロック3:「エントリーポイント」
#######################
def slack_receiver(request):
    # Bolt にリクエストを丸投げ（ここで署名検証とコマンド実行が行われる）
    return handler.handle(request)


# 環境変数読み込み
PROJECT  = os.environ.get("PROJECT_ID")
LOCATION = os.environ.get("LOCATION")
QUEUE = os.environ.get("QUEUE_ID")
WORKER_URL = os.environ.get("WORKER_URL")
SA_EMAIL = os.environ.get("SERVICE_ACCOUNT_EMAIL") 

###################################
# ◆機能ブロック4:「スラッシュコマンド(/comp_start)のハンドラー」
###################################
@app.command("/comp_start")
def handle_weather(ack, body):
    # 1. Slackへ即座に応答を返す（3秒ルール回避）
    ack("リクエストを受理しました。気象データの集計を開始します...")
    
    # 後続の 「fetch_weather_handler」 に必要な情報を取得
    response_url = body.get("response_url")
    command_text = body.get("text", "")

    parent = client.queue_path(PROJECT, LOCATION, QUEUE)

    # 3. 非同期タスクの生成
    task = {
        'http_request': {
            'http_method': tasks_v2.HttpMethod.POST,
            'url': WORKER_URL,
            'headers': {"Content-type": "application/json"},
            'body': json.dumps({
                "text": command_text,
                "response_url": response_url
            }).encode(),
            'oidc_token': {
                'service_account_email': SA_EMAIL
            }
        }
    }

    # 4. キューの投入（バトンタッチ完了）
    try:
        client.create_task(parent=parent, task=task)
    except Exception as e:
        print(f"Error creating task: {e}")


