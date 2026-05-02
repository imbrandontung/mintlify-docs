# Agent-Native Endpoint — Brandon Tung

純 agent 用，**不為人類設計**。Pure agent surface — not designed for humans.

---

## 架構 / Architecture

```
human side                       agent side
imbrandontung.mintlify.app       imbrandontung-agent.<sub>.workers.dev
  └ MDX content (Mintlify)         ├ GET  /llms.txt
                                    ├ GET  /llms-full.txt
                                    ├ GET  /.well-known/agent-manifest.json
                                    ├ POST /agent/checkin
                                    ├ POST /agent/event
                                    └ GET  /agent/checkins (admin)
```

`brand_data.json` daily_collector pulls KV → dashboard 顯示「N agents 今日報到」。

---

## 檔案佈局 / Layout

```
agent/
├ build_llms.py              # 從 .mdx 產生 llms.txt + llms-full.txt
├ agent-manifest.json        # 靜態，直接編輯
├ llms.txt                   # 由 build_llms.py 產生（每次 .mdx 變動重跑）
├ llms-full.txt              # 同上
├ README.md                  # 本檔
└ worker/
   ├ wrangler.toml           # Cloudflare Worker 部署設定
   ├ public/                 # 靜態檔案（部署時 wrangler 上傳）
   │  ├ llms.txt             # ← cp from agent/llms.txt
   │  ├ llms-full.txt        # ← cp from agent/llms-full.txt
   │  └ agent-manifest.json  # ← cp from agent/agent-manifest.json
   └ src/index.js            # Worker 邏輯
```

---

## 首次部署步驟 / Initial deployment

```bash
# 0. 安裝 wrangler (一次性)
npm install -g wrangler

# 1. 登入 Cloudflare
cd agent/worker
wrangler login

# 2. 建立 KV namespace
wrangler kv:namespace create "AGENT_KV"
# → 把回傳的 id 填回 wrangler.toml 的 [[kv_namespaces]] id 欄位

# 3. 設定 admin token (用來讀取 /agent/checkins)
wrangler secret put ADMIN_TOKEN
# 隨機產生一個 32+ char 的 token，記在 password manager

# 4. 產生最新靜態檔
cd ../..   # 回到 repo root
python3 agent/build_llms.py
cp agent/llms.txt agent/llms-full.txt agent/agent-manifest.json agent/worker/public/

# 5. 部署
cd agent/worker
wrangler deploy

# 部署後 URL（複製給我，我會更新 manifest 中的 URL）：
#   https://imbrandontung-agent.<your-subdomain>.workers.dev
```

---

## 日常更新流程 / Routine update

每次 `.mdx` 內容變動：
```bash
python3 agent/build_llms.py
cp agent/llms.txt agent/llms-full.txt agent/worker/public/
cd agent/worker && wrangler deploy
```

可寫進 `daily_collector.py` 自動化（待 Brandon 確認部署後再接）。

---

## Agent 端使用範例 / Sample agent usage

### 1) 發現 (Discovery)
```bash
curl https://imbrandontung-agent.<sub>.workers.dev/.well-known/agent-manifest.json
```

### 2) 報到 (Check-in)
```bash
curl -X POST https://imbrandontung-agent.<sub>.workers.dev/agent/checkin \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "claude-sonnet-4.6",
    "operator": "user@example.com",
    "purpose": "research",
    "intent_summary": "尋找 AI Agent security 相關文章"
  }'
```

回傳：
```json
{
  "session_token": "uuid",
  "ttl_sec": 3600,
  "links": { "content_index": "/llms.txt", ... }
}
```

### 3) 讀內容
```bash
curl https://imbrandontung-agent.<sub>.workers.dev/llms-full.txt
```

### 4) 回報事件 (optional)
```bash
curl -X POST https://imbrandontung-agent.<sub>.workers.dev/agent/event \
  -H "Content-Type: application/json" \
  -d '{
    "session_token": "<uuid>",
    "event_type": "read",
    "url": "/posts/gcnext26-agent-security",
    "dwell_ms": 32000
  }'
```

### 5) Brandon 觀測 (admin)
```bash
curl https://imbrandontung-agent.<sub>.workers.dev/agent/checkins?since=2026-04-30 \
  -H "Authorization: Bearer <ADMIN_TOKEN>"
```

---

## 安全備註 / Security notes

- IP 不存原值，只存 SHA-256 前 6 bytes 的 hash（避免 PII 落地）
- `ADMIN_TOKEN` 是 secret，**不寫進 repo**，用 `wrangler secret put` 儲存
- KV 預設 90 天 TTL，過期自動清除
- Worker 預設無 rate limit，被濫用時加 Cloudflare Rate Limit Rules
- CORS `*` — 開放給所有 agent，無需 preflight 認證
- 所有資料公開（站內容是公開的），check-in 紀錄屬營運觀測，policy 已寫入 manifest

---

## 待辦 / TODO

- [ ] 部署 Worker（Brandon 動手，跟著上面步驟）
- [ ] 驗證 endpoints 回應正常
- [ ] 把 worker URL 更新到 `agent-manifest.json` 的 endpoints 欄位
- [ ] 加 `fetch_agent_checkins()` 到 `daily_collector.py`，把 KV 數字拉進 dashboard
- [ ] （未來）自訂域名 `agent.brandontung.tw`
- [ ] （未來）GitHub OIDC 取代 anonymous，給可信 agent 高 rate limit
