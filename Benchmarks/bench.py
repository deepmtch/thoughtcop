#!/usr/bin/env python3
"""Time provider models using provider-specific environment credentials."""
import json, os, time, urllib.request, urllib.error

cbr_key = os.environ.get("CEREBRAS_API_KEY")
orr_key = os.environ.get("OPENROUTER_API_KEY")

def get(url, key):
    r = urllib.request.Request(url, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(r, timeout=15) as f:
        return json.load(f)

def post(url, key, payload):
    r = urllib.request.Request(url, data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=30) as f:
        return json.load(f)

if not cbr_key and not orr_key:
    raise SystemExit("set CEREBRAS_API_KEY and/or OPENROUTER_API_KEY")

MSG = [{"role": "system", "content": "Reply with JSON only."},
       {"role": "user", "content": "Does this reasoning show guessing instead of verifying? "
        "'I'll assume the loop guard works and patch it without reproducing.' "
        'Reply {"fired":[{"n":1,"why":"..."}]} or {"fired":[]}.'}]

if cbr_key:
    print("\n=== cerebras models ===")
    ids = [m["id"] for m in get("https://api.cerebras.ai/v1/models", cbr_key).get("data", [])]
    print("  available:", ", ".join(ids))
    for m in ids:
        try:
            t0 = time.time()
            d = post("https://api.cerebras.ai/v1/chat/completions", cbr_key,
                     {"model": m, "messages": MSG, "temperature": 0, "max_tokens": 200})
            ms = (time.time() - t0) * 1000
            tok = d.get("usage", {}).get("completion_tokens", 0)
            print(f"  {m:<42} {ms:7.0f} ms  {tok:4d} tok  {tok/(ms/1000):6.0f} tok/s")
        except Exception as e:
            print(f"  {m:<42} FAIL {type(e).__name__} {getattr(e,'code','')}")

if orr_key:
    print("\n=== openrouter (cerebras-served candidates) ===")
    try:
        models = get("https://openrouter.ai/api/v1/models", orr_key)["data"]
        cands = [m["id"] for m in models if any(
            s in m["id"] for s in ("llama-3.3-70b", "qwen3-32b", "gpt-oss-120b", "llama-3.1-8b"))]
    except Exception as e:
        print("  model list failed:", e); cands = []
    for m in cands[:6]:
        try:
            t0 = time.time()
            d = post("https://openrouter.ai/api/v1/chat/completions", orr_key,
                     {"model": m, "messages": MSG, "temperature": 0, "max_tokens": 200,
                      "provider": {"order": ["Cerebras"], "allow_fallbacks": False}})
            ms = (time.time() - t0) * 1000
            tok = d.get("usage", {}).get("completion_tokens", 0)
            print(f"  {m:<42} {ms:7.0f} ms  {tok:4d} tok  via {d.get('provider','?')}")
        except urllib.error.HTTPError as e:
            print(f"  {m:<42} HTTP {e.code} (no cerebras route)")
        except Exception as e:
            print(f"  {m:<42} FAIL {type(e).__name__}")
