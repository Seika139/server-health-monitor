# トラブルシューティング

## timer が動いていない

```bash
# timer の状態を確認
systemctl status health-monitor.timer

# timer が有効か確認
systemctl is-enabled health-monitor.timer

# 有効でなければ再度有効化
sudo systemctl enable --now health-monitor.timer
```

## 手動実行でエラーが出る

```bash
# 手動で実行してエラーを確認
sudo bash /opt/health-monitor/scripts/monitor.sh

# config.env が読めるか確認
cat /opt/health-monitor/config.env
```

よくある原因:

- `config.env` のパーミッション（root で読めるか）
- `curl` が未インストール

## Discord に通知が来ない

### 1. Webhook URL が正しいか確認

```bash
source /opt/health-monitor/config.env
echo "$DISCORD_WEBHOOK_URL"
# 空なら config.env に URL を設定する
```

### 2. Webhook が生きているかテスト

```bash
source /opt/health-monitor/config.env
curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d '{"content":"test"}' \
  "$DISCORD_WEBHOOK_URL"
# 204 = 成功, 401 = URL無効, 404 = Webhook削除済み
```

### 3. クールダウンが効いていないか確認

同一アラートは `ALERT_COOLDOWN` 秒間（デフォルト300秒）抑制されます。

```bash
# クールダウンファイルを確認
ls -la /var/log/health-monitor/.cooldown/

# 強制的にリセット
sudo rm -rf /var/log/health-monitor/.cooldown/
```

### 4. そもそも閾値を超えていない

```bash
# 最新のログを確認
tail -5 /var/log/health-monitor/metrics-$(date +%Y-%m-%d).log
```

閾値を一時的に下げてテストする:

```bash
sudo vi /opt/health-monitor/config.env
# CPU_THRESHOLD=1  のように低い値にして手動実行
sudo bash /opt/health-monitor/scripts/monitor.sh
# テスト後に元に戻すこと
```

## journalctl でログを確認する

systemd 経由の実行ログは journalctl で確認できます。

```bash
# 最近の実行結果
journalctl -u health-monitor.service --no-pager -n 20

# リアルタイムで監視
journalctl -u health-monitor.service -f
```

## atop のデータがない

```bash
# atop が動いているか確認
systemctl status atop

# ログディレクトリを確認
ls -la /var/log/atop/
```

atop が停止している場合:

```bash
sudo systemctl enable --now atop
```
