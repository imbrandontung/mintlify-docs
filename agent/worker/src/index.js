/**
 * Brandon Tung — Agent Endpoint Worker
 * ====================================
 * Cloudflare Worker exposing agent-only endpoints:
 *   GET  /llms.txt                      — site index (LLM-friendly)
 *   GET  /llms-full.txt                 — full corpus
 *   GET  /.well-known/agent-manifest.json — discovery
 *   POST /agent/checkin                  — agent registers presence
 *   POST /agent/event                    — agent reports activity
 *   GET  /agent/checkins?since=ISO8601   — observability (admin only)
 *
 * KV binding required: AGENT_KV (configured in wrangler.toml)
 * Secret required:     ADMIN_TOKEN (for /agent/checkins read-back)
 *
 * Static content (llms.txt, manifest) is bundled at build time via wrangler.
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
      ...extraHeaders,
    },
  });
}

function text(body, status = 200, contentType = "text/plain; charset=utf-8") {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=300",
      ...CORS_HEADERS,
    },
  });
}

function nowIso() {
  return new Date().toISOString();
}

function uuid() {
  // Cloudflare Workers expose crypto.randomUUID()
  return crypto.randomUUID();
}

async function handleCheckin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "invalid_json" }, 400);
  }

  // Validate minimum fields — be lenient: agents are diverse
  const agent_id = String(body.agent_id || "unknown").slice(0, 200);
  const operator = String(body.operator || "anonymous").slice(0, 200);
  const purpose = String(body.purpose || "read").slice(0, 50);
  const intent = String(body.intent_summary || "").slice(0, 500);

  // Build session record
  const session_id = uuid();
  const ts = nowIso();
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const ua = request.headers.get("User-Agent") || "";
  const country = request.cf?.country || "??";

  const record = {
    session_id,
    agent_id,
    operator,
    purpose,
    intent,
    ts,
    ip_hash: await sha256Short(ip),  // hashed, not raw IP
    ua,
    country,
  };

  // Write to KV with 90-day TTL + metadata (so /agent/stats can aggregate without KV.get per record)
  await env.AGENT_KV.put(
    `checkin:${ts}:${session_id}`,
    JSON.stringify(record),
    {
      expirationTtl: 60 * 60 * 24 * 90,
      metadata: { agent_id, purpose }
    }
  );

  // Increment daily counter for the dashboard
  const dayKey = `count:day:${ts.slice(0, 10)}`;
  const cur = parseInt((await env.AGENT_KV.get(dayKey)) || "0", 10);
  await env.AGENT_KV.put(dayKey, String(cur + 1), { expirationTtl: 60 * 60 * 24 * 365 });

  return json({
    session_token: session_id,
    ttl_sec: 3600,
    rate_limit: "30/min",
    preferred_format: "markdown",
    links: {
      content_index: "/llms.txt",
      content_full: "/llms-full.txt",
      event_endpoint: "/agent/event",
    },
    note: "Welcome. Brandon's site is agent-friendly. Identify yourself in subsequent /agent/event calls.",
  });
}

async function handleEvent(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "invalid_json" }, 400);
  }
  const session_id = String(body.session_token || body.session_id || "unknown").slice(0, 100);
  const event_type = String(body.event_type || "read").slice(0, 50);
  const url_path = String(body.url || body.path || "").slice(0, 500);
  const dwell_ms = Math.min(parseInt(body.dwell_ms || "0", 10), 600000);
  const ts = nowIso();

  await env.AGENT_KV.put(
    `event:${ts}:${session_id}:${event_type}`,
    JSON.stringify({ session_id, event_type, url_path, dwell_ms, ts }),
    { expirationTtl: 60 * 60 * 24 * 90 }
  );
  return json({ ok: true, ts });
}

async function handleListCheckins(request, env) {
  // Admin-only: requires Bearer ADMIN_TOKEN
  const auth = request.headers.get("Authorization") || "";
  if (auth !== `Bearer ${env.ADMIN_TOKEN}`) {
    return json({ error: "unauthorized" }, 401);
  }
  const url = new URL(request.url);
  const since = url.searchParams.get("since") || "";
  const list = await env.AGENT_KV.list({ prefix: "checkin:" });
  const records = [];
  for (const k of list.keys) {
    if (since && k.name.split(":")[1] < since) continue;
    const v = await env.AGENT_KV.get(k.name);
    if (v) records.push(JSON.parse(v));
  }
  return json({ count: records.length, since, records });
}

async function handleStats(request, env) {
  // Public-read aggregate stats — no PII, no admin token required.
  // Returns counts by agent_id and purpose, since optional date filter.
  const url = new URL(request.url);
  const since = url.searchParams.get("since") || "";
  const list = await env.AGENT_KV.list({ prefix: "checkin:" });
  // Filter keys by since first, then parallelize the KV reads (much faster than sequential await)
  const keys = list.keys.filter(k => !since || k.name.split(":")[1] >= since);
  // Prefer metadata (added at write time) — fall back to KV.get for legacy records
  const values = await Promise.all(keys.map(async (k) => {
    if (k.metadata && (k.metadata.agent_id || k.metadata.purpose)) return k.metadata;
    const v = await env.AGENT_KV.get(k.name);
    if (!v) return null;
    try { return JSON.parse(v); } catch { return null; }
  }));
  let total = 0;
  const by_agent = {};
  const by_purpose = {};
  for (const r of values) {
    if (!r) continue;
    total += 1;
    const aid = r.agent_id || "unknown";
    by_agent[aid] = (by_agent[aid] || 0) + 1;
    const p = r.purpose || "unknown";
    by_purpose[p] = (by_purpose[p] || 0) + 1;
  }
  return json({ total, by_agent, by_purpose, since, generated_at: nowIso() });
}

async function sha256Short(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].slice(0, 6).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Static files baked at deploy time via wrangler [assets] / [text_blobs]
// For MVP, just inline minimal placeholders; replace with assets binding later
const PLACEHOLDER_LLMS_TXT = `# Brandon Tung\n\n> Replace via wrangler asset binding. Run agent/build_llms.py and bind output dir.\n\n- See https://imbrandontung.mintlify.app for human-readable content.\n`;
const PLACEHOLDER_MANIFEST = { error: "manifest not bundled — bind agent/agent-manifest.json via [assets]" };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // CORS preflight
    if (method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // Static-ish endpoints — prefer assets binding (env.ASSETS) when configured
    if (method === "GET" && path === "/llms.txt") {
      const fromAssets = env.ASSETS ? await env.ASSETS.fetch(new Request(new URL("/llms.txt", request.url))) : null;
      if (fromAssets && fromAssets.ok) {
        return new Response(await fromAssets.text(), { headers: { ...CORS_HEADERS, "Content-Type": "text/plain; charset=utf-8" } });
      }
      return text(PLACEHOLDER_LLMS_TXT);
    }
    if (method === "GET" && path === "/llms-full.txt") {
      const fromAssets = env.ASSETS ? await env.ASSETS.fetch(new Request(new URL("/llms-full.txt", request.url))) : null;
      if (fromAssets && fromAssets.ok) {
        return new Response(await fromAssets.text(), { headers: { ...CORS_HEADERS, "Content-Type": "text/plain; charset=utf-8" } });
      }
      return text("# llms-full.txt not bundled yet. Run agent/build_llms.py and redeploy.");
    }
    if (method === "GET" && path === "/.well-known/agent-manifest.json") {
      const fromAssets = env.ASSETS ? await env.ASSETS.fetch(new Request(new URL("/agent-manifest.json", request.url))) : null;
      if (fromAssets && fromAssets.ok) {
        return new Response(await fromAssets.text(), { headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" } });
      }
      return json(PLACEHOLDER_MANIFEST, 503);
    }

    // Agent dynamic endpoints
    if (method === "POST" && path === "/agent/checkin") {
      return handleCheckin(request, env);
    }
    if (method === "POST" && path === "/agent/event") {
      return handleEvent(request, env);
    }
    if (method === "GET" && path === "/agent/checkins") {
      return handleListCheckins(request, env);
    }
    if (method === "GET" && path === "/agent/stats") {
      return handleStats(request, env);
    }

    if (method === "GET" && path === "/") {
      return json({
        message: "Brandon Tung — Agent Endpoint",
        manifest: "/.well-known/agent-manifest.json",
        index: "/llms.txt",
        checkin: "POST /agent/checkin",
      });
    }

    return json({ error: "not_found", path }, 404);
  },
};
