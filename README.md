# RetroWeather-Insights: Serverless Data Pipeline

70年前（1950年代）と現代の気象データを比較・分析するためのサーバーレス・データパイプラインです。Slackからのリクエストをトリガーに、GCP上でデータの取得・加工・蓄積を自動で行います。

## 🚀 Overview
「最近の夏は昔より本当に暑いのか？」という疑問を、客観的なデータで検証するために開発しました。
Slackのスラッシュコマンドから特定の地点の気象データを召喚し、BigQueryで集計、Looker Studioで可視化します。

## 🏗 Architecture
Slackの応答制限（3秒）を回避するため、Cloud Tasksを用いた非同期アーキテクチャを採用しています。

[ここに先ほどのMermaid構成図を貼る]

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




