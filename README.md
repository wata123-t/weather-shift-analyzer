# RetroWeather-Insights: Serverless Data Pipeline

70年前（1950年代）と現代の気象データを比較・分析するためのサーバーレス・データパイプラインです。Slackからのリクエストをトリガーに、GCP上でデータの取得・加工・蓄積を自動で行います。

## 🚀 Overview
「最近の夏は昔より本当に暑いのか？」という疑問を、客観的なデータで検証するために開発しました。
Slackのスラッシュコマンドから特定の地点の気象データを召喚し、BigQueryで集計、Looker Studioで可視化します。

## 🏗 Architecture
Slackの応答制限（3秒）を回避するため、Cloud Tasksを用いた非同期アーキテクチャを採用しています。

```mermaid
graph TD
    subgraph Slack_Workspace
        A[User: /weather-compare] -->|Slash Command| B(Slack API)
    end

    subgraph Google_Cloud_Platform
        B -->|HTTP POST| C[Cloud Functions: Receiver]
        
        subgraph Asynchronous_Queue
            C -->|Create Task| D[Cloud Tasks]
            D -->|Trigger| E[Cloud Functions: Worker]
            C -.->|Immediate Response 200| B
        end

        subgraph Data_Processing
            E -->|1. Fetch API Data| F(Open-Meteo API)
            E -->|2. Load Raw Data| G[(BigQuery: raw_table)]
            E -->|3. Run SQL Transformation| H[(BigQuery: monthly_table)]
        end

        subgraph Visualization
            H --> I[Looker Studio]
        end
    end

    E -.->|4. Post Result| B
```

### Key Technologies
- **Runtime**: Python 3.11 (Cloud Functions)
- **Infrastructure**: Terraform (IaC)
- **Data Warehouse**: BigQuery
- **Task Queue**: Cloud Tasks (Asynchronous processing)
- **External API**: Open-Meteo Archive API
- **BI Tool**: Looker Studio

## 💡 Technical Highlights & Design Decisions

### 1. Asynchronous Task Handling
Slack APIの3秒タイムアウト制約を解決するため、**Receiver-Workerパターン**を採用。
- `Receiver` 関数: リクエストを即座に受理し、200 OKを返却。
- `Cloud Tasks`: 処理をキューイングし、リトライ耐性を確保。
- `Worker` 関数: 実際のデータフェッチと集計を実行。

### 2. Efficient Data Processing (SQL-First)
データ処理の負荷を考慮し、役割を明確に分離しました。
- **Python**: APIからのデータ抽出（ETLのEとL）を担当。
- **SQL (BigQuery)**: 70年分のデータ計算（不快指数の算出、月次集計）を担当。
これにより、アプリケーション側のメモリ消費を抑え、高速な集計を実現しています。

### 3. Infrastructure as Code (Terraform)
コンソールでの手動設定を一切排除し、すべてのGCPリソースをTerraformで定義。
`terraform apply` 一発で分析基盤が立ち上がる再現性を担保しています。

## 🛠 Usage
1. Slackで `/weather-compare` を実行。
2. Cloud Tasks経由でWorkerが起動し、Open-Meteoから過去と現在のデータを取得。
3. BigQuery上で集計SQLが実行され、`monthly_comp_data` テーブルが更新。
4. 処理完了後、Slackに完了通知が届きます。

## 🚧 Roadmap (Future Improvements)
- [ ] **Security**: Slack Signing Secret を用いたリクエスト署名の検証実装。
- [ ] **Monitoring**: Slack Webhook を利用したエラー通知の高度化。
- [ ] **Data Scope**: 比較対象期間をパラメータで動的に変更できる機能。



## 📁 Project Structure

```text
.
├── terraform/                # Infrastructure as Code (IaC)
│   ├── main.tf               # メインのリソース定義 (Functions, Tasks, BQ)
│   ├── variables.tf          # 環境変数・設定値の定義
│   ├── outputs.tf            # デプロイ後に出力する情報（URL等）
│   └── files/                # デプロイ用にアーカイブされたzip（自動生成）
│
├── functions/                # Cloud Functions ソースコード
│   ├── receiver/             # Slackリクエスト受付用 (Receiver)
│   │   ├── main.py           # 受付ロジック & Cloud Tasksへの登録
│   │   └── requirements.txt  # 依存ライブラリ (google-cloud-tasks等)
│   │
│   └── worker/               # データ取得・加工用 (Worker)
│       ├── main.py           # Open-Meteo API取得 & BQロード
│       ├── requirements.txt  # 依存ライブラリ (pandas, pandas-gbq等)
│       └── sql/              # 集計用SQLクエリ
│           └── create_monthly_comp.sql  # 70年前比較用の集計SQL
│
└── docs/                     # ドキュメント、構成図、スクリーンショット


### 解説のアピールポイント（READMEに追加する言葉）

この構造図のすぐ下に、以下のような「設計意図」を数行添えるとさらに効果的です。

> #### **Design Intent**
> - **Separation of Concerns**: インフラ（Terraform）とアプリケーションロジック（functions）を分離し、保守性を高めています。
> - **SQL Externalization**: 複雑な集計ロジックをPythonコード内に直接記述せず、`.sql`ファイルとして外出しすることで、SQL単体でのテストや修正を容易にしています。
> - **Modular Functions**: 受付（Receiver）と実行（Worker）を別関数に分けることで、将来的な「Slack以外のインターフェース追加」にも柔軟に対応できる構成にしています。

---

### 次のステップとしてのお手伝い

ディレクトリ構造が固まったので、次は**「このリポジトリをクローンした人がどうやってデプロイするか」という「Setup / Deployment」のセクション**を作成しましょうか？（`terraform apply` を実行するまでの手順など）



