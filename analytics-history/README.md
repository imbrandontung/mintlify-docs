# Analytics History — Weekly Snapshots

> 由 `weekly-brand-sync-audit` Skill 每週一 09:00 自動寫入。
> 純資料目錄，**不**被 Mintlify 渲染為頁面（已在 `.mintignore` 排除）。

## 目錄結構

```
analytics-history/
├── README.md            (這個檔案)
├── mintlify/
│   ├── 2026-04-28.json  (週一 09:00 snapshot)
│   ├── 2026-05-05.json
│   └── ...
└── cloudflare/
    ├── 2026-04-28.json
    ├── 2026-05-05.json
    └── ...
```

## JSON 格式

詳見 Skill `references/analytics-format.md`。

兩家共通頂層欄位：
- `snapshot_date`
- `platform`
- `source_url`
- `date_range`
- `totals`
- `top_pages`
- `top_referrers`

Cloudflare 額外有：
- `geo` (country / city breakdown)
- `device` (desktop / mobile / tablet)
- `browser`
- `os`
- `time_series` (daily 7-day)

## 為何永久保留在 GitHub

| 平台 | 預設保留期 | 我們需要 |
|---|---|---|
| Mintlify built-in | 7 天滾動 | 永久 |
| Cloudflare Free | 6 個月 | 永久 |
| GitHub git history | ♾️ | ♾️ |

把每週 snapshot commit 到 GitHub = 利用 git history 永久保留 + 跨平台備份 + 任何電腦 git clone 即可重現完整紀錄。

## 趨勢分析（週報用）

讀取所有 `*.json` 後計算：

- WoW（週對週）變化 %
- 4 週移動平均
- 12 週線性趨勢斜率
- 新國家 / 新 referrer 偵測
- 裝置比例演變

## 隱私

Cloudflare Web Analytics **不追蹤個人身份**（無 cookie、無 fingerprint、無 IP 儲存），符合 GDPR / CCPA。所有 snapshot 數據為**聚合層級**，不含個人識別資訊。
