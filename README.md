# Brandon Tung

> **Agent，從營運現場長出來。**
> **Agents, grown on the ops floor.**

**Live site**: https://imbrandontung.mintlify.app/

## 中文版 / 站台說明

這個 repo 是 [imbrandontung.mintlify.app](https://imbrandontung.mintlify.app/) 的原始檔案，使用 [Mintlify](https://mintlify.com/) 託管。

### 結構

```
.
├── docs.json              # Mintlify 站台配置
├── index.mdx              # 落地頁
├── introduction.mdx       # 首頁（hero + 卡片）
├── about.mdx              # 履歷與能力範圍
├── projects/              # ML 專案頁
│   ├── regression.mdx
│   ├── classification.mdx
│   ├── nlp-bots.mdx
│   ├── eda.mdx
│   ├── scraping.mdx
│   └── visualization.mdx
├── ml100days/             # 100 天挑戰頁
│   ├── overview.mdx
│   ├── days-1-5.mdx
│   └── days-6-13.mdx
└── resources/             # 資源頁
    ├── datasets.mdx
    └── tools.mdx
```

### 內容守則

1. **雙語**：中文先 → 英文後（站內所有頁面）
2. **遮罩**：客戶名、內部 IP、SID、案件數字 一律不出現在公開頁
3. **誠信**：未驗證的數字、結果、claim 一律標 TODO，不寫上去

### 本機開發

```bash
# 安裝 Mintlify CLI
npm i -g mint

# 在本目錄啟動 dev server
mint dev
```

---

## English

This repo holds the source for [imbrandontung.mintlify.app](https://imbrandontung.mintlify.app/), hosted on [Mintlify](https://mintlify.com/).

### Structure

(see tree above)

### Content rules

1. **Bilingual** — Chinese first, English second (every page)
2. **Redaction** — no customer names, internal IPs, SIDs, or case-volume numbers on public pages
3. **Integrity** — any unverified number, result, or claim is marked TODO until verified

### Local dev

```bash
npm i -g mint
mint dev
```

## Author

**Brandon Tung** — Dynasafe Digital COE Lead · CISSP / CHFI (PMP earned 2009, lapsed)
[LinkedIn](https://www.linkedin.com/in/imbrandontung/) · Contact via LinkedIn DM (no email published).

## License

Content (text, mdx) is © Brandon Tung, all rights reserved unless otherwise noted.
Code snippets within the site are MIT licensed unless explicitly stated.
