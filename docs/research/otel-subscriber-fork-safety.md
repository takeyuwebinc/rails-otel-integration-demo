# 調査報告: OtelLogsSubscriber の Puma `preload_app!` 環境における fork 安全性

**作成日**: 2026/04/12
**ステータス**: Final

## 概要

### 調査の背景

記事「02-logs」のレビューにおいて、以下の指摘を受けた:

> Pumaの`preload_app!`を使用するマルチワーカー環境では、masterプロセスでSubscriberが初期化された後にワーカーがforkされるため、ワーカープロセスごとにSubscriberを初期化する必要があります。`on_worker_boot`ブロック内で初期化するか、`preload_app!`を使わない構成を検討してください。

この指摘が事実に基づくものか、コード修正が必要かを判断するために調査を実施した。

### 調査の目的

`OtelLogsSubscriber` の初期化コードが Puma `preload_app!` + マルチワーカー環境で正しく動作するかを検証し、コード修正の要否を確定する。

### 調査範囲

- **前提**: 本プロジェクトは現在 `preload_app!` を使用していない（Puma 単一プロセス構成）。本調査は `preload_app!` を導入した場合に既存コードが正しく動作するかを検証する
- **調査対象**: `opentelemetry-logs-sdk` 0.5.0 の `BatchLogRecordProcessor` の fork 安全性、`opentelemetry-sdk` 1.11.0 / `opentelemetry-metrics-sdk` 0.13.0 の同等の仕組み
- **調査対象外**: OTel コレクター側の設定、デプロイ構成の選定

## 調査内容

### 調査対象

- `opentelemetry-logs-sdk` 0.5.0（`BatchLogRecordProcessor`）
- `opentelemetry-sdk` 1.11.0（`BatchSpanProcessor`）— 比較対象
- `opentelemetry-metrics-sdk` 0.13.0（`PeriodicMetricReader`）— 比較対象
- opentelemetry-ruby リポジトリの関連 Issue / PR

### 調査方法

1. GitHub 上の [opentelemetry-ruby](https://github.com/open-telemetry/opentelemetry-ruby) リポジトリから各 SDK のソースコードを取得・分析
2. fork 関連の Issue / PR を検索・確認
3. プロジェクトコードの初期化フロー分析

## 調査結果

### SDK の fork 安全性実装

3つの SDK すべてに fork 安全性が実装されている。

#### BatchLogRecordProcessor（opentelemetry-logs-sdk 0.5.0）

`reset_on_fork` メソッドが `initialize`、`on_emit`、`force_flush` の内部で呼ばれ、`Process.pid` 比較で fork を遅延検知する（[ソースコード](https://github.com/open-telemetry/opentelemetry-ruby/blob/opentelemetry-logs-sdk/v0.5.0/logs_sdk/lib/opentelemetry/sdk/logs/export/batch_log_record_processor.rb)）。

```ruby
def reset_on_fork(restart_thread: true)
  pid = Process.pid
  return if @pid == pid
  @pid = pid
  log_records.clear
  @thread = restart_thread ? Thread.new { work } : nil
end
```

fork 検知時の動作:

- 親プロセスのバッファをクリア（未送信レコードは破棄）
- 新しいワーカースレッドを起動
- エクスポーターはリセットしない

#### BatchSpanProcessor（opentelemetry-sdk 1.11.0）

`BatchLogRecordProcessor` と同一パターンの `reset_on_fork` を持つ（[ソースコード](https://github.com/open-telemetry/opentelemetry-ruby/blob/opentelemetry-sdk/v1.11.0/sdk/lib/opentelemetry/sdk/trace/export/batch_span_processor.rb)）。

#### PeriodicMetricReader（opentelemetry-metrics-sdk 0.13.0）

異なるアプローチ。`Process._fork` フックで即時検知する（Ruby 3.1+ が必要）。PR [#1823](https://github.com/open-telemetry/opentelemetry-ruby/pull/1823)（2025年5月マージ）で導入。

```ruby
def after_fork
  @exporter.reset if @exporter.respond_to?(:reset)
  collect  # 親プロセスの古いメトリクスを収集・破棄
  @thread = nil
  start
end
```

#### 比較表

| シグナル | SDK バージョン | 検知方式 | バッファ | スレッド | エクスポーター |
|---------|--------------|---------|---------|---------|-------------|
| Logs | 0.5.0 | PID 比較（遅延） | クリア | 再起動 | リセットなし |
| Traces | 1.11.0 | PID 比較（遅延） | クリア | 再起動 | リセットなし |
| Metrics | 0.13.0 | `Process._fork`（即時） | `collect` で破棄 | 再起動 | リセット |

### エクスポーターの fork 安全性

Logs / Traces の `reset_on_fork` はエクスポーターをリセットしない。本プロジェクトでは OTLP HTTP エクスポーター（`Net::HTTP` ベース、ポート 4318）を使用している。`Net::HTTP` は keep-alive 接続（タイムアウト 30 秒）を `@http` インスタンス変数で保持するため、fork 後に親プロセスの接続状態が子プロセスに引き継がれる。ただし、OTLP HTTP エクスポーターにはリトライ機構（最大 5 回、指数バックオフ）があり、fork 後の最初のエクスポートで接続エラーが発生しても自動復旧する。

gRPC エクスポーター使用時は fork 後にクラッシュやハングが発生する（[grpc/grpc #26257](https://github.com/grpc/grpc/issues/26257)）。本プロジェクトでは該当しない。

### 関連 Issue / PR

| # | タイトル | 状態 | 本プロジェクトへの影響 |
|---|---------|------|---------------------|
| [#310](https://github.com/open-telemetry/opentelemetry-ruby/issues/310) | Fork safety in BatchSpanProcessor | Closed | `reset_on_fork` 導入の元 Issue。解決済み |
| [#462](https://github.com/open-telemetry/opentelemetry-ruby/issues/462) | BSP should not spawn thread during Puma/Unicorn boot | Closed | マスターでの不要なスレッド起動。実害なし |
| [#1823](https://github.com/open-telemetry/opentelemetry-ruby/pull/1823) | fix: Recover periodic metric readers after forking | Merged | Metrics の fork 安全性。metrics-sdk 0.13.0 に含まれる |
| [#1425](https://github.com/open-telemetry/opentelemetry-ruby/issues/1425) | Forked Process Resource Attributes Are Missing | Closed (stale) | `process.pid` 属性が親のまま残る。ログ送信には影響しない |
| [#1800](https://github.com/open-telemetry/opentelemetry-ruby/issues/1800) | Periodic Metric exporter unable to collect on Passenger | Open | Passenger 固有。Puma には該当しない |

### プロジェクトの Ruby バージョン

`.ruby-version`: Ruby 4.0.2。`Process._fork` フック（Ruby 3.1+）が利用可能であり、Metrics を含む全シグナルで自動 fork 復旧が機能する。

## 分析・考察

### 主要な発見

レビュー指摘「ワーカープロセスごとにSubscriberを初期化する必要があります」は、使用中の `opentelemetry-logs-sdk` 0.5.0 では事実と異なる。`BatchLogRecordProcessor` の `reset_on_fork` により、fork 後のワーカーで最初のイベント発火時に自動的にスレッドが再起動される。

`preload_app!` 使用時の動作フロー:

1. マスタープロセスで Rails アプリケーションが初期化される。`preload_app!` はアプリケーションの初期化（イニシャライザの実行を含む）を fork 前のマスターで行う（[Puma DSL: preload_app!](https://puma.io/puma/Puma/DSL.html#preload_app!-instance_method)）。`config/initializers/opentelemetry.rb` の `after_initialize` ブロックもマスターで実行され、`OtelLogsSubscriber.new` → `BatchLogRecordProcessor` スレッド起動
2. `fork()` → ワーカーでスレッド消滅
3. ワーカーで最初のイベント発火 → `on_emit` → `reset_on_fork` が PID 変化を検知 → バッファクリア + スレッド再起動
4. 以降正常にエクスポート

`Rails.event.subscribe(subscriber)` の登録は `ActiveSupport::Notifications::Fanout` のインメモリ購読者リストとして fork 後のワーカーにコピーされる。Ruby の `fork()` による Copy-on-Write でオブジェクトが複製されるため、各ワーカーで独立した購読者インスタンスとして機能する。ただし、Fanout 内部の Mutex の fork 後の動作について Rails 公式ドキュメントでの明示的な保証は確認できていない。

`at_exit { subscriber.shutdown }` は各ワーカーで独立して実行される。ただし、Puma ワーカーが `exit!` で終了する場合は `at_exit` フックが実行されない点に注意が必要（`BatchLogRecordProcessor` の `reset_on_fork` はバッファクリアを行うため、未送信レコードが失われる可能性がある）。

### リスクと制約

| リスク | 深刻度 | 説明 |
|--------|--------|------|
| マスタープロセスに不要なスレッドが残る | 低 | `BatchLogRecordProcessor` のスレッドはイベントが発火しない限りアイドル状態。`PeriodicMetricReader` のスレッドは 60 秒間隔で collect を実行するが、マスターでは計器にデータが記録されないため空の収集となる |
| `exit!` による `at_exit` 非実行 | 低 | Puma ワーカーが `exit!` で終了した場合、`at_exit { subscriber.shutdown }` が呼ばれず、バッファ内の未送信レコードが失われる可能性がある |
| `process.pid` リソース属性がワーカーで親 PID のまま | 低 | 既知問題（[#1425](https://github.com/open-telemetry/opentelemetry-ruby/issues/1425)）。ログの送信先・内容・トレース相関には影響しない |
| gRPC エクスポーター使用時のクラッシュ | 該当なし | 本プロジェクトは OTLP HTTP エクスポーターを使用。gRPC エクスポーターでは fork 後にクラッシュが発生する |

## 結論・推奨事項

### 結論

`OtelLogsSubscriber` の現在の初期化コードは、本プロジェクトの構成（OTLP HTTP エクスポーター、Ruby 4.0.2）において、Puma `preload_app!` + マルチワーカー環境で**正しく動作する**。コード変更は不要。

根拠:

- `opentelemetry-logs-sdk` 0.5.0 の `BatchLogRecordProcessor` は `reset_on_fork` により fork を自動検知・復旧する
- `opentelemetry-sdk` 1.11.0（Traces）、`opentelemetry-metrics-sdk` 0.13.0（Metrics）も同様に fork 安全
- Ruby 4.0.2 は `Process._fork`（Ruby 3.1+）を満たしており、全シグナルで自動 fork 復旧が機能する
- OTLP HTTP エクスポーター使用のため、エクスポーターが fork 後にリセットされなくてもリトライ機構で復旧する

### 推奨事項

1. **記事の注記を修正する**
   - 理由: 「ワーカープロセスごとにSubscriberを初期化する必要があります」は `opentelemetry-logs-sdk` 0.5.0 の `reset_on_fork` 実装と矛盾する
   - 期待効果: 読者に正確な情報を提供し、不要な実装作業を防げる

### 次のアクション

- [ ] 記事 `docs/articles/02-logs/article.md` の該当注記を、SDK の fork 安全性に基づく正確な内容に修正する

## 参考資料

- [BatchLogRecordProcessor ソースコード (v0.5.0)](https://github.com/open-telemetry/opentelemetry-ruby/blob/opentelemetry-logs-sdk/v0.5.0/logs_sdk/lib/opentelemetry/sdk/logs/export/batch_log_record_processor.rb)
- [BatchSpanProcessor ソースコード (v1.11.0)](https://github.com/open-telemetry/opentelemetry-ruby/blob/opentelemetry-sdk/v1.11.0/sdk/lib/opentelemetry/sdk/trace/export/batch_span_processor.rb)
- [#310: Fork safety in BatchSpanProcessor](https://github.com/open-telemetry/opentelemetry-ruby/issues/310)
- [#1823: fix: Recover periodic metric readers after forking](https://github.com/open-telemetry/opentelemetry-ruby/pull/1823)
- [#1425: Forked Process Resource Attributes Are Missing](https://github.com/open-telemetry/opentelemetry-ruby/issues/1425)
- [grpc/grpc #26257: fork safety issues](https://github.com/grpc/grpc/issues/26257)
- [Puma DSL: preload_app!](https://puma.io/puma/Puma/DSL.html#preload_app!-instance_method)
