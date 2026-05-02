var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.js
var CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400"
};
function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
      ...extraHeaders
    }
  });
}
__name(json, "json");
function text(body, status = 200, contentType = "text/plain; charset=utf-8") {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=300",
      ...CORS_HEADERS
    }
  });
}
__name(text, "text");
function nowIso() {
  return (/* @__PURE__ */ new Date()).toISOString();
}
__name(nowIso, "nowIso");
function uuid() {
  return crypto.randomUUID();
}
__name(uuid, "uuid");
async function handleCheckin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "invalid_json" }, 400);
  }
  const agent_id = String(body.agent_id || "unknown").slice(0, 200);
  const operator = String(body.operator || "anonymous").slice(0, 200);
  const purpose = String(body.purpose || "read").slice(0, 50);
  const intent = String(body.intent_summary || "").slice(0, 500);
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
    ip_hash: await sha256Short(ip),
    // hashed, not raw IP
    ua,
    country
  };
  await env.AGENT_KV.put(
    `checkin:${ts}:${session_id}`,
    JSON.stringify(record),
    { expirationTtl: 60 * 60 * 24 * 90 }
  );
  const dayKey = `count:day:${ts.slice(0, 10)}`;
  const cur = parseInt(await env.AGENT_KV.get(dayKey) || "0", 10);
  await env.AGENT_KV.put(dayKey, String(cur + 1), { expirationTtl: 60 * 60 * 24 * 365 });
  return json({
    session_token: session_id,
    ttl_sec: 3600,
    rate_limit: "30/min",
    preferred_format: "markdown",
    links: {
      content_index: "/llms.txt",
      content_full: "/llms-full.txt",
      event_endpoint: "/agent/event"
    },
    note: "Welcome. Brandon's site is agent-friendly. Identify yourself in subsequent /agent/event calls."
  });
}
__name(handleCheckin, "handleCheckin");
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
  const dwell_ms = Math.min(parseInt(body.dwell_ms || "0", 10), 6e5);
  const ts = nowIso();
  await env.AGENT_KV.put(
    `event:${ts}:${session_id}:${event_type}`,
    JSON.stringify({ session_id, event_type, url_path, dwell_ms, ts }),
    { expirationTtl: 60 * 60 * 24 * 90 }
  );
  return json({ ok: true, ts });
}
__name(handleEvent, "handleEvent");
async function handleListCheckins(request, env) {
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
__name(handleListCheckins, "handleListCheckins");
async function handleStats(request, env) {
  const url = new URL(request.url);
  const since = url.searchParams.get("since") || "";
  const list = await env.AGENT_KV.list({ prefix: "checkin:" });
  let total = 0;
  const by_agent = {};
  const by_purpose = {};
  for (const k of list.keys) {
    if (since && k.name.split(":")[1] < since) continue;
    const v = await env.AGENT_KV.get(k.name);
    if (!v) continue;
    let r;
    try {
      r = JSON.parse(v);
    } catch {
      continue;
    }
    total += 1;
    const aid = r.agent_id || "unknown";
    by_agent[aid] = (by_agent[aid] || 0) + 1;
    const p = r.purpose || "unknown";
    by_purpose[p] = (by_purpose[p] || 0) + 1;
  }
  return json({ total, by_agent, by_purpose, since, generated_at: nowIso() });
}
__name(handleStats, "handleStats");
async function sha256Short(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].slice(0, 6).map((b) => b.toString(16).padStart(2, "0")).join("");
}
__name(sha256Short, "sha256Short");
var PLACEHOLDER_LLMS_TXT = `# Brandon Tung

> Replace via wrangler asset binding. Run agent/build_llms.py and bind output dir.

- See https://imbrandontung.mintlify.app for human-readable content.
`;
var PLACEHOLDER_MANIFEST = { error: "manifest not bundled \u2014 bind agent/agent-manifest.json via [assets]" };
var index_default = {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    if (method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
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
        message: "Brandon Tung \u2014 Agent Endpoint",
        manifest: "/.well-known/agent-manifest.json",
        index: "/llms.txt",
        checkin: "POST /agent/checkin"
      });
    }
    return json({ error: "not_found", path }, 404);
  }
};
export {
  index_default as default
};
//# sourceMappingURL=index.js.map
