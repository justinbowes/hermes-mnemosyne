"""Build-time assertion: Hermes base must be >= 0.19.0.

Prevents accidentally building from a stale base tag that predates critical
fixes (dashboard auth, perf improvements, SimpleX structured send).
"""
import sys
from importlib.metadata import version

v = version("hermes-agent")
parts = [int(x) for x in v.split(".")[:3]]
if parts < [0, 19, 0]:
    print(f"FAIL: Hermes {v} is older than 0.19.0 — stale base tag?", file=sys.stderr)
    sys.exit(1)

print(f"OK: Hermes version {v} >= 0.19.0")
