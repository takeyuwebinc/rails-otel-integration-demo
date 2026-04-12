# Rails 8.1 OTel統合デモアプリ 要件定義書

**作成日**: 2026年4月12日
**更新日**: 2026年4月12日

## 1. 機能概要

Rails 8.1で導入されたStructured Event Reporter（`Rails.event`）とOpenTelemetry、CloudWatchを統合するデモアプリケーションを構築する。

**目的**:
- Rails 8.1 Structured Event ReporterとOpenTelemetryの統合方法を実装を通じて理解する
- EventReporter→OTel統合をOTel Logs API方式で実装し、OTel仕様の方向性（OTEP 4430: events are logs with names）に沿った統合パターンを把握する
- 実装結果を技術記事（日本語）として公開し、Rails開発者（OTel初心者）に実装の参考情報を提供する

**背景**:
- 2026年4月時点で、EventReporter→OTelの公式統合ライブラリは存在しない（調査報告書 セクション2.4, 5）
- EventReporterとOTelの組み合わせに関する日本語記事も存在しない（調査報告書 セクション6）
- 本デモアプリと技術記事が、この空白地帯を埋める最初の日本語リソースとなることを意図する

## 2. 機能要件

### 2.1 サンプルアプリケーション

OTel計装の動作を示すための題材として、簡易書店アプリケーションを構築する。

#### 2.1.1 書籍管理

- 書籍の一覧表示、詳細表示、作成、編集、削除ができる
- 書籍は タイトル、著者名、価格、在庫数 を持つ

#### 2.1.2 注文処理

- 書籍を指定して注文を作成できる
- 注文作成時に在庫数を減算する
- 在庫不足の場合は注文を拒否し、理由を表示する
- 注文は 注文番号、書籍、数量、合計金額、ステータス を持つ
- 注文ステータスは `pending → confirmed → shipped` の順に一方向で遷移する。キャンセル・差戻しは対象外とする
- 注文一覧画面から、各注文のステータスを次の状態に進めるボタンを操作できる（pending→confirmed、confirmed→shipped）

#### 2.1.3 注文確認メール（バックグラウンドジョブ）

- 注文作成後、バックグラウンドジョブで注文確認メールを送信する
- デモ用途のため、実際のメール送信は不要。ジョブの実行とOTelトレースへの反映を確認できればよい

### 2.2 OTelテレメトリ（3シグナル同時稼働）

3つのOTelシグナル（Traces, Logs, Metrics）を常時同時に稼働させる。

#### 2.2.1 Traces（フレームワーク計装）

- `opentelemetry-instrumentation-rails`（`use_all`）を使用し、フレームワークレベルの自動計装を有効にする
- 以下のSpanがCloudWatch X-Rayで確認できること:
  - コントローラーアクション（Action Pack）
  - DBクエリ（Active Record）
  - ビューレンダリング（Action View）
  - バックグラウンドジョブ（Active Job）
- OTel Collector経由でCloudWatch X-Rayエンドポイント（`xray.{Region}.amazonaws.com/v1/traces`）に送信する

#### 2.2.2 Logs（EventReporterビジネスイベント）

- `Rails.event.notify`を使用して以下のビジネスイベントを発行する:
  - `order.created` — 注文作成時（注文番号、書籍ID、数量、合計金額を含む）
  - `order.status_changed` — 注文ステータス変更時（注文番号、変更前後のステータスを含む）
  - `book.viewed` — 書籍詳細ページ閲覧時（書籍ID、タイトルを含む）
  - `inventory.low` — 注文による在庫減算後、残在庫数が5以下になった時（書���ID、残在庫数を含む）
- これらのイベントをOTelパイプラインに統合するSubscriberを実装する（統合方式は2.3で定義）
- OTel Collector経由でCloudWatch Logsエンドポイント（`logs.{Region}.amazonaws.com/v1/logs`）に送信する

#### 2.2.3 Metrics（アプリケーションメトリクス）

- OTel Metrics SDKを使用して以下のメトリクスを計測する:
  - 注文作成数（Counter）
  - 注文金額（Histogram）
- OTel Collector経由でCloudWatch Metricsエンドポイント（`monitoring.{Region}.amazonaws.com/v1/metrics`）に送信する

### 2.3 EventReporter→OTel統合（Logs API方式）

EventReporterのイベントをOTel Logs API経由でLog Recordとして送信するSubscriberを実装する。

- `opentelemetry-logs-sdk`を使用する
- trace_id/span_idはOTel SDKが現在のSpanコンテキストから自動付与する
- CloudWatch Logs上でLog Recordとして確認できること

**この方式を採用する根拠**:
- OTel仕様の方向性（OTEP 4430: events are logs with names）に合致する
- EventReporterのpoint-in-timeイベントをLog Recordとして送信するのが意味的に正確
- trace contextの自動付与によりトレースとの関連付けが自然に実現される

### 2.4 インフラ構成

- Docker Composeで以下のコンテナを構成する:
  - Railsアプリケーション（Rails 8.1）
  - PostgreSQL
  - OTel Collector
- OTel Collectorは以下のパイプラインを処理する:
  - Traces: OTLP receiver → OTLP HTTP exporter（SigV4認証）→ CloudWatch X-Ray
  - Logs: OTLP receiver → OTLP HTTP exporter（SigV4認証）→ CloudWatch Logs
  - Metrics: OTLP receiver → OTLP HTTP exporter（SigV4認証）→ CloudWatch Metrics
- AWS認証情報はDocker Compose経由で環境変数として渡す

## 3. 前提条件・制約事項

### 3.1 前提条件

- **ランタイム**: Ruby 3.3以上、Rails 8.1
- **データベース**: PostgreSQL
- **コンテナ**: Docker, Docker Compose
- **AWSアカウント**: CloudWatchへの送信に必要。IAMユーザーまたはロールに以下の権限が付与されていること:
  - `xray:PutTraceSegments`, `xray:PutTelemetryRecords`（Traces）
  - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`（Logs）
  - `cloudwatch:PutMetricData`（Metrics）
- **AWSリージョン**: CloudWatch Metrics OTLPがPublic Previewの5リージョンのいずれか（us-east-1, us-west-2, ap-southeast-2, ap-southeast-1, eu-west-1）

### 3.2 制約事項

- **デモ用途限定**: 本アプリケーションは学習・記事執筆のためのデモであり、本番環境での利用を想定しない
- **認証・認可なし**: サンプルアプリにユーザー認証は実装しない
- **OTel Ruby SDKの成熟度**:
  - Traces SDK: Stable — 実用可能
  - Logs SDK（v0.5.0）: Development — API破壊変更のリスクあり
  - Metrics SDK: Development — API破壊変更のリスクあり
- **CloudWatch OTLP Metrics**: Public Preview（5リージョン限定、2026年4月時点）
- **EventReporter**: Rails 8.1で初登場。パフォーマンス問題（PR #56761）やフィルタリング副作用（PR #56837）が報告・修正済み。ただしRails 8.2以降でAPIの破壊的変更の可能性は残る
- **配列型属性**: CloudWatchが配列型属性をサポートしない（Classmethod記事 2026/04/06の実証による報告）。OTel Collector設定で`process.command_args`等の配列属性を削除する必要がある
- **Development段階SDKの利用**: Logs SDK（EventReporter統合）とMetrics SDKはDevelopment段階に依存する。デモ用途として許容するが、API破壊変更によりビルドが壊れる可能性がある

### 3.3 依存関係

- **調査報告書**: `docs/research/rails-event-reporter-otel-cloudwatch.md` — 技術的な判断の根拠
- **OTel Ruby gems**: opentelemetry-sdk, opentelemetry-instrumentation-rails, opentelemetry-exporter-otlp, opentelemetry-logs-sdk, opentelemetry-metrics-sdk
- **OTel Collector**: OTLP HTTP exporter と SigV4認証拡張を含むディストリビューション（CloudWatch OTLPエンドポイントへの送信に使用）

## 4. 用語定義

| 用語 | 説明 |
|------|------|
| Structured Event Reporter | Rails 8.1で導入された構造化イベント報告機構。`Rails.event`でアクセスする |
| EventReporter | Structured Event Reporterの略称。本文書では同義で使用する |
| OTel | OpenTelemetryの略称 |
| OTLP | OpenTelemetry Protocol。テレメトリデータの送受信プロトコル |
| Span | OTel Tracesにおける処理単位。開始時刻と終了時刻を持つ |
| Log Record | OTel Logsにおけるログエントリ |
| OTel Collector | テレメトリデータの受信・処理・転送を行うエージェント。receiver（受信）、processor（処理）、exporter（送信）のパイプラインで構成される |
| receiver | OTel Collectorの受信コンポーネント。本デモではOTLP receiverを使用する |
| exporter | OTel Collectorの送信コンポーネント。バックエンド（CloudWatch等）へテレメトリを転送する |
| X-Ray | AWS X-Ray。分散トレーシングサービス |

## 5. 受け入れ条件

- [ ] Docker Compose upでRails + PostgreSQL + OTel Collectorが起動する
- [ ] 書籍のCRUD操作ができる
- [ ] 注文を作成でき、在庫が減算される
- [ ] 在庫不足時に注文が拒否される
- [ ] 注文一覧画面からステータスを進められる（pending→confirmed→shipped）
- [ ] 注文作成後にバックグラウンドジョブが実行される
- [ ] CloudWatch X-Rayでコントローラー・DB・ビュー・ジョブのSpanが確認できる（バックグラウンドジョブのSpanを含む）
- [ ] 4種のビジネスイベント（`order.created`, `order.status_changed`, `book.viewed`, `inventory.low`）がそれぞれ発行される
- [ ] CloudWatch LogsでEventReporterのイベントがLog Recordとして確認できる
- [ ] CloudWatch MetricsでカスタムメトリクスのCounterとHistogramが確認できる
- [ ] EventReporterのイベントにtrace_id/span_idが含まれ、CloudWatch上でトレースとの関連付けが��能

## 6. 対象外（スコープ外）

- ユーザー認証・認可
- フロントエンドの装飾（デフォルトのRails scaffold UIで十分）
- 本番環境向けのパフォーマンスチューニング
- OTel Collectorの高可用性構成
- ローカルバックエンド（Jaeger, Zipkin等）への対応
- Datadog, New Relic等の他APMバックエンドへの対応

---

## 改訂履歴

| バージョン | 日付 | 変更内容 |
|------------|------|----------|
| 1.0 | 2026/04/12 | 初版作成 |
| 1.1 | 2026/04/12 | 自動品質検証の結果を反映 |
| 1.2 | 2026/04/12 | EventReporter統合をLogs API方式（パターンB）のみに変更 |
