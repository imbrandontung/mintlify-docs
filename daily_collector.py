#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
daily_collector.py - Personal Brand Daily Auto Collector
"""
import json, os, re, sys
import urllib.request, urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, date, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_FILE = ROOT / "brand_data.json"
JS_FILE = ROOT / "brand_data.js"
CONFIG_FILE = ROOT / "daily_collector.config.json"
LOG_FILE = ROOT / "daily_collector.log"
LOG_MAX_BYTES = 1_048_576
HISTORY_DIR = ROOT / "analytics-history"
HISTORY_KEEP_DAYS = 90


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > LOG_MAX_BYTES:
            LOG_FILE.rename(LOG_FILE.with_suffix(".log.1"))
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_config():
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
        except Exception as e:
            log(f"WARN: config parse failed: {e}")
    return {}


def _get(url, timeout=10, headers=None):
    h = {"User-Agent": "Mozilla/5.0 (compatible; BrandCollector/1.0; +https://imbrandontung.mintlify.app)"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch_github(username):
    if not username:
        return {"skipped": "no username"}
    try:
        user = json.loads(_get(f"https://api.github.com/users/{urllib.parse.quote(username)}"))
        repos = json.loads(_get(f"https://api.github.com/users/{urllib.parse.quote(username)}/repos?per_page=100&sort=updated"))
        stars = sum(r.get("stargazers_count", 0) for r in repos)
        forks = sum(r.get("forks_count", 0) for r in repos)
        return {"username": username, "followers": user.get("followers", 0), "following": user.get("following", 0),
                "public_repos": user.get("public_repos", 0), "stars": stars, "forks": forks, "fetched": True}
    except Exception as e:
        log(f"GitHub fetch failed: {e}")
        return {"error": str(e), "fetched": False}


def fetch_mintlify(domain):
    if not domain:
        return {"skipped": "no domain"}
    try:
        xml = _get(f"https://{domain}/sitemap.xml")
        try:
            root = ET.fromstring(xml)
            urls = root.findall(".//{http://www.sitemaps.org/schemas/sitemap/0.9}url")
            page_count = len(urls) if urls else xml.count(b"<url>")
        except Exception:
            page_count = xml.count(b"<url>")
        return {"domain": domain, "page_count": int(page_count), "fetched": True}
    except Exception as e:
        log(f"Mintlify sitemap fetch failed: {e}")
        return {"error": str(e), "fetched": False}


def fetch_cloudflare(cfg):
    token = cfg.get("cloudflare_api_token")
    account_id = cfg.get("cloudflare_account_id")
    site_tag = cfg.get("cloudflare_site_tag")
    if not (token and account_id and site_tag):
        return {"skipped": "no credentials"}
    try:
        d = (date.today() - timedelta(days=1)).isoformat()
        query = """
        query($accountTag:String!, $siteTag:String!, $start:Date!, $end:Date!) {
          viewer {
            accounts(filter:{accountTag:$accountTag}) {
              total: rumPageloadEventsAdaptiveGroups(
                filter:{siteTag:$siteTag, date_geq:$start, date_leq:$end}
                limit:1
              ) {
                count
                sum { visits }
              }
            }
          }
        }
        """
        body = json.dumps({"query": query, "variables": {"accountTag": account_id, "siteTag": site_tag, "start": d, "end": d}}).encode("utf-8")
        req = urllib.request.Request("https://api.cloudflare.com/client/v4/graphql", data=body,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "User-Agent": "BrandCollector/1.0"})
        with urllib.request.urlopen(req, timeout=15) as r:
            resp = json.loads(r.read())
        if resp.get("errors"):
            return {"error": str(resp["errors"]), "fetched": False}
        accounts = (resp.get("data") or {}).get("viewer", {}).get("accounts", [])
        if not accounts:
            return {"pageviews": 0, "visits": 0, "visitors": 0, "for_date": d, "fetched": True}
        a = accounts[0]
        total = a.get("total", [{}])[0] if a.get("total") else {}
        return {"pageviews": int(total.get("count", 0) or 0),
                "visits": int((total.get("sum") or {}).get("visits", 0) or 0),
                "visitors": 0, "for_date": d, "fetched": True}
    except Exception as e:
        log(f"Cloudflare fetch failed: {e}")
        return {"error": str(e), "fetched": False}


def fetch_linkedin(cfg):
    token = cfg.get("linkedin_access_token")
    org_urn = cfg.get("linkedin_org_urn")
    if not (token and org_urn):
        return {"skipped": "no token"}
    try:
        url = f"https://api.linkedin.com/v2/networkSizes/{urllib.parse.quote(org_urn)}?edgeType=CompanyFollowedByMember"
        data = json.loads(_get(url, headers={"Authorization": f"Bearer {token}"}))
        return {"followers": int(data.get("firstDegreeSize", 0)), "fetched": True}
    except Exception as e:
        log(f"LinkedIn fetch failed: {e}")
        return {"error": str(e), "fetched": False}


def fetch_agent_checkins(cfg):
    base = cfg.get("agent_endpoint_url")
    if not base:
        return {"skipped": "no agent endpoint configured"}
    try:
        today = date.today().isoformat()
        url = f"{base.rstrip('/')}/agent/stats?since={today}"
        data = json.loads(_get(url, timeout=30))
        return {
            "endpoint": base,
            "today_total": int(data.get("total", 0) or 0),
            "by_agent": data.get("by_agent", {}),
            "by_purpose": data.get("by_purpose", {}),
            "fetched": True,
        }
    except Exception as e:
        log(f"Agent stats fetch failed: {e}")
        return {"error": str(e), "fetched": False}


PATTERNS = [
    ("IP-Private", re.compile(r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b")),
    ("IP-Public", re.compile(r"\b(?!10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|127\.|0\.)(?:\d{1,3}\.){3}\d{1,3}\b")),
    ("Email-Internal", re.compile(r"[\w.-]+@(?!gmail|outlook|yahoo|hotmail|protonmail|icloud|github|mintlify|example\.|test\.|localhost|sample\.)[\w.-]+\.\w+")),
    ("Hostname-Pattern", re.compile(r"\b[A-Z]{2,4}-(?:SRV|DC|FW|SW|RTR|DB|WEB|APP|SIEM|EDR|PAM|IDS)-?\d{1,4}\b")),
    ("Project-Code", re.compile(r"\b(?:PRJ|PROJ|CASE|TICKET|JIRA)[-_][A-Z]{0,3}\d{2,8}\b", re.I)),
    ("Contract-No", re.compile(r"(?:合約|contract|採購單|PO)[號#:\s-]*[A-Z]{0,4}\d{4,}", re.I)),
    ("NDA-Trigger", re.compile(r"(?:機密(?:資料|文件|等級)?|不對外|\[(?:CONFIDENTIAL|RESTRICTED|PROPRIETARY|INTERNAL[ -]ONLY)\]|//\s*confidential|DO\s*NOT\s*(?:DISTRIBUTE|SHARE|PUBLISH))", re.I)),
]

EXCLUDED_DIRS = {".git", "node_modules", ".venv", "__pycache__", "analytics-history", ".mintignore", ".skill"}
WHITELIST_FILES = {"SECURITY.md", "README.md", ".gitignore", "LICENSE", "LICENSE.md"}
MAX_HITS_PER_FILE = 20
CONTEXT_CHARS = 40


def scan_nda():
    targets = []
    for pattern in ("**/*.md", "**/*.mdx"):
        for p in ROOT.glob(pattern):
            if any(part in EXCLUDED_DIRS for part in p.parts):
                continue
            if p.name in WHITELIST_FILES:
                continue
            targets.append(p)
    by_file = []
    total_hits = 0
    pattern_totals = {label: 0 for label, _ in PATTERNS}
    for p in targets:
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        lines = text.split("\n")
        file_pattern_counts = {}
        snippets = []
        for label, pat in PATTERNS:
            for line_no, line in enumerate(lines, 1):
                for m in pat.finditer(line):
                    file_pattern_counts[label] = file_pattern_counts.get(label, 0) + 1
                    pattern_totals[label] += 1
                    total_hits += 1
                    if len(snippets) < MAX_HITS_PER_FILE:
                        start = max(0, m.start() - CONTEXT_CHARS)
                        end = min(len(line), m.end() + CONTEXT_CHARS)
                        snippets.append({"line": line_no, "pattern": label, "match": m.group(), "context": line[start:end].strip()})
        if file_pattern_counts:
            try:
                rel = str(p.relative_to(ROOT))
            except Exception:
                rel = p.name
            hits_arr = [{"pattern": k, "count": v} for k, v in file_pattern_counts.items()]
            by_file.append({"file": rel, "hits": hits_arr, "total": sum(h["count"] for h in hits_arr), "snippets": snippets})
    by_file.sort(key=lambda x: x["total"], reverse=True)
    scanned_files = []
    for p in targets:
        try:
            scanned_files.append(str(p.relative_to(ROOT)).replace("\\", "/"))
        except Exception:
            scanned_files.append(p.name)
    scanned_files.sort()
    return {"total_hits": total_hits, "files_scanned": len(targets), "files_with_hits": len(by_file),
            "by_pattern": pattern_totals, "by_file": by_file, "scanned_files": scanned_files}


def _extract_title(text, fallback):
    m = re.search(r'^---\s*\n(.*?)\n---', text, re.DOTALL | re.MULTILINE)
    if m:
        fm = m.group(1)
        t = re.search(r'^title:\s*["\']?(.+?)["\']?\s*$', fm, re.MULTILINE)
        if t:
            return t.group(1).strip().strip('"\'')
    h = re.search(r'^#\s+(.+)$', text, re.MULTILINE)
    if h:
        return h.group(1).strip()
    return fallback


def compute_articles():
    targets = []
    for p in ROOT.glob("**/*.mdx"):
        if any(part in EXCLUDED_DIRS for part in p.parts):
            continue
        targets.append(p)
    now = datetime.now(timezone.utc)
    rows = []
    for p in targets:
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        lines = text.splitlines()
        non_blank = sum(1 for l in lines if l.strip())
        headings = sum(1 for l in lines if l.lstrip().startswith("#"))
        code_blocks = text.count("```") // 2
        mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc)
        recency_days = (now - mtime).days
        recency_bonus = 50 if recency_days <= 7 else 0
        score = non_blank + headings * 10 + code_blocks * 50 + recency_bonus
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        url = "/" + rel.replace(".mdx", "")
        if url == "/index":
            url = "/"
        rows.append({"file": rel, "url": url,
                     "title": _extract_title(text, p.stem.replace("-", " ").title()),
                     "lines": len(lines), "headings": headings, "code_blocks": code_blocks,
                     "last_modified": mtime.isoformat(), "recency_days": recency_days, "score": score})
    rows.sort(key=lambda r: r["score"], reverse=True)
    for i, r in enumerate(rows, 1):
        r["rank"] = i
    return {"as_of": date.today().isoformat(),
            "score_formula": "non_blank_lines + headings*10 + code_blocks*50 + (recency<=7d ? 50 : 0)",
            "score_note": "Proxy score until Cloudflare/LinkedIn analytics wired in",
            "ranked": rows}


def main():
    today = date.today().isoformat()
    cfg = load_config()
    log(f"==== Daily run start: {today} ====")
    if DATA_FILE.exists():
        try:
            data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
        except Exception as e:
            log(f"WARN: brand_data.json parse failed: {e}")
            data = {"schema": "v3", "nda": [], "metrics": []}
    else:
        data = {"schema": "v3", "nda": [], "metrics": []}
    if "nda" not in data:
        data["nda"] = []
    if "metrics" not in data:
        data["metrics"] = []
    gh = fetch_github(cfg.get("github_username", "imbrandontung"))
    mintlify = fetch_mintlify(cfg.get("mintlify_domain", "imbrandontung.mintlify.app"))
    cloudflare = fetch_cloudflare(cfg)
    linkedin = fetch_linkedin(cfg)
    agent = fetch_agent_checkins(cfg)
    nda = scan_nda()
    log(f"GitHub: {gh}")
    log(f"Mintlify: {mintlify}")
    log(f"Cloudflare: {cloudflare}")
    log(f"LinkedIn: {linkedin}")
    log(f"Agent: {agent}")
    log(f"NDA scan: total_hits={nda['total_hits']} files_with_hits={nda['files_with_hits']}/{nda['files_scanned']}")
    nda_entry = {"date": today, "hits": nda["total_hits"], "files_scanned": nda["files_scanned"],
                 "files_with_hits": nda["files_with_hits"], "by_pattern": nda["by_pattern"],
                 "by_file": nda["by_file"], "scanned_files": nda.get("scanned_files", []),
                 "ts": datetime.now(timezone.utc).isoformat()}
    data["nda"] = [x for x in data["nda"] if x.get("date") != today] + [nda_entry]
    data["nda"].sort(key=lambda x: x.get("date", ""))
    metrics_entry = {"date": today, "github": gh, "mintlify": mintlify, "cloudflare": cloudflare,
                     "linkedin": linkedin, "agent": agent, "ts": datetime.now(timezone.utc).isoformat()}
    data["metrics"] = [x for x in data["metrics"] if x.get("date") != today] + [metrics_entry]
    data["metrics"].sort(key=lambda x: x.get("date", ""))
    data["articles"] = compute_articles()
    log(f"Articles: {len(data['articles']['ranked'])} ranked, top={data['articles']['ranked'][0]['file'] if data['articles']['ranked'] else 'none'}")
    data["last_run"] = datetime.now(timezone.utc).isoformat()
    data["last_run_local"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    data["schema"] = "v3"
    DATA_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    # Daily backup to analytics-history/
    try:
        HISTORY_DIR.mkdir(exist_ok=True)
        bak = HISTORY_DIR / f"brand_data_{today}.json"
        bak.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        cutoff = (date.today() - timedelta(days=HISTORY_KEEP_DAYS)).isoformat()
        for bfile in HISTORY_DIR.glob("brand_data_*.json"):
            try:
                if bfile.stem.split("_", 2)[-1] < cutoff:
                    bfile.unlink()
            except Exception:
                pass
        log(f"Backup -> analytics-history/{bak.name}")
    except Exception as e:
        log(f"WARN: backup failed: {e}")

    js_blob = "// Auto-generated by daily_collector.py - DO NOT EDIT\n"
    js_blob += "// Last run: " + data["last_run_local"] + "\n"
    js_blob += "window.BRAND_DATA = " + json.dumps(data, ensure_ascii=False, indent=2) + ";\n"
    JS_FILE.write_text(js_blob, encoding="utf-8")
    log(f"Wrote {DATA_FILE.name} ({DATA_FILE.stat().st_size} bytes)")
    log(f"Wrote {JS_FILE.name} ({JS_FILE.stat().st_size} bytes)")
    log(f"==== Daily run end: {today} ====\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
