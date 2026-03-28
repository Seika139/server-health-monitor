# server-health-monitor Agent Guide

Ubuntu サーバーのヘルス状態を自動記録し、異常時に Discord へ通知する軽量監視ツールです。
本書はプロジェクトを触るエージェント向けの簡易ガイドです。

## セットアップ

- 前提: macOS（開発）/ Ubuntu 20.04+（デプロイ先）
- タスクランナー: [mise](https://mise.jdx.dev/)

```bash
cd server-health-monitor
mise trust
mise run lint     # 全 linter 実行
```

## ディレクトリ概要

| パス | 説明 |
|------|------|
| `scripts/monitor.sh` | メイン監視スクリプト。1分間隔で systemd timer から実行される |
| `scripts/alert.sh` | Discord Webhook への通知送信。クールダウン機構を内蔵 |
| `scripts/heartbeat.sh` | 外部死活監視サービスへの ping 送信 |
| `scripts/status.sh` | サーバー上での稼働状態確認 |
| `scripts/test-alert.sh` | Discord 通知のテスト送信 |
| `scripts/analyze.sh` | メトリクスログの集計レポート生成 |
| `scripts/validate-config.sh` | config.env の型・範囲バリデーション |
| `config.env` | 設定ファイルテンプレート（閾値、Webhook URL 等） |
| `install.sh` | サーバーへのインストーラ（パッケージ導入〜systemd 登録） |
| `uninstall.sh` | 3段階のアンインストーラ（停止/削除/完全撤去） |
| `systemd/` | systemd service/timer ユニットファイル |
| `mise/tasks/*.sh` | ローカル開発用 mise タスク |
| `tests/*.bats` | bats-core ユニットテスト |
| `docs/` | 詳細ドキュメント |

## 主な mise タスク

| コマンド | 説明 |
|----------|------|
| `mise run lint` | shellcheck + markdownlint + yamllint を一括実行 |
| `mise run format` | markdownlint --fix による自動修正 |
| `mise run validate` | config.env のバリデーション |
| `mise run test` | bats-core ユニットテスト |
| `mise run deploy -- user@server` | サーバーへファイルをコピー |

## データフロー

```text
systemd timer (1分間隔)
  └── monitor.sh
        ├── /proc/stat, /proc/meminfo, /proc/vmstat, df, /proc/loadavg, pgrep
        │     → メトリクス収集
        ├── /var/log/health-monitor/metrics-YYYY-MM-DD.log
        │     → TSV 形式でログ記録
        ├── 閾値超過? → fire_alert() → alert.sh → Discord Webhook
        │     │          └── 成功時のみ .alert/<type> を作成
        │     └── クールダウンチェック (.cooldown/)、Rate Limit リトライ (429)
        ├── 閾値以下 & .alert/<type> 存在? → check_recovery() → alert.sh recover
        │     └── 成功時のみ .alert/<type> を削除
        └── heartbeat.sh → 外部 URL へ ping (opt-in)
```

## 監視項目

| 項目 | 取得元 | デフォルト閾値 |
|------|--------|---------------|
| CPU 使用率 | `/proc/stat`（1秒差分） | 80% |
| メモリ使用率 | `/proc/meminfo` | 80% |
| Swap I/O レート | `/proc/vmstat`（1秒差分） | 200 pg/s |
| ディスク使用率 | `df /` | 90% |
| ロードアベレージ | `/proc/loadavg` | CPU コア数 x 2 |
| プロセス死活 | `pgrep -x` | 設定時のみ |

## 実装上の注意

- `scripts/` 配下は **Ubuntu (Linux) で動作する前提**で書く。macOS 固有の構文（`sed -i ''`、`date -v` 等）は使わない
- `set -euo pipefail` をスクリプトの先頭に必ず記述する
- `config.env` を `source` する箇所には `# shellcheck source=../config.env` を付ける
- `curl` による外部通信は `|| true` でガードし、通信失敗が監視本体を止めないようにする
- Discord 通知のクールダウンはファイルベース（`/var/log/health-monitor/.cooldown/`）。テスト時は `rm -rf` でリセットできる
- アラート状態は `/var/log/health-monitor/.alert/<type>` のタッチファイルで管理。`alert.sh` の **exit code で送信成功を判定**し、成功時のみ状態を記録・削除する（未送信での孤立 Recovery を防止）
- Recovery 通知はクールダウンをスキップする（復旧は必ず通知すべきため）
- `alert.sh` は HTTP 429 で1回リトライする。`Retry-After` ヘッダーを参照し、最大5秒で打ち切る

## 変更時のチェックリスト

新しいスクリプトを追加した場合:

- [ ] `install.sh` のコピー対象に追加
- [ ] README の構成図を更新
- [ ] `mise run lint` がパスすることを確認
- [ ] `mise run test` がパスすることを確認

新しい設定項目を追加した場合:

- [ ] `config.env` にデフォルト値付きで追加
- [ ] `scripts/validate-config.sh` にバリデーションを追加
- [ ] `scripts/monitor.sh` で使用（必要に応じて）
- [ ] README の設定項目テーブルを更新

新しい監視項目を追加した場合:

- [ ] `scripts/monitor.sh` にメトリクス取得・ログ出力・閾値チェックを追加
- [ ] `scripts/alert.sh` の `case` 文にアラート種別と色を追加
- [ ] `docs/log-format.md` のフィールド定義を更新
- [ ] README の監視項目テーブルを更新

## 参考リソース

- `README.md` — クイックスタートと設定一覧
- `docs/discord-webhook-setup.md` — Webhook の作成手順
- `docs/log-format.md` — TSV ログのフィールド定義と解析例
- `docs/investigation-guide.md` — スパイク発生後の原因調査フロー
- `docs/troubleshooting.md` — よくあるトラブルの対処法
