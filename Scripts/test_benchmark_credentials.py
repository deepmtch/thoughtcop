#!/usr/bin/env python3
"""Keep benchmark credentials scoped to their actual network provider."""

from pathlib import Path


bench = Path("Benchmarks/bench.py").read_text()
bench2 = Path("Benchmarks/bench2.py").read_text()

assert 'os.environ.get("CEREBRAS_API_KEY")' in bench
assert 'os.environ.get("OPENROUTER_API_KEY")' in bench
assert 'os.environ.get("OPENROUTER_API_KEY")' in bench2
combined = bench + bench2
assert "/tmp/key" not in combined
assert 'os.environ.get("GROQ_API_KEY")' not in combined
assert "api.groq.com" not in combined

print("benchmark credentials: providerScoped=true temporaryFile=false")
