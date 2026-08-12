#!/usr/bin/env python3
"""Probe both keys against both services and time candidate models. No key is printed."""
import json, time, urllib.request, urllib.error, sys

KEYFILE = "/tmp/key"
lines = [l.strip() for l in open(KEYFILE) if l.strip() and not l.startswith("#")]

def get(url, key):
    r = urllib.request.Request(url, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(r, timeout=15) as f:
        return json.load(f)

def post(url, key, payload):
    r = urllib.request.Request(url, data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=30) as f:
        return json.load(f)

print("=== which key works where ===")
cbr_key = orr_key = None
for i, k in enumerate(lines):
    for svc, url in (("cerebras", "https://api.cerebras.ai/v1/models"),
                     ("openrouter", "https://openrouter.ai/api/v1/key")):
        try:
            get(url, k)
            print(f"  line{i+1} -> {svc}: OK")
            if svc == "cerebras": cbr_key = k
            else: orr_key = k
        except urllib.error.HTTPError as e:
            print(f"  line{i+1} -> {svc}: HTTP {e.code}")
        except Exception as e:
            print(f"  line{i+1} -> {svc}: {type(e).__name__}")

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
