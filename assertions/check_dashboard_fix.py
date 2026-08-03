"""Build-time assertion: dashboard env-reveal must not use pre-fix getSessionToken pattern.

Upstream issue #55210 (fixed by commit 3e24b16f): the gated dashboard's
revealEnvVar previously called getSessionToken() directly, leaking the session
token. This assertion catches regressions on base-tag downgrades.
"""
import pathlib
import sys

spa = pathlib.Path("/opt/hermes/web/dist")
if not spa.exists():
    print("SKIP: no compiled SPA found at /opt/hermes/web/dist")
    sys.exit(0)

js_files = list(spa.rglob("*.js"))
if not js_files:
    print("SKIP: no JS files in SPA dist")
    sys.exit(0)

hits = []
for f in js_files:
    content = f.read_text(errors="ignore")
    if "getSessionToken" in content and "env/reveal" in content:
        hits.append(str(f))

if hits:
    print(f"FAIL: compiled SPA still uses getSessionToken+env/reveal: {hits}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(js_files)} SPA JS files checked, no pre-fix env/reveal pattern found")
