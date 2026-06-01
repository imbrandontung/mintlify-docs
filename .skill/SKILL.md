---
name: brand-auto-dashboard
description: Brandon Tung 個人品牌（imbrandontung.mintlify.app）每日 Brand Auto Dashboard 的標準產出流程。Use this skill whenever the user mentions brand-metrics、brand_data、daily_collector、NDA scan dashboard、文章聲量排名、Brandon Tung 資安自媒體 dashboard、scanned files checklist、NDA_PrePublish_Scorecard.html, or asks to regenerate / refresh / fix / extend the brand metrics dashboard. Trigger even when the user only references one section name like "今日 NDA 掃描明細" or "📁 已掃描檔案清單", because all sections live in the same dashboard pipeline. Also trigger for Cloudflare API token diagnosis (cfut_ prefix), brand_data.js schema questions, or any request to "rerun the brand metrics" / "show today's dashboard".
---

# Brand Auto Dashboard — Standard Operating Procedure

Pipeline that produces `C:\Users\user\Documents\Claude\Projects\打造個人品牌\NDA_PrePublish_Scorecard.html`. Tomorrow's output must be **100% layout-identical** to today's. Golden HTML lives both at the project path and at `.skill/NDA_PrePublish_Scorecard.golden.html` — never freelance the layout, change only `brand_data.js` unless the user explicitly asks for a layout change.

This is the canonical mirror of the AppData skill (`skills-plugin\…\skills\brand-auto-dashboard\`). The AppData copy can occasionally lose files; this Documents copy is the source of truth.

## 1. Files in play

Under `C:\Users\user\Documents\Claude\Projects\打造個人品牌\`:

- `NDA_PrePublish_Scorecard.html` — the dashboard, golden layout. Restore from `.skill/NDA_PrePublish_Scorecard.golden.html` if broken.
- `brand_data.js` — `window.BRAND_DATA = {...}`. Regenerated daily by collector or manual rerun.
- `brand_data.json` — JSON mirror of brand_data.js (no `window.` prefix). Keep in sync.
- `daily_collector.py` — Python collector. Edited only when adding metric sources.
- `daily_collector.config.json` — Cloudflare token + usernames. **Never echo token in chat.**
- `daily_collector.log` — append-only log of each run.
- `cloudflare-token-verify.ps1` + `.bat` — token diagnostic (token never printed).

## 2. Dashboard layout (must stay this exact order)

1. `<header>` — H1「📊 Brandon Tung 資安自媒體」+ tagline `Agents, grown on the ops floor.` + meta strip + source ON/OFF/ERR badges
2. **Snapshot cards** — NDA / GH Stars / Mintlify Pages / Cloudflare Visits / LinkedIn
3. **📈 趨勢圖表 / Trends** — 5 charts (NDA hits, GH growth, Mintlify pages, CF+LI engagement, NDA pattern bar)
4. **📣 文章累計聲量排行 / Article Voice Ranking** — `articles.ranked`, top 3 with 🥇🥈🥉
5. **🛡️ 今日 NDA 掃描明細 / Today's NDA File-by-File Detail** — every scanned file as a row
6. **📋 附錄：NDA 檢查項目清單 / Appendix: NDA Check Items** — 7 patterns × PASS/FAIL
7. **📁 已掃描檔案清單 / Scanned Files Checklist** — final section, must be LAST h2

New sections default between Trends and NDA detail unless user says otherwise.

## 3. brand_data.js schema

```js
window.BRAND_DATA = {
  schema: "v3",
  nda: [{
    date, hits, files_scanned, files_with_hits,
    by_pattern: {                    // ALL 7 keys required
      "IP-Private":0,"IP-Public":0,"Email-Internal":0,"Hostname-Pattern":0,
      "Project-Code":0,"Contract-No":0,"NDA-Trigger":0
    },
    by_file: [{ file, total, hits:[{pattern,count}], snippets:[{line,pattern,match,context}] }],
    scanned_files: [/* every file scanned, sorted, forward-slash, relative */],
    ts, rerun_method?: "manual_via_web_fetch_grep"
  }],
  metrics: [{
    date,
    github:    {username, followers, following, public_repos, stars, forks, fetched:true} | {error,fetched:false},
    mintlify:  {domain, page_count, fetched:true} | {error,fetched:false},
    cloudflare:{pageviews, visits, visitors, for_date, fetched:true} | {skipped} | {error,fetched:false},
    linkedin:  {followers, fetched:true} | {skipped:"no token"},
    ts
  }],
  articles: {
    as_of, score_formula, score_note,
    ranked: [{ rank, file, url, title, lines, headings, code_blocks, last_modified, score }]
    // sorted desc by score, rank = index+1, currently 15 entries
  },
  last_run, last_run_local
};
```

`brand_data.json` = same object minus `window.BRAND_DATA = ` and `;`.

## 4. Render pipeline (in NDA_PrePublish_Scorecard.html)

```js
const root = document.getElementById("root");
const D = window.BRAND_DATA;
const NDA_PATTERN_DEFS = [...7 entries...];   // MUST be here, NOT later — TDZ

if(!D){ root.innerHTML = "<empty-state>"; }
else {
  document.getElementById("lastRun").textContent = D.last_run_local || D.last_run || "—";
  [
    ["renderSourceStrip",            renderSourceStrip],
    ["renderSnapshot",               renderSnapshot],
    ["renderCharts",                 renderCharts],
    ["renderArticleVoiceRank",       renderArticleVoiceRank],
    ["renderNdaTable",               renderNdaTable],
    ["renderNdaChecklist",           renderNdaChecklist],
    ["renderScannedFilesChecklist",  renderScannedFilesChecklist],
  ].forEach(([name, fn]) => {
    try { fn(D); }
    catch(e){
      root.insertAdjacentHTML("beforeend",
        '<div class="empty" style="border-color:var(--red);color:var(--red);margin:8px 0">'
        + '⚠️ ' + name + ' 渲染失敗：' + (e?.message || String(e))
        + ' (typeof Chart=' + typeof Chart + ')</div>');
    }
  });
}
```

Three patterns the HTML depends on:

- **TDZ-safe const placement** — `const NDA_PATTERN_DEFS` near top of script, BEFORE the `forEach`. `const` has temporal dead zone; declaring it after the forEach throws ReferenceError inside `renderNdaChecklist`.
- **Try/catch wrapper** — one renderer's failure must not block the rest. Most common failure: Chart.js blocked by Cowork preview's CSP.
- **SVG chart fallback** — `renderCharts` checks `typeof Chart === "undefined"` and uses inline `svgLineChart` / `svgBarChart`. Cowork preview's CSP blocks `cdnjs.cloudflare.com`; without fallback the dashboard shows blank chart cards.

## 5. Header text — exact strings

```html
<title>Brandon Tung 資安自媒體 — Agents, grown on the ops floor.</title>
<h1 style="margin:0 0 2px">📊 Brandon Tung 資安自媒體</h1>
<div class="tagline" style="font-size:14px;color:var(--accent);font-style:italic;margin:0 0 6px;letter-spacing:.3px">Agents, grown on the ops floor.</div>
<div class="sub">自媒體成效 + NDA 自查全自動儀表板 / Auto-collected daily, zero-click view</div>
```

The string `Brand Auto Dashboard` must NOT appear anywhere. Verify with grep after any header edit.

## 6. Daily run — happy path

1. Cowork scheduled task triggers (typically 09:01).
2. `python3 daily_collector.py` runs in `打造個人品牌/`.
3. Collector fetches GitHub / Mintlify / Cloudflare / LinkedIn, runs NDA scan over `*.md` / `*.mdx`.
4. Writes `brand_data.json` + `brand_data.js`, appends to `daily_collector.log`.
5. Dashboard auto-picks up new data on next page load.

**Reply MUST end with the dashboard `computer://` link.** Numeric summary alone is incomplete.

## 7. Manual rerun (when bash sandbox is down)

If `mcp__workspace__bash` returns "Workspace unavailable", reproduce the collector's output:

- **GitHub**: `WebFetch https://api.github.com/users/imbrandontung` and `.../repos?per_page=100&sort=updated`. Sum `stargazers_count`, `forks_count`.
- **Mintlify**: `WebFetch https://imbrandontung.mintlify.app/sitemap.xml`, count `<url>` (currently 14).
- **NDA scan**: 7 Grep patterns over `*.{md,mdx}` (see § 9). Glob to enumerate, apply EXCLUDED_DIRS + WHITELIST_FILES.
- **Cloudflare**: WebFetch is GET-only; CF GraphQL needs POST. If `cloudflare-token-verify.bat` ran today, copy its `pageviews` / `visits`. Otherwise `{skipped: "manual rerun: web_fetch is GET-only"}`.
- **Articles ranking**: `Grep "\\S+" --count` for non-blank lines (proxy when ripgrep can't `--count-matches`); `Grep "^#+\\s"` for headings; `Grep "^\`\`\`" / 2` for code-block pairs. Recompute score = `lines + headings*10 + code_blocks*50 + (recency<=7d ? 50 : 0)`.
- Write `brand_data.json` + `brand_data.js` directly. Tag each entry `rerun_method: "manual_via_web_fetch_grep"`.
- Append a `==== Manual rerun ====` block to `daily_collector.log`.

## 8. Cloudflare token (`cfut_` prefix is valid)

`cfut_`-prefixed 53-char tokens ARE valid modern Cloudflare API tokens. Don't reject by prefix alone — verify with `cloudflare-token-verify.bat`:

1. `[1/3]` calls `GET /user/tokens/verify`. Want `success=true status=active`.
2. `[2/3]` runs the same GraphQL the collector uses. Want `pageviews` / `visits` numbers.
3. The .ps1 NEVER prints the token; output is safe to share.

Required scope: `Account → Account Analytics → Read`, with the specific account included in Account Resources.

Required config keys: `cloudflare_api_token`, `cloudflare_account_id` (32-char hex), `cloudflare_site_tag` (32-char hex from `dash → Analytics → Web Analytics`, NOT Zone ID).

Troubleshooting:

| Symptom | Cause | Fix |
|---|---|---|
| `[1/3] EXCEPTION 401/403` | Token wrong/revoked | Recreate at dash → Profile → API Tokens |
| `[1/3] success` but `[2/3] errors: unauthorized` | Token missing `Account Analytics:Read` | Re-issue with right permission |
| `[2/3] errors: 'siteTag is invalid'` | Wrong site tag (probably Zone ID) | Get from Web Analytics page |
| `[2/3] 0 accounts matched` | account_id wrong or token not scoped | Fix config or token's "Account Resources" |
| Collector log `Tunnel connection failed: 403` | Bash sandbox egress doesn't include api.cloudflare.com | Settings → Capabilities → add to allowlist |

For per-page PV (future work): extend the GraphQL query with `dimensions: [requestPath]` and merge into `articles.ranked[i].score`.

## 9. NDA scan — 7 patterns

```python
PATTERNS = [
  ("IP-Private",       r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b"),
  ("IP-Public",        r"\b(?!10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|127\.|0\.)(?:\d{1,3}\.){3}\d{1,3}\b"),
  ("Email-Internal",   r"[\w.-]+@(?!gmail|outlook|yahoo|hotmail|protonmail|icloud|github|mintlify|example\.|test\.|localhost|sample\.)[\w.-]+\.\w+"),
  ("Hostname-Pattern", r"\b[A-Z]{2,4}-(?:SRV|DC|FW|SW|RTR|DB|WEB|APP|SIEM|EDR|PAM|IDS)-?\d{1,4}\b"),
  ("Project-Code",     r"\b(?:PRJ|PROJ|CASE|TICKET|JIRA)[-_][A-Z]{0,3}\d{2,8}\b", re.I),
  ("Contract-No",      r"(?:合約|contract|採購單|PO)[號#:\s-]*[A-Z]{0,4}\d{4,}", re.I),
  ("NDA-Trigger",      r"(?:機密(?:資料|文件|等級)?|不對外|\[(?:CONFIDENTIAL|RESTRICTED|PROPRIETARY|INTERNAL[ -]ONLY)\]|//\s*confidential|DO\s*NOT\s*(?:DISTRIBUTE|SHARE|PUBLISH))", re.I),
]
EXCLUDED_DIRS = {".git","node_modules",".venv","__pycache__","analytics-history",".mintignore"}
WHITELIST_FILES = {"SECURITY.md","README.md",".gitignore","LICENSE","LICENSE.md"}
MAX_HITS_PER_FILE = 20
CONTEXT_CHARS = 40
```

Patterns 2/3 use Python negative lookahead — ripgrep doesn't support it. For manual reruns, match broad pattern then post-filter.

The 7 keys MUST be present in `nda[i].by_pattern` even when 0; drift breaks `renderNdaChecklist`.

## 10. Closed-loop verification

After ANY change, verify in Playwright (`browser_navigate` to `about:blank`, then `browser_evaluate`):

1. **Position** — `[...querySelectorAll("h2")].pop()` for "最後面"; index check for "between X and Y".
2. **Render chain** — each `renderXxx` ran without throwing AND its section is in DOM.
3. **Schema sanity** — `D.nda[D.nda.length-1].scanned_files` length matches expected; `D.articles.ranked.length === 15`.
4. **Forbidden strings** — `!document.body.innerHTML.includes("Brand Auto Dashboard")` after title edits.

`file://` is blocked from both Playwright and Chrome MCP. Verify by simulating data + replicating renderer logic in `browser_evaluate` against `about:blank`. Anti-pattern: only counting rows / asserting syntax — DOM position is the most-missed assertion.

## 11. Reply format (Brandon's preferences)

- **English-first** when content is "published" (LinkedIn / Mintlify / GitHub posts) — full EN block before full ZH block, with dual-line `【中文標題】` / `【English Title】` opener. See § 13.
- Chat replies stay 中文 only.
- End every brand-run reply with `[開啟 Dashboard](computer://...NDA_PrePublish_Scorecard.html)`.
- Format when reporting status: Answer → Evidence → Confidence% → Verify Steps.
- No verbose apologies. No emojis unless user uses them.

## 12. Don't-do list

- Don't claim `cfut_` is non-standard without running the verify script.
- Don't collapse the NDA detail table to a single "all clean" line — list every scanned file.
- Don't put `Scanned Files Checklist` anywhere except the bottom.
- Don't load Chart.js without an SVG fallback — Cowork preview CSP blocks the CDN.
- Don't move `const NDA_PATTERN_DEFS` below the orchestration block (TDZ).
- Don't leave duplicated/dead Python at the end of `daily_collector.py`.
- Don't claim closed-loop verification when only row count was checked but DOM position wasn't.

## 13. 跨平台發文 SOP（LinkedIn + Mintlify + GitHub）

**Updated 2026-06-02：** 新增 **§ 13.0 平台分層與受眾鎖定**（受眾 = enterprise architects / CTO / AI infrastructure leaders；禁止 SMB / 中小企業 / 商業導流字眼；違者禁止發布）。完整規則：見 KB-O07。

**Updated 2026-06-01：** 改為 **英文內文在前**，擴大英文讀者觸及；標題只用英文；正文前先以兩行同時呈現中英文標題。適用平台：LinkedIn 貼文、Mintlify 文章、GitHub README / Release Notes / 公開 commit message。

### 13.0 平台分層與受眾鎖定（Platform Tiering — 最高優先）

| 平台 | 定位（離職前）| 受眾 | SMB 字眼 |
|------|--------------|------|----------|
| LinkedIn | 最技術前沿的企業級 AI 架構經驗 | 企業架構師 / CTO / CIO / AI 基礎設施主管 | ❌ 禁 |
| Mintlify (`imbrandontung.mintlify.app`) | 同 LinkedIn（canonical 來源）| 同上 | ❌ 禁 |
| GitHub | 開源樣板、agent skill / SOP / 程式碼 | 開發者、架構師 | ❌ 禁 |
| 未來個人品牌網站（離職後另闢）| SMB 包班 / 顧問 / 客製課程成功案例 | SMB 老闆、決策者 | ✅ 主受眾 |

**強制檢查（每篇 LinkedIn / Mintlify / GitHub 公開文章必過）**

```
□ 全文無 SMB / Small and Medium Business / 中小企業 / 中小型組織 字眼？
□ 主訴對象是企業架構師 / CTO / AI 基礎設施主管，不是「中小企業老闆」？
□ 無商業導流字眼（企業包班、1v1 顧問、客製課程）？
□ Tone 是「最技術前沿」，不是「給中小企業看的入門解說」？
```

任一項為「否」，禁止發布，必須改寫。

商業導流（imBrandon 個人公司目前 TA 是 SMB）走**私域管道**：Email、私訊、客戶介紹。離職後才另闢品牌網站放 SMB 案例。


### 格式（固定順序，不可更動）

```
[Post / Page Title — English only]

【中文標題】
【English Title】

---

[Full English content block]

---

[完整中文版內文]

---

延伸閱讀 / Read more:
https://imbrandontung.mintlify.app/posts/<slug>

#hashtags (EN + ZH merged, no dup)
```

規則：
- **標題（Title field）只用英文**。LinkedIn post title / Mintlify frontmatter `title:` / GitHub release title 皆同。
- 正文開頭兩行：第一行 `【中文標題】`、第二行 `【English Title】`，讓中英讀者都能秒抓主題。
- **英文整段先寫完，才接 `---`，再接中文整段**。不逐段交替。
- Mintlify 連結放最末（LinkedIn / GitHub 才需要；Mintlify 自己是 canonical 就不必）。
- Hashtag 跟在連結之後，中英合併、不重複。

### Mintlify 對應

- Frontmatter `title:` 英文單行。
- 第一段 `【中文標題】` / `【English Title】` 兩行，作為視覺 hook。
- 後續結構同上：English block → `---` → Chinese block → References。
- Heading anchors：英文 heading 用英文 ID，中文 heading 用中文 ID，不共用。

### GitHub 對應

- README、Release Notes、公開 commit message 套用同格式。
- 內部腳本註解、私有 commit 不必雙語。

### Chrome MCP 流程（LinkedIn）

```
1. tabs_context_mcp(createIfEmpty=true)          # 取得 tabId
2. navigate("https://www.linkedin.com/feed/")    # 開 LinkedIn feed
3. find("Start a post / 開始發文")               # 找到貼文框
4. left_click(element)                           # 點擊打開
5. form_input / type — 貼入全文（EN → ZH → 連結）
6. screenshot — 截圖給用戶確認
7. 等待用戶明確授權（"確認發布" / "go"）
8. find("Post / 發布 button") → left_click      # 發布
9. screenshot — 確認貼文已出現在 feed
```

### 安全規則

- 步驟 8 點「Post」前 **必須** 截圖 + 等用戶授權，不可自動送出。
- 不貼公司名稱、客戶名稱、內部專案代碼。
- 若 LinkedIn 要求登入，停下並通知用戶自行登入，不代入密碼。
- GitHub push 同樣須先 `git diff` 截圖等授權；公開 commit message 也走雙語格式。

### Don't-do

- 不貼兩篇（一中一英分開）：一律合併為一篇雙語貼文。
- 不把中文放在英文前面（2026-06-01 之後是 EN first）。
- 不省略 Mintlify 連結（LinkedIn / GitHub 場景）。
- 不在用戶確認前點 Post / Push。
- 標題不要中英並列；標題只用英文。中英標題只放在正文前兩行。

---

## Bundled assets (in this folder)

- `NDA_PrePublish_Scorecard.golden.html` — frozen 2026-04-29 dashboard. Restore source.
- `brand_data.example.js` — example with all fields populated.
- `cloudflare-token-verify.ps1` + `.bat` — token diagnostic (also kept in `打造個人品牌/` root).
