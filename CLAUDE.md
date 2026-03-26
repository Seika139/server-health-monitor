# Claude Code Instructions

## Project Overview

Ubuntu サーバーのヘルス監視ツール。1分間隔でメトリクスを記録し、閾値超過時に Discord Webhook で通知する。
開発はローカル Mac で行い、サーバーへは `scp` + `install.sh` でデプロイする。

## Language

- Use Japanese for communication and commit messages.

## Tech Stack

- **Language**: Bash (POSIX-compatible features + bashisms allowed)
- **Target OS**: Ubuntu 20.04+
- **Task runner**: [mise](https://mise.jdx.dev/) with file-based tasks in `mise/tasks/*.sh`
- **Linters**: shellcheck, markdownlint-cli2, yamllint

## Development Commands

```bash
mise run lint       # shellcheck + markdownlint + yamllint
mise run format     # markdownlint --fix
mise run validate   # config.env のバリデーション
mise run test       # bats-core ユニットテスト
mise run deploy -- user@server
```

## Project Structure

- `scripts/` — サーバー上で実行されるスクリプト群
- `systemd/` — systemd の service/timer ユニット
- `mise/tasks/` — ローカル開発用 mise タスク（shfmt/shellcheck の対象にするためファイルベース）
- `tests/` — bats-core ユニットテスト
- `docs/` — 詳細ドキュメント（README からリンク）
- `config.env` — サーバー上の設定ファイルのテンプレート

## Code Style

- シェルスクリプトは `set -euo pipefail` で始める
- shellcheck の `--severity=warning` をパスすること
- `# shellcheck source=` ディレクティブで source 先を明示する
- インデントはスペース4つ（`.editorconfig` 参照）
- 色付き出力は `\033[33m`（黄）/ `\033[32m`（緑）/ `\033[31m`（赤）+ `\033[0m`（リセット）

## Architecture Decisions

- **`/proc/stat` で CPU を取得**: `top -bn2` より高速（2秒→1秒）。1秒の `sleep` で差分を計算
- **systemd oneshot**: config.env を編集するだけで次回実行から反映（restart 不要）
- **クールダウン機構**: `/var/log/health-monitor/.cooldown/` にタイムスタンプファイルを置く方式。同一アラートの連続発火を抑制
- **Recovery 通知**: `/var/log/health-monitor/.alert/` にアラート状態ファイルを置き、閾値を下回ったら復旧通知を送信して削除する状態マシン。alert.sh の exit code で送信成功を確認し、成功時のみ状態を記録・削除する
- **Rate Limit 対策**: alert.sh で HTTP 429 を受けたら `Retry-After` ヘッダーを参照して最大5秒待機後に1回リトライ
- **heartbeat は opt-in**: `HEARTBEAT_URL` が空なら何もしない設計
- **install.sh の冪等性**: 再実行時に config.env を上書きせず、テンプレートとの差分（新規設定項目）を表示する

## Rules

- `scripts/` のスクリプトは Linux (Ubuntu) で動作する前提で書く。macOS 固有の構文は使わない
- `config.env` にシークレット（Webhook URL 等）のデフォルト値を入れない
- 新しいスクリプトを `scripts/` に追加したら `install.sh` のコピー対象にも追加する
- ドキュメント追加時は README の構成図・詳細ドキュメントテーブルも更新する
- 新しい設定項目を追加したら `config.env`、`validate-config.sh`、README の設定項目テーブルの3箇所を更新する
