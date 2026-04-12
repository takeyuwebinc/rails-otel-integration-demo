# Rails 8.1 OTel統合デモアプリ

Rails 8.1 Structured Event Reporter（`Rails.event`）+ OpenTelemetry + CloudWatch の統合デモ。

OTelの3シグナル（Traces, Logs, Metrics）を同時稼働させ、CloudWatchで確認できる構成を実現する。

## 構成

```
Rails 8.1 アプリ ──OTLP──▶ OTel Collector ──SigV4──▶ CloudWatch
  ├─ Traces（自動計装）                          ├─ X-Ray（Traces）
  ├─ Logs（EventReporter→OTel Logs API）         ├─ CloudWatch Logs（Logs）
  └─ Metrics（Counter/Histogram）                └─ CloudWatch Metrics（Metrics）
```

| コンテナ | 役割 | ポート |
|---------|------|-------|
| web | Rails アプリ + OTel SDK | 3000 |
| db | PostgreSQL | 5432 |
| otel-collector | ADOT Collector | 4317（gRPC）, 4318（HTTP） |

## 前提条件

- Docker, Docker Compose
- AWSアカウント（CloudWatchへの送信に必要）

## AWS設定

### 必要なIAM権限

OTel CollectorがCloudWatchにテレメトリを送信するため、以下の権限を持つIAMユーザーまたはロールが必要。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:UpdateTraceSegmentDestination",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
```

### X-Ray OTLP取り込みの設定

X-RayのOTLPエンドポイント経由でトレースを送信するには、トレースの保存先をCloudWatch Logsに設定する必要がある。

まず、X-Rayサービスが`aws/spans`ロググループに書き込めるよう、CloudWatch Logsのリソースポリシーを設定する。`ACCOUNT_ID`と`REGION`は環境に合わせて置き換える。

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

aws logs put-resource-policy \
  --policy-name XRayLogAccess \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"TransactionSearchXRayAccess\",
        \"Effect\": \"Allow\",
        \"Principal\": {
          \"Service\": \"xray.amazonaws.com\"
        },
        \"Action\": \"logs:PutLogEvents\",
        \"Resource\": [
          \"arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:aws/spans:*\",
          \"arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/application-signals/data:*\"
        ],
        \"Condition\": {
          \"ArnLike\": {
            \"aws:SourceArn\": \"arn:aws:xray:${REGION}:${ACCOUNT_ID}:*\"
          },
          \"StringEquals\": {
            \"aws:SourceAccount\": \"${ACCOUNT_ID}\"
          }
        }
      }
    ]
  }"
```

次に、トレースの保存先をCloudWatch Logsに切り替える。

```bash
aws xray update-trace-segment-destination --destination CloudWatchLogs
```

これらの設定はリージョンごとに1回だけ実行すればよい。

参考: [Enable transaction search - Amazon CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Enable-TransactionSearch.html)

### リージョン

CloudWatch Metrics OTLPエンドポイントは以下の5リージョンでPublic Preview（2026年4月時点）。

- us-east-1, us-west-2, ap-southeast-1, ap-southeast-2, eu-west-1

Traces（X-Ray）とLogs（CloudWatch Logs）のOTLPエンドポイントはGA済みで、他のリージョンでも利用可能。3シグナル全てを動作させるには上記5リージョンのいずれかを選択する。

### 認証情報の設定

`.env.example`をコピーして`.env`を作成し、AWSの認証情報を記入する。

```bash
cp .env.example .env
```

```bash
# .env
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=ap-southeast-1
```

Docker Composeは`.env`ファイルを自動的に読み込む。

## 起動

```bash
# コンテナ起動
docker compose up -d

# DB作成・マイグレーション
docker compose exec web bin/rails db:create db:migrate

# シードデータ投入
docker compose exec web bin/rails db:seed
```

http://localhost:3000 でアプリにアクセスできる。

## テスト

```bash
docker compose run --rm \
  -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://postgres:password@db:5432/bookstore_otel_demo_test \
  web bin/rails db:create db:migrate test
```

## 操作とCloudWatch動作確認

### 1. Traces（X-Ray）の確認

任意のページ操作でTraceが生成される。

**操作**: ブラウザで http://localhost:3000/books にアクセス

**CloudWatch確認手順**:
1. AWSコンソール → CloudWatch → X-Ray traces → Traces
2. Service Map または Trace一覧にて `bookstore-otel-demo` サービスのSpanを確認
3. 各TraceにはController（Action Pack）、DBクエリ（Active Record）、View（Action View）のSpanがネストされている

### 2. Logs（CloudWatch Logs）の確認 — EventReporterイベント

4種のビジネスイベントがLog Recordとして送信される。

#### book.viewed イベント

**操作**: 書籍の詳細ページを開く（例: http://localhost:3000/books/1）

**ペイロード**: `book_id`, `title`

#### order.created + inventory.low イベント

**操作**: 注文を作成する

1. http://localhost:3000/orders/new を開く
2. 書籍と数量を選択して「注文を確定する」をクリック

**ペイロード**:
- `order.created`: `order_number`, `book_id`, `quantity`, `total_amount`
- `inventory.low`（残在庫5以下の場合のみ）: `book_id`, `remaining_stock`

#### order.status_changed イベント

**操作**: 注文一覧からステータスを進める

1. http://localhost:3000/orders を開く
2. pending状態の注文の「pending → confirmed」ボタンをクリック

**ペイロード**: `order_number`, `from_status`, `to_status`

**CloudWatch確認手順**:
1. AWSコンソール → CloudWatch → Logs → Log groups
2. OTel Collectorが自動作成するロググループを確認（`/aws/otel` や サービス名ベースのグループ）
3. Log eventsを開き、bodyフィールドにイベント名（例: `order.created`）、attributesにペイロードが含まれていることを確認
4. 各Log Recordの`trace_id`/`span_id`がX-RayのTrace IDと一致することを確認 — これによりTraceとLogの関連付けが機能していることがわかる

### 3. Metrics（CloudWatch Metrics）の確認

注文作成時にメトリクスが記録される。

**操作**: 注文を複数回作成する（異なる書籍・数量で）

**CloudWatch確認手順**:
1. AWSコンソール → CloudWatch → Metrics → All metrics
2. カスタム名前空間を探す（OTel Collectorのデフォルト名前空間）
3. 以下のメトリクスを確認:
   - `orders.created`（Counter） — 注文ごとに1ずつ増加
   - `orders.amount`（Histogram） — 注文金額の分布

### TraceとLogの関連付け確認

EventReporterイベントのLog RecordにはOTel SDKが自動的に`trace_id`と`span_id`を付与する。

1. CloudWatch Logsでイベントの`trace_id`をコピー
2. X-Ray TracesでそのTrace IDを検索
3. 該当リクエストのTrace配下にController Spanが存在し、そのSpan内で発行されたイベントであることが確認できる

## OTelシグナル一覧

### Traces（自動計装）

`opentelemetry-instrumentation-all`（`use_all`）による自動計装。

| Span | 計装元 |
|------|-------|
| HTTPリクエスト処理 | Action Pack |
| DBクエリ | Active Record / PG |
| ビューレンダリング | Action View |
| メール送信 | Action Mailer |
| バックグラウンドジョブ | Active Job |

### Logs（EventReporter → OTel Logs API）

| イベント | タイミング | ペイロード |
|---------|----------|-----------|
| `book.viewed` | 書籍詳細表示 | book_id, title |
| `order.created` | 注文作成 | order_number, book_id, quantity, total_amount |
| `order.status_changed` | ステータス変更 | order_number, from_status, to_status |
| `inventory.low` | 在庫5以下 | book_id, remaining_stock |

### Metrics

| メトリクス | 種別 | 単位 | タイミング |
|-----------|------|------|----------|
| `orders.created` | Counter | {orders} | 注文作成時 |
| `orders.amount` | Histogram | JPY | 注文作成時 |

## 技術スタック

- Ruby 4.0.2 / Rails 8.1.3
- PostgreSQL 17
- OpenTelemetry SDK 1.11.0
- OpenTelemetry Logs SDK 0.5.0（Development）
- OpenTelemetry Metrics SDK 0.13.0（Development）
- AWS Distro for OpenTelemetry Collector（ADOT）
