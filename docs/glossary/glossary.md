# Rails 8.1 OTel統合デモアプリ 用語集

**作成日**: 2026年4月12日
**更新日**: 2026年4月12日

## 凡例

| 項目 | 説明 |
|------|------|
| 用語 | 正式な用語名（プロジェクト内で統一して使用する名称） |
| 定義 | 用語の意味を簡潔かつ正確に記述 |
| 別名 | 許容される同義語（正式用語の使用を推奨） |
| 禁止表現 | 混乱を招くため使用を避ける表現 |
| 英語名 | 対応する英語表記（コード上の命名に使用） |
| コンテキスト | この用語が使用される境界づけられたコンテキスト |

## Rails関連

| 用語 | 定義 | 別名 | 禁止表現 | 英語名 | コンテキスト |
|------|------|------|----------|--------|-------------|
| Structured Event Reporter | Rails 8.1で導入された構造化イベント報告機構。`Rails.event`でアクセスし、名前付き・型付きペイロードを持つpoint-in-timeイベントを発行する。テレメトリ/オブザーバビリティが主目的であり、配信保証を持つイベント駆動基盤ではない | EventReporter | 構造化ロガー（汎用ロギングの代替ではないため）、Domain Events（配信保証がないため） | ActiveSupport::EventReporter | 共通 |
| ActiveSupport::Notifications | Railsの内部計装機構。`instrument`ブロックによるstart/finish計測を行い、期間（duration）を持つイベントを発行する。OTel計装gemはこの仕組みを利用してSpanを生成する | AS::N | — | ActiveSupport::Notifications | 共通 |
| StructuredEventSubscriber | AS::Nのイベントを購読し、Structured Event Reporter経由で構造化イベントとして再発行するブリッジ。Action Pack、Active Record、Active Job等のフレームワークライブラリに組み込まれている（PR #55690） | — | — | ActiveSupport::StructuredEventSubscriber | 共通 |
| Subscriber | Structured Event Reporterに登録されるイベント消費者。`emit`メソッドでイベントを受け取り、外部システム（OTelパイプライン等）への転送やログ出力を行う | — | リスナー（ActiveSupport::Notificationsの`subscriber`と混同しやすいが、EventReporterのSubscriberはeventオブジェクトを受け取る点が異なる） | Subscriber | EventReporter統合 |
| ビジネスイベント | アプリケーションコードが`Rails.event.notify`で明示的に発行するドメイン固有のイベント。本デモでは`order.created`、`order.status_changed`、`book.viewed`、`inventory.low`の4種を定義する | アプリケーションイベント | フレームワークイベント（AS::N経由のイベントとは発行元が異なるため区別が必要） | business event | EventReporter統合 |

## OpenTelemetry（OTel）関連

| 用語 | 定義 | 別名 | 禁止表現 | 英語名 | コンテキスト |
|------|------|------|----------|--------|-------------|
| OpenTelemetry | テレメトリデータ（Traces, Logs, Metrics）の生成・収集・送信を標準化するオープンソースのオブザーバビリティフレームワーク。CNCFプロジェクト | OTel | — | OpenTelemetry | 共通 |
| テレメトリ | アプリケーションの動作状態を外部から観測するために収集されるデータの総称。OTelではTraces、Logs、Metricsの3種のシグナルで構成される | テレメトリーデータ | メトリクス（テレメトリの一部であり同義ではない）、ログ（同上） | telemetry | 共通 |
| シグナル | OTelが定義するテレメトリデータの種別。Traces、Logs、Metricsの3種がある。本デモでは3シグナルすべてを同時稼働させる | — | — | signal | 共通 |
| 計装 | アプリケーションコードやフレームワークにテレメトリ収集のためのコードを組み込むこと。OTelでは自動計装（フレームワークレベル）と手動計装（アプリケーションコード）がある | インストルメンテーション | — | instrumentation | 共通 |
| 自動計装 | `opentelemetry-instrumentation-rails`（`use_all`）等のgemにより、アプリケーションコードを変更せずにフレームワークレベルのテレメトリを収集する仕組み。AS::Nへのフックとモンキーパッチの併用で実現されている | — | — | auto-instrumentation | Traces |
| OTLP | OpenTelemetry Protocol。テレメトリデータの送受信に使用する標準プロトコル。gRPCまたはHTTP/protobufで通信する。本デモではアプリケーションからOTel Collectorへの送信、およびOTel CollectorからCloudWatchへの送信に使用する | — | — | OTLP (OpenTelemetry Protocol) | 共通 |
| Trace | 分散システムにおけるリクエストの処理経路全体を表現するデータ構造。複数のSpanで構成される。OTelの3シグナルの1つ | トレース | — | Trace | Traces |
| Span | OTel Tracesにおける処理の単位。開始時刻と終了時刻（duration）を持ち、親子関係でトレースツリーを構成する。コントローラーアクション、DBクエリ、ビューレンダリング等がそれぞれ1つのSpanになる | — | イベント（Span Eventと混同するため）、ログ（Log Recordと異なる概念） | Span | Traces |
| Span Event | Span上に記録されるpoint-in-timeのイベント。OTEP 4430によりSpan Event APIが非推奨化予定であり、Logs APIへの移行が推奨されている。本デモではこの方式を採用しない | — | — | Span Event | Traces |
| trace context | Traceの識別情報（trace_id, span_id）を保持するコンテキスト。OTel Logs API方式ではSDKが現在のSpanコンテキストからtrace_id/span_idを自動付与し、LogsとTracesの関連付けを実現する | トレースコンテキスト | — | trace context | 共通 |
| Log Record | OTel Logsにおけるログエントリ。タイムスタンプ、severity、body、attributesを持つ。本デモではEventReporterのビジネスイベントをLog Recordとして送信する | ログレコード | ログ（一般的な文字列ログと区別するため。OTel仕様における構造化されたデータ構造を指す） | LogRecord | Logs |
| Logs API | OTel SDKが提供するログ送信用API。LoggerProviderからLoggerを取得し、`on_emit`メソッドでLog Recordを送信する。本デモのEventReporter→OTel統合はこの方式（パターンB）を採用する | — | — | Logs API | Logs |
| LoggerProvider | OTel Logs SDKにおけるLoggerのファクトリ。`OpenTelemetry.logger_provider`でアクセスする | — | — | LoggerProvider | Logs |
| Logger | OTel Logs SDKにおけるLog Record送信の操作オブジェクト。LoggerProviderから取得し、`on_emit`でLog Recordを発行する | OTel Logger | Rails.logger（Railsの標準ロガーとは別物） | Logger | Logs |
| Counter | OTel Metricsにおける累積加算型のメトリクス種別。単調増加する値を記録する。本デモでは注文作成数をCounterで計測する | — | — | Counter | Metrics |
| Histogram | OTel Metricsにおける値の分布を記録するメトリクス種別。バケット分布と統計値（合計、個数、最小、最大）を算出する。本デモでは注文金額をHistogramで計測する | — | — | Histogram | Metrics |
| TracerProvider | OTel Traces SDKにおけるTracerのファクトリ。SpanProcessorとExporterの構成を保持する | — | — | TracerProvider | Traces |
| Tracer | OTel Traces SDKにおけるSpan生成の操作オブジェクト。TracerProviderから取得する | — | — | Tracer | Traces |
| SpanProcessor | Spanのライフサイクル（開始・終了）にフックして処理を行うコンポーネント。BatchSpanProcessorがバッチ送信の標準実装 | — | — | SpanProcessor | Traces |
| BatchSpanProcessor | 完了したSpanをバッチにまとめてExporterに送信するSpanProcessor実装。非同期バッチ処理によりパフォーマンスへの影響を最小化する | — | — | BatchSpanProcessor | Traces |
| OTLP Exporter | OTel SDKからOTel CollectorにOTLPでテレメトリを送信するコンポーネント。`opentelemetry-exporter-otlp` gemで提供される | — | — | OTLP Exporter | 共通 |
| OTEP 4430 | Span Event APIの非推奨化計画を定めたOTel仕様提案。「events are logs with names」の方針に基づき、Span Event APIをLogs APIに統合する。本デモがLogs API方式を採用する根拠の1つ | Span Event API Deprecation Plan | — | OTEP 4430 | Logs |

## AWS / CloudWatch関連

| 用語 | 定義 | 別名 | 禁止表現 | 英語名 | コンテキスト |
|------|------|------|----------|--------|-------------|
| CloudWatch | AWSが提供するモニタリング・オブザーバビリティサービス。OTLPエンドポイント経由でOTel標準形式のテレメトリを受信できる。本デモのテレメトリバックエンド | — | — | Amazon CloudWatch | 共通 |
| X-Ray | AWSの分散トレーシングサービス。OTel CollectorのAWS X-Ray Exporterを通じてOTLPのTraceデータを受信し、トレースを可視化する。CloudWatch OTLPエンドポイント（`xray.{Region}.amazonaws.com/v1/traces`）でGA提供 | AWS X-Ray | — | AWS X-Ray | Traces |
| CloudWatch Logs | AWSのログ管理サービス。OTel CollectorからOTLP経由でLog Recordを受信する。EventReporterのビジネスイベントの送信先。OTLPエンドポイント（`logs.{Region}.amazonaws.com/v1/logs`）でGA提供 | — | — | Amazon CloudWatch Logs | Logs |
| CloudWatch Metrics | AWSのメトリクスモニタリングサービス。OTel CollectorからOTLP経由でメトリクスデータを受信する。OTLPエンドポイント（`monitoring.{Region}.amazonaws.com/v1/metrics`）でPublic Preview提供（5リージョン限定、2026年4月時点） | — | — | Amazon CloudWatch Metrics | Metrics |

## インフラ関連

| 用語 | 定義 | 別名 | 禁止表現 | 英語名 | コンテキスト |
|------|------|------|----------|--------|-------------|
| OTel Collector | テレメトリデータの受信・処理・転送を行うベンダー非依存のエージェント。receiver→processor→exporterのパイプラインで構成される。本デモではOTLP receiverで受信し、AWS向けexporterでCloudWatchに転送する | Collector | — | OpenTelemetry Collector | 共通 |
| receiver | OTel Collectorの受信コンポーネント。アプリケーションやエージェントからテレメトリデータを受け取る。本デモではOTLP receiverを使用する | レシーバー | — | receiver | OTel Collector |
| processor | OTel Collectorの処理コンポーネント。受信したテレメトリデータの変換・フィルタリング・バッチ処理を行う。CloudWatchの配列型属性非対応への対処（属性削除）もprocessorで行う | プロセッサー | — | processor | OTel Collector |
| exporter | OTel Collectorの送信コンポーネント。処理済みのテレメトリデータをバックエンド（CloudWatch等）に転送する。本デモではOTLP HTTP exporterとSigV4認証拡張を組み合わせ、CloudWatch OTLPエンドポイントに送信する | エクスポーター | — | exporter | OTel Collector |
| Docker Compose | 複数コンテナの構成を宣言的に定義し、一括で起動・管理するツール。本デモではRailsアプリケーション、PostgreSQL、OTel Collectorの3コンテナを構成する | — | — | Docker Compose | 共通 |

---

## 改訂履歴

| バージョン | 日付 | 変更内容 |
|------------|------|----------|
| 1.0 | 2026/04/12 | 初版作成。要件定義書の用語定義（10語）を種として、調査報告書から技術用語を追加し全35語を定義 |
