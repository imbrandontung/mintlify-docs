#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_llms.py — generate llms.txt + llms-full.txt from .mdx files.
Run: python3 agent/build_llms.py
Output: agent/llms.txt, agent/llms-full.txt
Reference: https://llmstxt.org/ (draft standard)
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "agent"
SITE_NAME = "Brandon Tung"
SITE_DESC = "Agent，從營運現場長出來。Agents, grown on the ops floor."
SITE_URL = "https://imbrandontung.mintlify.app"

EXCLUDED_DIRS = {".git", "node_modules", ".venv", "__pycache__", ".skill", "agent"}


def extract_frontmatter(text):
    m = re.search(r'^---\s*\n(.*?)\n---', text, re.DOTALL | re.MULTILINE)
    if not m:
        return {}, text
    fm_text = m.group(1)
    body = text[m.end():].lstrip()
    fm = {}
    for line in fm_text.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"\'')
    return fm, body


def collect_articles():
    articles = []
    for p in ROOT.glob("**/*.mdx"):
        if any(part in EXCLUDED_DIRS for part in p.parts):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except Exception:
            continue
        fm, body = extract_frontmatter(text)
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        url_path = "/" + rel.replace(".mdx", "")
        if url_path == "/index":
            url_path = "/"
        articles.append({
            "path": rel,
            "url": SITE_URL + url_path,
            "title": fm.get("title", p.stem),
            "description": fm.get("description", ""),
            "body": body,
        })
    articles.sort(key=lambda a: a["path"])
    return articles


def build_llms_txt(articles):
    """Concise index — one-liner per article. ~5 KB."""
    lines = [
        f"# {SITE_NAME}",
        "",
        f"> {SITE_DESC}",
        "",
        "Brandon Tung (童國鎮) — AI Security Architect / Dynasafe Digital COE Lead.",
        "25 years in enterprise security & IT operations. AI Agent strategy, TOGAF EA, NPI.",
        "",
        "## Pages",
        "",
    ]
    for a in articles:
        title = a["title"]
        desc = a["description"]
        if desc:
            lines.append(f"- [{title}]({a['url']}): {desc}")
        else:
            lines.append(f"- [{title}]({a['url']})")
    lines.append("")
    lines.append("## Machine Endpoints")
    lines.append("")
    lines.append("- Agent manifest: /.well-known/agent-manifest.json")
    lines.append("- Full content: /llms-full.txt")
    lines.append("- Check-in: POST /agent/checkin")
    lines.append("")
    return "\n".join(lines)


def build_llms_full_txt(articles):
    """Full corpus — every article concatenated. agent reads once, knows everything."""
    out = [
        f"# {SITE_NAME} — Full Corpus",
        "",
        f"> {SITE_DESC}",
        "",
        f"Source: {SITE_URL}",
        f"Articles: {len(articles)}",
        "",
        "---",
        "",
    ]
    for a in articles:
        out.append(f"# {a['title']}")
        out.append("")
        out.append(f"URL: {a['url']}")
        if a["description"]:
            out.append(f"Description: {a['description']}")
        out.append("")
        out.append(a["body"])
        out.append("")
        out.append("---")
        out.append("")
    return "\n".join(out)


def main():
    articles = collect_articles()
    print(f"Found {len(articles)} articles")
    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "llms.txt").write_text(build_llms_txt(articles), encoding="utf-8")
    (OUT_DIR / "llms-full.txt").write_text(build_llms_full_txt(articles), encoding="utf-8")
    print(f"Wrote {OUT_DIR}/llms.txt ({(OUT_DIR / 'llms.txt').stat().st_size} bytes)")
    print(f"Wrote {OUT_DIR}/llms-full.txt ({(OUT_DIR / 'llms-full.txt').stat().st_size} bytes)")


if __name__ == "__main__":
    main()
