# ログフォーマット

## メトリクスログ

**場所**: `/var/log/health-monitor/metrics-YYYY-MM-DD.log`

TSV（タブ区切り）形式で1分ごとに1行追記されます。

### フィールド

| # | フィールド | 例 | 説明 |
|---|-----------|-----|------|
| 1 | タイムスタンプ | `2026-03-26 15:32:01` | `YYYY-MM-DD HH:MM:SS` 形式 |
| 2 | CPU 使用率 | `cpu=42.3%` | `/proc/stat` から1秒差分で算出 |
| 3 | メモリ使用率 | `mem=65.1%` | `(Total - Available) / Total` |
| 4 | Swap 使用率 | `swap=12.0%` | `(Total - Free) / Total` |
| 5 | Swap I/O レート | `swap_io=150pg/s` | `/proc/vmstat` の `pswpin`+`pswpout` の1秒差分 |
| 6 | ディスク使用率 | `disk=72%` | ルートパーティション (`/`) |
| 7 | ロードアベレージ | `load=1.25` | 1分間平均 |
| 8 | CPU コア数 | `cores=4` | `nproc` の値 |

### サンプル

```text
2026-03-26 15:32:01  cpu=42.3%  mem=65.1%  swap=5.0%   swap_io=0pg/s    disk=72%  load=1.25  cores=4
2026-03-26 15:33:01  cpu=88.7%  mem=71.3%  swap=12.3%  swap_io=85pg/s   disk=72%  load=3.41  cores=4
2026-03-26 15:34:01  cpu=91.2%  mem=85.0%  swap=45.1%  swap_io=310pg/s  disk=72%  load=5.12  cores=4
```

### 解析ヘルパー

`analyze.sh` で集計レポートを生成できます。

```bash
# 当日のレポート
bash /opt/health-monitor/scripts/analyze.sh

# 日付指定
bash /opt/health-monitor/scripts/analyze.sh 2026-03-26
```

出力内容: 各メトリクスの平均/最大値、時間帯別CPU推移のバーチャート、閾値超過回数と発生時刻。

### 手動解析（awk）

```bash
# 特定日のログを表示
cat /var/log/health-monitor/metrics-2026-03-26.log

# CPU が 80% を超えた行を抽出
awk -F'\t' '{split($2,a,"="); split(a[2],b,"%"); if(b[1]+0>80) print}' \
    /var/log/health-monitor/metrics-2026-03-26.log

# 時間帯ごとの CPU 平均（1時間単位）
awk -F'\t' '{
    split($1,t," "); hour=substr(t[2],1,2);
    split($2,a,"="); split(a[2],b,"%");
    sum[hour]+=b[1]; cnt[hour]++
} END {
    for(h in sum) printf "%s:00  avg cpu=%.1f%%\n", h, sum[h]/cnt[h]
}' /var/log/health-monitor/metrics-2026-03-26.log | sort
```

## logrotate

- 日次でローテーション
- 30世代保持（`config.env` の `LOG_RETENTION_DAYS` に対応）
- gzip 圧縮（1日遅延）
- 設定ファイル: `/etc/logrotate.d/health-monitor`
