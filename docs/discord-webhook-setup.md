# Discord Webhook の作成手順

## 1. Webhook を作成する

1. Discord で通知を送りたいチャンネルを開く
2. チャンネル名の横にある歯車アイコン（チャンネル設定）をクリック
3. 左メニューから **連携サービス** → **ウェブフック** を選択
4. **新しいウェブフック** をクリック
5. 名前を設定（例: `Server Health Monitor`）
6. **ウェブフックURLをコピー** をクリック

## 2. config.env に設定する

```bash
sudo vi /opt/health-monitor/config.env
```

以下の行にコピーした URL を貼り付ける:

```bash
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1234567890/abcdefg..."
```

## 3. 通知テスト

```bash
# Webhook URL が正しく設定されたか確認
source /opt/health-monitor/config.env
curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d '{"content":"Health Monitor テスト通知"}' \
  "$DISCORD_WEBHOOK_URL"
# 204 が返れば成功
```

## 通知の見え方

閾値を超えると、以下のような Embed メッセージが届きます:

```text
CPU Alert - myserver
━━━━━━━━━━━━━━━━━━━━━
Current:   94.2%
Threshold: 80%
Top Processes:
  root     1234    82.3% python3
  www-data 5678    11.2% node
━━━━━━━━━━━━━━━━━━━━━
```

色はアラート種別で変わります:

| 色 | アラート種別 |
|----|-------------|
| 赤 | CPU |
| オレンジ | メモリ |
| ダークオレンジ | Swap |
| 黄 | ディスク |
| 紫 | ロードアベレージ |
| 青 | プロセス死活 |
| **緑** | **復旧通知（全種別共通）** |

### 復旧通知の見え方

閾値を下回って正常に戻ると、緑色の Embed が届きます:

```text
CPU Recovered - myserver
━━━━━━━━━━━━━━━━━━━━━
Current:   45.2%
Threshold: 80%
━━━━━━━━━━━━━━━━━━━━━
```
