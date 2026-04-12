# Rails 8.1 Structured Event Reporter + OpenTelemetry + CloudWatch 統合調査報告書

**作成日**: 2026/04/12
**ステータス**: Draft

## 概要

### 調査の背景

2025年10月にリリースされたRails 8.1で、Shopify発の構造化イベント報告機構「Structured Event Reporter」（`Rails.event`）が導入された。一方、CloudWatchが2026年4月時点でOTLP（OpenTelemetry Protocol）経由のTraces・Logs・Metricsの3シグナル受信に対応し、ベンダー固有のエージェントに依存せずOTel標準パイプラインでCloudWatchにテレメトリを送信可能になった（[Classmethod記事, 2026/04/06](https://dev.classmethod.jp/articles/cloudwatch-open-telemetry-metrics/)）。

この2つの動向が重なることで、Rails 8.1アプリケーションからOTel Collector経由でCloudWatchに構造化テレメトリを送信する完全なobservabilityスタックの構築が現実的な選択肢となった。本調査はその統合の技術的実現性、制約、推奨パターンを明らかにする。

### 調査の目的

1. Structured Event Reporterの設計・仕組み・APIを理解する
2. OpenTelemetry Ruby SDKとの統合アーキテクチャを明らかにする
3. 既存のOTel計装gem群との関係性・違いを整理する
4. CloudWatch OTLP対応を踏まえた実装パターンとデモアプリ構成を検討する

本調査はデモアプリ構築と技術記事執筆の基盤とすることを想定している。

### 調査範囲

- **対象**: Rails 8.1 Structured Event Reporter、OpenTelemetry Ruby SDK/計装gem、CloudWatch OTLPエンドポイント
- **対象外**: Datadog・New Relic等の他APMバックエンド、Rails以外のRubyフレームワーク、OTel Collectorの運用設計の詳細

## 調査内容

### 調査対象

- Rails 8.1 `ActiveSupport::EventReporter`（PR #55334、PR #55690）
- OpenTelemetry Ruby SDK（opentelemetry-ruby, opentelemetry-ruby-contrib）
- CloudWatch OTLP Metrics/Logs/Tracesエンドポイント
- OTel仕様のSpan Events非推奨化（OTEP 4430）

### 調査方法

- Railsソースコード・PR・Issueの分析（GitHub rails/rails）
- OpenTelemetry Ruby SDK・contribリポジトリのIssue・PR調査
- 公式ドキュメント・リリースノート・CHANGELOGの確認
- 技術記事・カンファレンス発表の収集（英語・日本語）
- 批判的情報（limitation、problem、criticism）の意図的な収集

## 調査結果

### 1. Rails 8.1 Structured Event Reporter

#### 1.1 導入経緯

DHHが2023年12月にIssue [#50452](https://github.com/rails/rails/issues/50452)「Add structured logging next to developer logging」を起票した。Shopifyと37signalsの両社が社内で構造化ロギングを長年使用しており、そこから共通基盤を抽出するという方針が示された。

Adrianna Chang（Shopify, Staff Software Engineer）がPR [#55334](https://github.com/rails/rails/pull/55334)として実装し、2025年8月にマージされた。Rails 8.1.0（[2025年10月22日リリース](https://rubyonrails.org/2025/10/22/rails-8-1)）に含まれている。

#### 1.2 設計意図

既存の`Rails.logger`は人間可読なログ出力に優れるが、オブザーバビリティプラットフォームによるパースには不向きである。`Rails.event`は以下を目的として設計された（[PR #55334](https://github.com/rails/rails/pull/55334)）:

- 構造化データとしてのイベント発行（名前付き、型付きペイロード、タグ、コンテキスト）
- イベント発行とイベント消費の責務分離（Subscriberパターン）
- `ActiveSupport::Notifications`との補完関係（競合ではない）

**AS::Nとの明確な棲み分け**: AS::Nはインストルメンテーション（`instrument`ブロックによるstart/finish、duration計測）向け。`Rails.event`はpoint-in-timeのリッチなコンテキスト付きイベント発行向け（[PR #55334 レビュー議論](https://github.com/rails/rails/pull/55334)）。

#### 1.3 コアAPI

```ruby
# イベント発行
Rails.event.notify("user.signup", user_id: 123, email: "user@example.com")

# タグ付きイベント（ネスト可能、Fiberローカルで継承）
Rails.event.tagged("checkout") do
  Rails.event.notify("checkout.started", cart_id: @cart.id)
end

# コンテキスト設定（リクエスト/ジョブスコープ）
Rails.event.set_context(request_id: request.request_id, user_id: current_user&.id)

# デバッグモード
Rails.event.with_debug do
  Rails.event.debug("sql.query", sql: "SELECT * FROM users")
end

# Subscriber登録
Rails.event.subscribe(MySubscriber.new)
```

([ActiveSupport::EventReporter API doc](https://edgeapi.rubyonrails.org/classes/ActiveSupport/EventReporter.html))

#### 1.4 イベント構造体

各イベントには以下のメタデータが自動付与される:

| フィールド | 型 | 説明 |
|---|---|---|
| `name` | String | イベント識別子 |
| `payload` | Hash / Object | カスタムデータ |
| `tags` | Hash | ドメインコンテキスト（ネスト可能） |
| `context` | Hash | リクエスト/ジョブメタデータ |
| `timestamp` | Integer | ナノ秒精度タイムスタンプ |
| `source_location` | Hash | ファイルパス、行番号、メソッド名 |

([PR #55334 差分](https://github.com/rails/rails/pull/55334/files))

#### 1.5 実装上の特徴

- **Fiber分離**: タグとコンテキストは`Fiber`ローカルストレージに保存。`ActiveSupport::IsolatedExecutionState`ではなくFiber storageを直接使用している。Shopifyの要件としてFiber単位のコンテキスト分離が必要だったため（[PR #55334 レビュー](https://github.com/rails/rails/pull/55334)）
- **自動フィルタリング**: Hash payloadは`Rails.application.filter_parameters`に基づいて自動フィルタされる
- **エラーハンドリング**: Subscriberのエラーは`ActiveSupport.error_reporter`に報告される（`raise_on_error: true`で例外送出も可能）
- **エンコーダ**: JSON、MessagePackに対応。イベントオブジェクト使用時は`to_h`の実装が必要

#### 1.6 StructuredEventSubscriber（AS::Nブリッジ）

PR [#55690](https://github.com/rails/rails/pull/55690)（gmcgibbon / Shopify, 2025年9月マージ）で導入された`ActiveSupport::StructuredEventSubscriber`は、既存のAS::Nイベントを消費し、`Rails.event`経由で構造化イベントとして再発行するブリッジである。

以下のフレームワークライブラリにStructuredEventSubscriberが追加された（[PR #55690](https://github.com/rails/rails/pull/55690)本文より）:
- Action Pack（ActionController, ActionDispatch, ActionViewを含む）、ActionMailer
- ActiveJob, ActiveRecord, ActiveStorage

([PR #55690](https://github.com/rails/rails/pull/55690))

#### 1.7 既知の問題点・批判

**パフォーマンス問題**: StructuredEventSubscriber導入後、Subscriberの有無に関わらずペイロード構築とフィルタリングのコストが常に発生する問題が報告された。byroot（Jean Boussier）が「フィルタリングロジックはASNから移植されたものだが、EventReporterではペイロード構築を省略できないため、機能として意味をなさない」と指摘している（[PR #56761](https://github.com/rails/rails/pull/56761)）。

**ペイロードフィルタリングの副作用**: SQLクエリ名などの内部メタデータまでセンシティブパラメータフィルタリングの対象になる問題（[PR #56837](https://github.com/rails/rails/pull/56837)）。

**ログレベルの欠如**: palkan（Vladimir Dementyev）がPRレビューで「`notify`と`debug`の2段階しかなく、info/warn/errorに相当する仕組みがないのは構造化ロギングの解決策として不十分」と指摘した。Rafael Francaは「テレメトリ/オブザーバビリティが主目的であり、汎用ロギングの代替ではない」と回答している（[PR #55334 レビュー](https://github.com/rails/rails/pull/55334)）。

**ビジネスイベント用途との混同**: PR説明の「business events」という表現が、イベント駆動アーキテクチャやDomain Eventsとしての利用を期待させるが、配信保証がなく、テレメトリ/オブザーバビリティ目的に限定されると明確化されている（[PR #55334 レビュー](https://github.com/rails/rails/pull/55334)）。

**AS::Nとの二重パイプライン**: StructuredEventSubscriberがAS::NイベントをEventReporterに再発行する構造のため、アーキテクチャの複雑さが増している。将来的にはLogSubscriberとの統合が計画されているが、現時点では両方が並存する。

---

### 2. OpenTelemetry Ruby SDK

#### 2.1 アーキテクチャ

OTel Ruby SDKは2層構造をとる（[opentelemetry-ruby SDK README](https://github.com/open-telemetry/opentelemetry-ruby/blob/main/sdk/README.md)）:

- **opentelemetry-api**: インターフェース定義。ライブラリが依存すべき層
- **opentelemetry-sdk**: 具体的実装。アプリケーションが利用する層

テレメトリパイプライン:

```
Application Code
  → Tracer（TracerProviderから取得）
    → Span生成
      → SpanProcessor（on_start / on_finish）
        → Exporter（OTLP, Console等）
          → OTel Collector → Backend
```

#### 2.2 シグナル別成熟度

| シグナル | Ruby SDKステータス | 備考 |
|---|---|---|
| Traces | **Stable** | 実用レベル |
| Metrics | Development | opentelemetry-metrics-sdk v0.13.0 |
| Logs | Development | opentelemetry-logs-sdk v0.5.0（[RubyGems](https://rubygems.org/gems/opentelemetry-logs-sdk)、2026/04/07リリース） |

([Ruby | OpenTelemetry](https://opentelemetry.io/docs/languages/ruby/))

参考として、Python・Go・JavaのSDKではMetrics/LogsがStableまたはそれに近い段階にある一方、Ruby SDKはいずれもDevelopment段階にとどまっている（[OTel Language APIs & SDKs](https://opentelemetry.io/docs/languages/)）。

#### 2.3 opentelemetry-instrumentation-rails gemの仕組み

`opentelemetry-instrumentation-rails`はメタgemであり、以下のサブ計装を束ねている（[opentelemetry-ruby-contrib/instrumentation/rails](https://github.com/open-telemetry/opentelemetry-ruby-contrib/tree/main/instrumentation/rails)）:

| コンポーネント | 計装手法 |
|---|---|
| Action Pack | ActiveSupport::Notifications（`process_action.action_controller`） |
| Action View | ActiveSupport::Notifications（`render_template.action_view`等） |
| Active Record | **モンキーパッチ**（module prepend）+ 一部AS::N |
| Active Job | **モンキーパッチ**（メタデータシリアライゼーション）+ AS::N |

計装手法が統一されておらず、AS::Nへの完全移行を目指すIssue [#218](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/218) が存在するが、2026年4月時点で**未完了（Open）**。Active RecordやActive Jobでは通知イベントだけでは十分な情報が取れないため、モンキーパッチが残存している。

#### 2.4 Structured Event Reporter対応状況

**2026年4月時点で、opentelemetry-ruby-contribにStructured Event Reporter対応のIssue・PRは存在しない。** 「structured event」「event reporter」「Rails.event」でリポジトリ内を検索したが該当なし（[opentelemetry-ruby-contrib Issues](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues)）。

#### 2.5 既知のパフォーマンス問題

100%サンプリング時にPostgreSQL操作で約300倍の遅延（100ms→30秒）が報告された事例がある。原因として`BatchSpanProcessor`のMutex競合とPumaのマルチスレッド環境との相互作用が疑われたが、根本原因は確定しないまま"NOT_PLANNED"としてクローズされた。測定環境の詳細（Rubyバージョン、Pumaワーカー/スレッド数等）はIssue内で十分に記載されていない。サンプリングレートの調整、不要な計装の無効化、OTLP Exporterのチューニングが一般的な対策として挙げられている（[Issue #1508](https://github.com/open-telemetry/opentelemetry-ruby/issues/1508)）。

---

### 3. OTel仕様: Span Events API非推奨化

#### 3.1 概要

OpenTelemetryは2026年にSpan Events APIの非推奨化を発表した（[ブログ記事](https://opentelemetry.io/blog/2026/deprecating-span-events/)）。仕様変更の詳細はOTEP 4430（[Span Event API Deprecation Plan](https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/4430-span-event-api-deprecation-plan.md)）に記載されている。

#### 3.2 非推奨対象と代替

- **非推奨対象**: `Span.AddEvent`、`Span.RecordException`のAPI
- **代替**: Logs API経由のイベント送信
- OTelの方針: 「events are logs with names」（イベントとは名前付きのログである）

**重要な区別**: 非推奨化されるのはSpan Event APIであり、Span Events自体がOTLPプロトコルから削除されるわけではない。Logs API経由で送信したイベントがSpan Eventsとして表示される仕組みは維持される（[OTEP 4430](https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/4430-span-event-api-deprecation-plan.md)）。

#### 3.3 Ruby SDKへの影響

Ruby SDKのLogs APIはDevelopment段階（v0.5.0）であるため、Span Event APIが非推奨化されても移行先が安定版として提供されていない。現行の`span.add_event`は引き続き動作するが、中長期的には`opentelemetry-logs-sdk`の安定化を注視する必要がある。

---

### 4. CloudWatch OTLP対応

#### 4.1 対応状況

| シグナル | エンドポイント | ステータス |
|---|---|---|
| Traces | `xray.{Region}.amazonaws.com/v1/traces` | GA |
| Logs | `logs.{Region}.amazonaws.com/v1/logs` | GA |
| Metrics | `monitoring.{Region}.amazonaws.com/v1/metrics` | **Public Preview** |

([AWS公式ドキュメント](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-OTLPEndpoint.html)、[Classmethod記事, 2026/04/06](https://dev.classmethod.jp/articles/cloudwatch-open-telemetry-metrics/))

#### 4.2 新機能

- PromQL対応（Query Studioエディタ）
- PromQLによるアラーム定義
- OTel標準形式でのAWS提供メトリクス処理

#### 4.3 対応リージョン（Metrics Public Preview）

us-east-1、us-west-2、ap-southeast-2、ap-southeast-1、eu-west-1

#### 4.4 制約事項

配列型属性がCloudWatchでサポートされない。OTel Collectorの設定時に`process.command_args`などの配列属性を削除処理する必要がある（[Classmethod記事](https://dev.classmethod.jp/articles/cloudwatch-open-telemetry-metrics/)）。

---

### 5. APMツールの対応状況

| ツール | Structured Event Reporter対応 | 根拠 |
|---|---|---|
| OpenTelemetry | 未対応（Issue/PRなし） | [opentelemetry-ruby-contrib Issues](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues)検索結果 |
| New Relic | 未対応（対応検討中） | [Issue #2765](https://github.com/newrelic/newrelic-ruby-agent/issues/2765) Open |
| Datadog | 不明（公式情報なし） | 公式ドキュメントで確認できず |

---

### 6. 技術記事・コミュニティリソース

#### 英語記事

- [Rails 8.1 Introduces Structured Event Reporting - Saeloun Blog](https://blog.saeloun.com/2025/12/18/rails-introduces-structured-event-reporting/) — API詳細解説
- [Structured Logging in Rails 8.1 - oxyconit](https://blog.oxyconit.com/structured-logging-in-rails-8-1-with-rails-event/) — 実用的コード例
- [Rails 8.1 New API: Rails.event.notify - FastRuby.io](https://www.fastruby.io/blog/rails-event-notify.html) — APMツール統合概要

#### カンファレンス発表

- Adrianna Chang "From Chaos to Clarity: Structured Event Reporting in Rails" — Rails World 2025（[Speaker Deck](https://speakerdeck.com/adriannachang/from-chaos-to-clarity-structured-event-reporting-in-rails)）

#### 日本語記事

EventReporterとOpenTelemetryの組み合わせに関する日本語記事は、調査時点で発見できなかった。

## 分析・考察

### 主要な発見

**1. EventReporterとOTel計装は競合ではなく補完関係にある**

| 仕組み | 対象 | イベント特性 | OTelとの関係 |
|---|---|---|---|
| AS::N + OTel gem | フレームワーク内部操作（SQL、コントローラ、ビュー等） | 期間あり（start/finish） | 既存gemが対応済み |
| EventReporter | アプリケーション固有のビジネスイベント | 瞬間的（point-in-time） | 公式統合なし。自作が必要 |

AS::Nの`instrument`ブロックは期間を持つため、OTel Spanに自然にマッピングできる。EventReporterのイベントは瞬間的であり、Spanへのマッピングは意味的に不正確（duration=0のSpanになる）。

**2. OTel概念への適切なマッピング**

| Railsの仕組み | イベント特性 | 適切なOTelマッピング | 理由 |
|---|---|---|---|
| AS::N `instrument`ブロック | 期間あり | **Span** | 処理の開始・終了を計測する概念と一致 |
| EventReporter `notify` | 瞬間的 | **Log Record**（Logs API） | point-in-timeイベントの記録として意味的に正確 |
| EventReporter `notify` | 瞬間的 | ~~Span Event~~ | OTEP 4430により非推奨化予定 |
| EventReporter `notify` | 瞬間的 | ~~Span（duration=0）~~ | Spanの意味に反する |

**3. 公式統合が存在しない空白地帯**

OTelコミュニティ側にもRails側にもAPMベンダー側にも、EventReporter→OTelの公式統合は存在しない。New Relicが対応検討中（[Issue #2765](https://github.com/newrelic/newrelic-ruby-agent/issues/2765)）という状況に留まる。

### 統合アーキテクチャ

CloudWatch OTLP対応を踏まえた全体構成:

```
Rails 8.1 アプリケーション
  │
  ├─ [Traces] OTel instrumentation gems
  │     ActiveSupport::Notifications経由
  │     → OTel SDK (BatchSpanProcessor)
  │         → OTLP Exporter ─────────────────┐
  │                                           │
  ├─ [Logs] EventReporter                     │
  │     → カスタムSubscriber                   │
  │         → (後述の3パターンのいずれか) ──┐  │
  │                                        │  │
  └─ [Metrics] OTel SDK Metrics            │  │
        → OTLP Exporter ──────────────┐   │  │
                                       ▼   ▼  ▼
                                  OTel Collector
                                       │   │  │
           monitoring.{Region}  ←──────┘   │  │
           /v1/metrics (Preview)           │  │
           logs.{Region}  ←────────────────┘  │
           /v1/logs (GA)                      │
           xray.{Region}  ←──────────────────┘
           /v1/traces (GA)
```

### 統合パターンの比較

EventReporterのイベントをOTelパイプラインに統合する3パターン:

#### パターンA: Span Event方式

```ruby
class OTelSpanEventSubscriber
  def emit(event)
    current_span = OpenTelemetry::Trace.current_span
    return if current_span == OpenTelemetry::Trace::Span::INVALID

    attributes = event[:payload].transform_keys(&:to_s).transform_values(&:to_s)
    event[:tags].each { |k, v| attributes["tag.#{k}"] = v.to_s }
    current_span.add_event(event[:name], attributes: attributes)
  end
end
```

| 観点 | 評価 |
|---|---|
| 実装難易度 | 低。Traces APIはStable |
| 意味的正確性 | 中。point-in-timeイベントをSpanに紐づける点は妥当 |
| 将来性 | **低。OTEP 4430によりSpan Event APIが非推奨化予定だが、Ruby SDKでの実施時期は未定。移行猶予はあるものの、新規設計での採用は非推奨** |
| CloudWatch連携 | Traces経由でX-Rayに送信。CloudWatch側でSpan Eventとして表示可能 |

#### パターンB: Logs API方式

```ruby
# 概念実装。opentelemetry-logs-sdk v0.5.0（Development段階）のAPIに基づく。
# 動作未検証。APIが将来変更される可能性がある。
class OTelLogSubscriber
  def initialize
    @logger = OpenTelemetry.logger_provider.logger("rails.event")
  end

  def emit(event)
    @logger.on_emit(
      body: event[:payload],
      severity_text: "INFO",
      attributes: event[:tags].merge(event[:context]).transform_keys(&:to_s),
      timestamp: event[:timestamp]
    )
  end
end
```

| 観点 | 評価 |
|---|---|
| 実装難易度 | 中。Logs APIの理解が必要 |
| 意味的正確性 | **高（仕様上の評価）。OTel仕様の方向性（events are logs with names）と一致。ただしRuby SDKでの実装品質は未検証** |
| 将来性 | **高。OTEP 4430の推奨パスに合致** |
| CloudWatch連携 | Logs経由でCloudWatch Logsに送信（GA） |
| リスク | **Ruby opentelemetry-logs-sdk v0.5.0はDevelopment段階。API破壊変更のリスクあり** |

#### パターンC: 構造化JSONログ + OTel Collector方式

```ruby
class JsonLogSubscriber
  def emit(event)
    span_context = OpenTelemetry::Trace.current_span.context
    record = {
      timestamp: event[:timestamp],
      severity: "INFO",
      body: event[:name],
      attributes: event[:payload].merge(event[:tags]).merge(event[:context]),
      resource: { "service.name" => Rails.application.class.module_parent_name },
      trace_id: span_context.hex_trace_id,
      span_id: span_context.hex_span_id
    }
    $stdout.puts JSON.dump(record)
  end
end
```

OTel Collectorの`filelog` receiverで収集し、OTLPパイプラインに統合。

| 観点 | 評価 |
|---|---|
| 実装難易度 | 中。Collector設定の知識が必要 |
| 意味的正確性 | 高。ログレコードとして正確 |
| 将来性 | **高。安定した技術のみに依存** |
| CloudWatch連携 | Collector経由でCloudWatch Logsに送信 |
| リスク | trace_id/span_idの明示的埋め込みが必要。Collectorのfilelog receiver設定が追加で必要。JSON出力フォーマットとパーサー設定の不一致によるログロスのリスクがある |

### パターン比較総括

| 評価項目 | A: Span Event | B: Logs API | C: JSON + Collector |
|---|---|---|---|
| 実装の手軽さ | 高 | 中 | 中 |
| OTel SDK依存度 | Traces APIのみ | Traces + Logs API | Traces APIのみ |
| 将来の安定性 | 低（非推奨化予定。移行猶予はあり） | 中（SDK未成熟） | 高（安定技術の組み合わせ。ただしCollector設定の保守が必要） |
| Span関連付け | 自動 | SDK内部で自動 | 手動（trace_id埋め込み） |
| CloudWatch対応 | X-Ray経由 | Logs経由（GA） | Logs経由（GA） |

### シグナル別の成熟度マトリクス

| シグナル | OTel Ruby SDK | CloudWatch OTLP | Rails側の仕組み | 総合判定 |
|---|---|---|---|---|
| Traces | Stable | GA | AS::N + OTel gem（実績あり） | **実用可能** |
| Logs | Development (v0.5) | GA | EventReporter（8.1新機能） | **実験段階** |
| Metrics | Development | Public Preview | OTel SDK直接 | **検証段階** |

### リスクと制約

**1. 二重パイプラインの複雑さ**

StructuredEventSubscriberがAS::NイベントをEventReporterに再発行するため、OTelがAS::Nを直接購読し、かつEventReporterも購読すると、同一フレームワークイベントが2経路で処理される可能性がある。ビジネスイベント（アプリケーションが`Rails.event.notify`で発行するもの）のみをOTel Subscriberで処理するフィルタリングが必要。

**2. パフォーマンスの累積リスク**

OTel計装のパフォーマンス問題（[Issue #1508](https://github.com/open-telemetry/opentelemetry-ruby/issues/1508): PostgreSQL 300倍遅延報告）とEventReporterのSubscriber処理は、同一リクエストサイクルで同期実行される構造にある。両者を併用した場合のパフォーマンス影響は未検証だが、処理が累積する可能性がある。本番環境ではサンプリングレートの調整とBatchSpanProcessorの適切な設定が必須と考えられる。

**3. EventReporter APIの安定性リスク**

EventReporterはRails 8.1で初登場であり、既にパフォーマンス問題（[PR #56761](https://github.com/rails/rails/pull/56761)）やフィルタリングの副作用（[PR #56837](https://github.com/rails/rails/pull/56837)）が報告されている。Rails 8.2以降でAPIの破壊的変更が発生する可能性は排除できない。

**4. OTel Ruby Logs/Metrics SDKの未成熟**

パターンBを採用する場合、opentelemetry-logs-sdk（v0.5.0, Development）に依存する。API破壊変更のリスクがある。Metricsも同様にDevelopment段階。

**5. CloudWatch固有の制約**

- 配列型属性がサポートされない（Collector設定で削除処理が必要）
- Metrics OTLPは5リージョンでのPublic Previewに限定（2026年4月時点）
- PromQLサポートは新機能であり、運用実績が限られる

**6. 日本語情報の不足**

EventReporterとOTelの組み合わせに関する日本語記事は調査時点で発見できなかった。トラブルシューティング時に参照できる情報が英語に限られる。

## 結論・推奨事項

### 結論

Rails 8.1 Structured Event ReporterとOpenTelemetry、CloudWatchの統合は技術的に実現可能だが、3つの技術要素がそれぞれ異なる成熟段階にある点を認識する必要がある。

- **Traces**: 即座に実用可能。既存のOTel計装gem + CloudWatch X-Rayエンドポイント（双方Stable/GA）
- **Logs（EventReporter → CloudWatch Logs）**: 実現可能だが統合は自作が必要。パターンによって安定性と将来性のトレードオフがある
- **Metrics**: 双方未成熟（Ruby SDK Development + CloudWatch Preview）。デモ・検証目的に限定すべき

公式統合ライブラリは存在せず、OTelコミュニティ・APMベンダーともに対応は未着手または検討段階にある。

### 推奨事項

**1. デモアプリでは3パターンすべてを実装・比較する**
- 理由: 学習目的と技術記事執筆が目的であり、各パターンのトレードオフを実体験として把握することに価値がある
- 期待効果: 読者が自身のユースケースに応じてパターンを選択できる判断材料を提供できる

**2. フレームワーク計装は既存OTel gemを使用する**
- 理由: `opentelemetry-instrumentation-rails`（`use_all`）によるフレームワーク計装はStableであり、自作する理由がない
- 期待効果: SQL、コントローラー、ビュー等の標準的なトレース計装を即座に利用可能

**3. EventReporterのOTel統合は薄いアダプター層にとどめる**
- 理由: 公式統合が将来提供される可能性があり、密結合な実装は移行コストを増大させる
- 期待効果: 公式統合が提供された際にアダプター層の差し替えのみで移行可能

**4. 本番環境への適用判断はパターンに応じて以下を確認する**
- パターンB（Logs API方式）: opentelemetry-logs-sdk が Stable（1.0）に到達するまで保留を推奨
- パターンC（JSON + Collector方式）: Logs SDKに依存しないため、EventReporter API自体の安定確認のみで適用可能
- 共通: Rails 8.2以降でEventReporter APIが安定する（破壊的変更がない）ことを確認
- Metricsを利用する場合: CloudWatch Metrics OTLPがGAになるまで待つことを推奨

### 次のアクション

- [ ] デモアプリのプロジェクト構成を決定する（Rails 8.1 + Docker Compose + OTel Collector + CloudWatch）
- [ ] Tracesの基本パイプライン（OTel gem → Collector → X-Ray）を構築する
- [ ] EventReporter → OTel統合の3パターンを実装する
- [ ] 各パターンの動作確認と比較検証を行う
- [ ] 技術記事のアウトラインを作成する

## 参考資料

### Rails Structured Event Reporter

- [PR #55334: Structured Event Reporting in Rails](https://github.com/rails/rails/pull/55334)
- [PR #55690: Structured event subscribers](https://github.com/rails/rails/pull/55690)
- [Issue #50452: Add structured logging next to developer logging](https://github.com/rails/rails/issues/50452)
- [Rails 8.1 リリースアナウンス](https://rubyonrails.org/2025/10/22/rails-8-1)
- [ActiveSupport::EventReporter API doc](https://edgeapi.rubyonrails.org/classes/ActiveSupport/EventReporter.html)
- [Adrianna Chang - Speaker Deck (Rails World 2025)](https://speakerdeck.com/adriannachang/from-chaos-to-clarity-structured-event-reporting-in-rails)
- [Saeloun Blog: Rails 8.1 Introduces Structured Event Reporting](https://blog.saeloun.com/2025/12/18/rails-introduces-structured-event-reporting/)
- [PR #56761: パフォーマンス問題](https://github.com/rails/rails/pull/56761)
- [PR #56837: フィルタリング副作用](https://github.com/rails/rails/pull/56837)

### OpenTelemetry

- [OpenTelemetry Ruby](https://opentelemetry.io/docs/languages/ruby/)
- [opentelemetry-ruby SDK](https://github.com/open-telemetry/opentelemetry-ruby)
- [opentelemetry-ruby-contrib](https://github.com/open-telemetry/opentelemetry-ruby-contrib)
- [Issue #218: Migrate Rails instrumentation to AS::N only](https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues/218)
- [Issue #1508: Performance impact on Ruby on Rails](https://github.com/open-telemetry/opentelemetry-ruby/issues/1508)
- [OTEP 4430: Span Event API Deprecation Plan](https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/4430-span-event-api-deprecation-plan.md)
- [ブログ: Deprecating Span Events](https://opentelemetry.io/blog/2026/deprecating-span-events/)
- [opentelemetry-logs-sdk](https://rubygems.org/gems/opentelemetry-logs-sdk)
- [OTel Language APIs & SDKs](https://opentelemetry.io/docs/languages/)

### CloudWatch

- [AWS公式: CloudWatch OTLPエンドポイント](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-OTLPEndpoint.html)
- [AWS公式: CloudWatch OpenTelemetry Metricsアナウンス](https://aws.amazon.com/about-aws/whats-new/2026/04/amazon-cloudwatch-opentelemetry-metrics/)
- [CloudWatch OpenTelemetry メトリクス対応（Classmethod, 2026/04/06）](https://dev.classmethod.jp/articles/cloudwatch-open-telemetry-metrics/)

### APMツール

- [New Relic: Rails 8.1 structured logging対応 Issue #2765](https://github.com/newrelic/newrelic-ruby-agent/issues/2765)
