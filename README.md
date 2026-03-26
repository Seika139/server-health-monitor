# server-health-monitor

Ubuntu サーバーのヘルス状態を自動記録し、異常時に Discord へ通知する軽量監視ツール。

## 前提条件

- **OS**: Ubuntu (20.04 以降)
- **権限**: sudo が使えること
- **ネットワーク**: Discord Webhook への HTTPS 通信が可能

## 構成

```text
server-health-monitor/
├── install.sh              # サーバーセットアップスクリプト
├── uninstall.sh            # 停止・アンインストール
├── config.env              # 設定ファイル（閾値・Webhook URL）
├── scripts/
│   ├── monitor.sh          # メイン監視（1分間隔で実行）
│   ├── alert.sh            # Discord Webhook 通知
│   ├── heartbeat.sh        # 外部死活監視への ping 送信
│   ├── status.sh           # 稼働状態の確認
│   ├── test-alert.sh       # Discord 通知テスト
│   ├── analyze.sh          # ログ解析レポート
│   └── validate-config.sh  # 設定値バリデーション
├── systemd/
│   ├── health-monitor.service
│   └── health-monitor.timer
├── mise/tasks/             # ローカル開発用タスク
├── tests/                  # bats-core ユニットテスト
└── docs/                   # 詳細ドキュメント
```

## 監視項目

| 項目             | 取得方法        | デフォルト閾値 |
| ---------------- | --------------- | -------------- |
| CPU 使用率       | `/proc/stat`    | 80%            |
| メモリ使用率     | `/proc/meminfo` | 80%            |
| Swap 使用率      | `/proc/meminfo` | 50%            |
| ディスク使用率   | `df /`          | 90%            |
| ロードアベレージ | `/proc/loadavg` | CPU コア数 x 2 |
| プロセス死活     | `pgrep -x`      | - (設定時のみ) |

## クイックスタート

### 1. サーバーにコピー

```bash
scp -r server-health-monitor/ user@server:~/
```

### 2. インストール

```bash
ssh user@server
cd ~/server-health-monitor
sudo bash install.sh
```

install.sh が行うこと:

- `atop`, `sysstat`, `curl` のインストール
- atop の10秒間隔記録を有効化
- スクリプトを `/opt/health-monitor/` に配置
- systemd timer を登録（1分間隔）
- logrotate を設定（30日保持）

### 3. Discord Webhook URL を設定

Discord の Webhook URL を取得して設定します（[詳細手順](docs/discord-webhook-setup.md)）。

```bash
sudo vi /opt/health-monitor/config.env
# DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..." を設定
```

### 4. 動作確認

```bash
# 設定のバリデーション
bash /opt/health-monitor/scripts/validate-config.sh

# Discord 通知テスト
bash /opt/health-monitor/scripts/test-alert.sh

# 手動実行
sudo bash /opt/health-monitor/scripts/monitor.sh

# 稼働状態の確認
bash /opt/health-monitor/scripts/status.sh
```

## 設定項目

`/opt/health-monitor/config.env` で以下を調整可能です。
oneshot サービスのため、設定変更後の再起動は不要です（次回実行時から反映）。

| 変数                        | 説明                                   | デフォルト    |
| --------------------------- | -------------------------------------- | ------------- |
| `DISCORD_WEBHOOK_URL`       | Discord Webhook URL（必須）            | -             |
| `SERVER_NAME`               | アラートに表示するサーバー名           | `$(hostname)` |
| `CPU_THRESHOLD`             | CPU アラート閾値 (%)                   | 80            |
| `MEMORY_THRESHOLD`          | メモリアラート閾値 (%)                 | 80            |
| `SWAP_THRESHOLD`            | Swap アラート閾値 (%)                  | 50            |
| `DISK_THRESHOLD`            | ディスクアラート閾値 (%)               | 90            |
| `LOAD_THRESHOLD_MULTIPLIER` | ロード閾値 = コア数 x この値           | 2             |
| `WATCH_PROCESSES`           | 死活監視するプロセス名（カンマ区切り） | -             |
| `LOG_RETENTION_DAYS`        | ログ保持日数                           | 30            |
| `ALERT_COOLDOWN`            | 同一アラート抑制秒数                   | 300           |
| `TOP_PROCESSES`             | アラートに含むプロセス数               | 5             |
| `HEARTBEAT_URL`             | 外部死活監視の ping 先 URL（空で無効） | -             |
| `HEARTBEAT_METHOD`          | `GET` または `POST`                    | `GET`         |

## 通知の仕組み

### アラートと復旧通知

閾値を超えると**アラート通知**（赤〜紫の embed）が Discord に送信されます。
その後、値が閾値を下回ると**復旧通知**（緑の embed）が自動送信されます。

```text
CPU 92% 超過 → [CPU Alert]     赤い embed が送信される
  ↓ (数分後)
CPU 45% に低下 → [CPU Recovered] 緑の embed が送信される
```

- 同一アラートの連続通知は `ALERT_COOLDOWN`（デフォルト300秒）で抑制されます
- 復旧通知はクールダウンの影響を受けず、必ず送信されます
- 通知色の一覧は [Discord Webhook セットアップ](docs/discord-webhook-setup.md) を参照

### Discord Rate Limit

短時間に複数の閾値を同時に超えた場合、Discord の Rate Limit（HTTP 429）を受けることがあります。
alert.sh は `Retry-After` ヘッダーを参照して最大5秒待機後に1回リトライします。

### アップグレード（再インストール）

`install.sh` を再実行すると、スクリプトと systemd unit は上書きされますが、
既存の `config.env` は保持されます。テンプレートに新しい設定項目が追加されている場合は
差分が表示されるので、必要に応じて手動で追記してください。

## 詳細ドキュメント

| ドキュメント                                                  | 内容                                                  |
| ------------------------------------------------------------- | ----------------------------------------------------- |
| [Discord Webhook セットアップ](docs/discord-webhook-setup.md) | Webhook の作成方法、通知テスト、通知の見え方          |
| [ログフォーマット](docs/log-format.md)                        | TSV フィールド定義、解析用 awk ワンライナー集         |
| [事後調査ガイド](docs/investigation-guide.md)                 | スパイク発生後の原因特定フロー（atop / sar の使い方） |
| [トラブルシューティング](docs/troubleshooting.md)             | 通知が来ない、timer が動かない等の対処法              |

## 運用コマンド（サーバー上）

```bash
# 稼働状態の確認
bash /opt/health-monitor/scripts/status.sh

# ログ解析レポート（当日）
bash /opt/health-monitor/scripts/analyze.sh

# ログ解析レポート（日付指定）
bash /opt/health-monitor/scripts/analyze.sh 2026-03-26

# Discord 通知テスト
bash /opt/health-monitor/scripts/test-alert.sh

# 設定バリデーション
bash /opt/health-monitor/scripts/validate-config.sh
```

## 開発コマンド（ローカル）

[mise](https://mise.jdx.dev/) を使った開発用タスク:

```bash
mise run lint       # shellcheck + markdownlint + yamllint
mise run format     # markdownlint --fix
mise run validate   # config.env のバリデーション
mise run test       # bats-core ユニットテスト
mise run deploy -- user@server  # サーバーにデプロイ
```

## 停止・アンインストール

```bash
sudo bash uninstall.sh
```

3つのモードを選択できます:

| モード              | 内容                                                        |
| ------------------- | ----------------------------------------------------------- |
| **1) Stop only**    | timer を停止。ファイル・ログはそのまま。再開も可能          |
| **2) Uninstall**    | health-monitor のファイルと systemd unit を削除。ログは保持 |
| **3) Full cleanup** | atop・sysstat も含めて全て削除                              |
