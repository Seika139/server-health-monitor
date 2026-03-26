# 事後調査ガイド

サーバーのフリーズやスパイクが発生した後、原因を特定するための手順。

## 調査フロー

```text
1. メトリクスログで異常時刻を特定
        ↓
2. atop でその時刻のプロセスを確認
        ↓
3. sar でシステム全体のトレンドを確認
        ↓
4. 必要に応じて個別ログを調査
```

## Step 1: 異常時刻の特定

メトリクスログから異常が発生した時間帯を絞り込みます。

```bash
# 当日のログを確認
cat /var/log/health-monitor/metrics-$(date +%Y-%m-%d).log

# CPU > 80% の時刻を抽出
awk -F'\t' '{split($2,a,"="); split(a[2],b,"%"); if(b[1]+0>80) print}' \
    /var/log/health-monitor/metrics-2026-03-26.log

# メモリ > 80% の時刻を抽出
awk -F'\t' '{split($3,a,"="); split(a[2],b,"%"); if(b[1]+0>80) print}' \
    /var/log/health-monitor/metrics-2026-03-26.log
```

## Step 2: atop で原因プロセスを特定

atop は10秒間隔でプロセス単位の記録を保持しています。

```bash
# 特定日の atop 記録を開く
atop -r /var/log/atop/atop_20260326
```

### atop の操作

| キー | 動作 |
|------|------|
| `b` | 指定時刻にジャンプ（例: `15:30` と入力） |
| `t` / `T` | 次 / 前のスナップショット（10秒単位） |
| `p` | プロセス単位表示に切替 |
| `C` | CPU 使用率でソート |
| `M` | メモリ使用量でソート |
| `D` | ディスク I/O でソート |
| `N` | ネットワークでソート |
| `q` | 終了 |

### 調べるポイント

- **CPU スパイク**: `C` でソートし、上位のプロセスとそのコマンドを確認
- **メモリ枯渇**: `M` でソートし、RSIZE（実メモリ使用量）が大きいプロセスを確認
- **OOM Killer**: `dmesg | grep -i oom` で OOM Killer が発動していないか確認
- **ディスク I/O**: `D` でソートし、大量の読み書きをしているプロセスを確認

## Step 3: sar でシステム全体のトレンドを確認

sar は1日を通した統計を確認できます。

```bash
# CPU 使用率の推移
sar -u -f /var/log/sysstat/sa26

# メモリ使用率
sar -r -f /var/log/sysstat/sa26

# ディスク I/O
sar -d -f /var/log/sysstat/sa26

# ネットワーク
sar -n DEV -f /var/log/sysstat/sa26

# 特定時間帯に絞る（15:00〜16:00）
sar -u -s 15:00:00 -e 16:00:00 -f /var/log/sysstat/sa26
```

## Step 4: 個別ログの調査

原因プロセスが判明したら、そのアプリケーションのログを確認します。

```bash
# システムログ
journalctl --since "2026-03-26 15:30" --until "2026-03-26 16:00"

# 特定サービスのログ
journalctl -u nginx --since "2026-03-26 15:30"

# OOM Killer のログ
dmesg | grep -i "out of memory"
journalctl -k | grep -i "oom"
```

## よくある原因パターン

| 症状 | よくある原因 | 確認方法 |
|------|-------------|----------|
| CPU 100% 張り付き | 無限ループ、過剰なリクエスト | atop `C` ソートでプロセス特定 |
| メモリ急増 → OOM | メモリリーク、大量データ処理 | `dmesg \| grep oom` + atop `M` ソート |
| ディスク I/O 高負荷 | 大量ログ出力、バックアップ、swap | atop `D` ソート + `sar -d` |
| Load 高い + CPU 低い | I/O wait（ディスクがボトルネック） | `sar -u` で `%iowait` を確認 |
