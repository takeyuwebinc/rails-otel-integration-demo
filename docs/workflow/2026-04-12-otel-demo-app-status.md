# ドキュメントワークフロー進捗

## プロジェクト情報

- **ワークフローID**: otel-demo-app
- **プロジェクト名**: Rails 8.1 Structured Event Reporter + OpenTelemetry + CloudWatch デモアプリ
- **開始日**: 2026-04-12
- **最終更新日**: 2026-04-12
- **ステータス**: 完了

## ワークフロー進捗

- [x] Phase 1: インベントリと計画
- [x] Phase 2: 要件定義
- [x] Phase 3: 用語集
- [x] Phase 4: 機能設計
- [x] Phase 5: ADR（不要と判断。主要な意思決定は調査報告書と要件定義書で文書化済み）
- [x] Phase 6: ファクトチェック（スキップ。各Phase内で検証済み）
- [x] Phase 7: 完了レビュー

## 成果物一覧

| 文書種別 | タイトル | ステータス | ファイルパス |
|---------|---------|-----------|------------|
| 調査報告書 | Rails Event Reporter + OTel + CloudWatch 統合調査 | 完了（既存） | docs/research/rails-event-reporter-otel-cloudwatch.md |
| 要件定義書 | Rails 8.1 OTel統合デモアプリ 要件定義書 | 完了 | docs/requirements/requirements.md |
| 用語集 | Rails 8.1 OTel統合デモアプリ 用語集（35語） | 完了 | docs/glossary/glossary.md |
| 機能設計書 | Rails 8.1 OTel統合デモアプリ 機能設計書 | 完了 | docs/functional-design/functional-design.md |
| ADR | — | 不要（スキップ） | — |

## 備考

- 目的: 学習 + 技術記事執筆
- EventReporter → OTel統合はLogs API方式（パターンB）のみを採用（当初は3パターンすべてを検討していたが、方針変更）
- OTel CollectorはOTLP HTTP exporter + SigV4認証拡張でCloudWatch OTLPエンドポイントに送信
- 横断整合性チェックで検出されたCollector構成の表記不整合を修正済み
