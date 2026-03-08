import functions_framework
import pandas as pd
import requests
import os
from google.cloud import bigquery
from pydantic import BaseModel, Field
from typing import List, Optional

##############################
# Pydantic モデルの定義
##############################
# APIのレスポンス構造を定義
class DailyData(BaseModel):
    time: List[str]
    temperature_2m_max: List[Optional[float]]
    temperature_2m_min: List[Optional[float]]
    relative_humidity_2m_mean: List[Optional[float]]

# ルートの構造
class WeatherResponse(BaseModel):
    daily: DailyData

PROJECT_ID = os.environ.get("PROJECT_ID")
DATASET_ID = os.environ.get("DATASET_ID")
TABLE_ID   = os.environ.get("TABLE_ID")
# 環境変数は「文字列」で届くため、数値計算やAPI用に float へキャスト
LAT        = float(os.environ.get("LAT")) 
LON        = float(os.environ.get("LON"))
 

#######################
# ◆機能ブロック1:「エントリーポイント」
#######################
@functions_framework.http
def fetch_weather_handler(request):
    # 1. リクエストと環境変数の取得
    request_json = request.get_json(silent=True)
    response_url = request_json.get('response_url') if request_json else None
    
    table_path = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"
    client = bigquery.Client(project=PROJECT_ID)
    
    # デフォルトの成功メッセージ
    message = "✅ 気象データの更新と集計テーブルの作成が完了しました！"

    try:
        # 2. 既存データの消去
        client.query(f"TRUNCATE TABLE `{table_path}`").result()

        #########################################
        # ◆機能ブロック2:「ETL処理の実行」
        #########################################
        # サブ関数へ座標(LAT, LON)を引数として渡し、データをロード
        fetch_and_load("1952-01-01", "1954-12-31", client, table_path, LAT, LON)
        fetch_and_load("2023-01-01", "2025-12-31", client, table_path, LAT, LON)
        
        #########################################
        # ◆機能ブロック3: SQL集計処理
        #########################################
        sql_path = os.path.join(os.path.dirname(__file__), 'sql', 'create_monthly_comp.sql')
        with open(sql_path, 'r', encoding='utf-8') as f:
            sql_template = f.read()
        
        # テンプレート内の変数を置換して実行
        sql = sql_template.format(PROJECT_ID=PROJECT_ID, DATASET_ID=DATASET_ID)
        client.query(sql).result() 
        
    except Exception as e:
        # エラー発生時はメッセージを上書きし、ログに出力
        error_detail = str(e)
        if "validation error" in error_detail.lower():
            message = f"❌ APIデータの形式が正しくありません(Pydanticエラー): {error_detail[:100]}..."
        else:
            message = f"❌ 処理中にエラーが発生しました: {error_detail}"
        
        print(f"Detailed Error: {error_detail}")

    # 3. Slack への応答メッセージ送信（response_url がある場合のみ）
    if response_url:
        requests.post(response_url, json={
            "text": message,
            "response_type": "in_channel"
        })

    # Cloud Tasks への正常応答
    return "OK", 200 


####################################
# ◆機能ブロック2:「ETL処理の実装」
####################################
def fetch_and_load(start, end, bq_client, table_path, lat, lon):
    """
    API抽出(Extract) -> 整形(Transform) -> ロード(Load) を担う汎用関数
    """
    url = "https://archive-api.open-meteo.com/v1/archive"
    params = {
        "latitude": lat, 
        "longitude": lon, 
        "start_date": start, 
        "end_date": end,
        "daily": ["temperature_2m_max", "temperature_2m_min", "relative_humidity_2m_mean"],
        "timezone": "Asia/Tokyo"
    }
    
    # APIリクエスト
    response = requests.get(url, params=params)
    response.raise_for_status() 
    
    # Pydantic を使用:生データをモデルに流し込み、チェックと変換を行う
    weather_data = WeatherResponse(**response.json())
    # 合格したデータを辞書に戻す(model_dump() で辞書化し、その中の ['daily'] 部分だけを取り出す)
    valid_daily_dict = weather_data.daily.model_dump()
    # Pandasによるデータ整形
    df = pd.DataFrame(valid_daily_dict)
    # DATE型へ変換（時刻の切り捨て）
    df['time'] = pd.to_datetime(df['time']).dt.date
    
    # カラム名を BigQuery のスキーマに合わせる
    df = df.rename(columns={
        "time": "date", 
        "temperature_2m_max": "temp_max",
        "temperature_2m_min": "temp_min", 
        "relative_humidity_2m_mean": "humidity_mean"
    })
    
    # BigQuery への追記ロード
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    job = bq_client.load_table_from_dataframe(df, table_path, job_config=job_config)
    job.result()
