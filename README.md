# hermes-mnemosyne

A **thin derived image**: the official [Hermes Agent](https://github.com/NousResearch/hermes-agent)
image with the [Mnemosyne](https://pypi.org/project/mnemosyne-memory/) memory
provider baked in.

```
FROM nousresearch/hermes-agent:<pinned>   # official published image
RUN uv pip install mnemosyne-memory==<pinned>
COPY plugins/memory/mnemosyne/ ...        # bundled provider shim
```

No source fork. No rebasing. We layer on top of a **pinned upstream tag** and
add exactly one dependency plus a small provider shim. Upstream ships a new
version → bump one file, rebuild, redeploy.

Published to: **`ghcr.io/justinbowes/hermes-mnemosyne`**

---

## Why this exists (and why not the alternatives)

Mnemosyne needs to be importable by the Hermes venv AND discoverable as a
memory provider. Three ways to get it there:

| Approach | Durable across image rebuild? | Maintenance | Verdict |
|---|---|---|---|
| Runtime `pip install` into `/opt/data/lazy-packages` | **No** — Hermes wipes that dir on a Python-ABI bump with no repopulate step; a base Python uprev silently drops the package | zero | fragile |
| Fork Hermes source, add to `pyproject.toml`, rebuild whole image | Yes | **high** — rebase treadmill on a fast-moving repo; 5GB multi-arch build | overkill for one dep |
| **This: thin `FROM` + one `RUN`** | **Yes** — installed into the image venv, re-resolved against the base's Python every build | **low** — bump `HERMES_BASE_TAG`, rebuild | ✅ |

The lazy-install ABI-wipe footgun is the whole reason a bake-in was wanted; this
image is immune to it because Mnemosyne is a first-class image dependency, not a
runtime-installed one.

---

## How the integration works

1. `uv pip install mnemosyne-memory` puts two top-level packages in the venv:
   `mnemosyne` (memory core) and `hermes_memory_provider` (the Hermes
   `MemoryProvider` adapter).
2. `plugins/memory/mnemosyne/__init__.py` re-exports `MnemosyneMemoryProvider`
   so Hermes's **bundled** memory-provider loader (`plugins/memory/`) discovers
   it. Bundled providers take precedence and are always present in the image —
   no dependency on a runtime symlink under `$HERMES_HOME/plugins`.
3. The Dockerfile runs a **build-time assertion** that the provider is
   discovered and reports `is_available() == True`, so a broken integration
   fails the build instead of shipping.

Activation is still per-profile config: set `memory.provider: mnemosyne` in
each profile's `config.yaml` (see "Runtime config" below). The image makes the
provider *available*; config makes it *active*.

---

## Deploying on Unraid (Carina)

The derived image is behaviorally identical to upstream + one memory provider —
same s6-overlay supervision, same privilege drop, same `HERMES_HOME`,
same env-var contract. So the Unraid template change is just the repository:

1. **Edit the Hermes-Agent container template** → **Repository**:
   ```
   nousresearch/hermes-agent:v2026.7.7.2   →   ghcr.io/justinbowes/hermes-mnemosyne:v2026.7.7.2
   ```
   Use the **immutable** `:<base-tag>` or `:<base-tag>-<sha>` tag, not `:latest`
   (matches the "pinned tag over latest" house rule).
2. **Apply** (recreate the container — a plain restart reuses the old image).
   Deploys are explicit and human-run; nothing auto-pulls (verified: overnight
   restarts do NOT re-pull images).
3. All persistent state under `/opt/data` (`$HERMES_HOME`) is untouched —
   config, `.env`, sessions, Mnemosyne's own `mnemosyne/data/*.db` all persist
   across the image swap.

GHCR is public-readable for this image by default once the package visibility
is set to public (Repo → Packages → hermes-mnemosyne → Package settings →
Change visibility → Public). If you keep it private, add registry creds to the
Unraid template (a GHCR token with `read:packages`).

### Runtime config (per profile)

The image ships the provider; enable it per profile. On the host or via
`hermes config`:
```yaml
memory:
  provider: mnemosyne
  mnemosyne:
    profile_isolation: true   # each profile → its own bank
```
(For the default profile: `hermes config set memory.provider mnemosyne`. For
named profiles: `HERMES_HOME=/opt/data/.hermes/profiles/<name> hermes config set memory.provider mnemosyne`.)

---

## Updating when upstream ships a new Hermes version

1. Check for a newer tag:
   `curl -s https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags/?page_size=5 | jq -r '.results[].name'`
2. Bump `HERMES_BASE_TAG` (and `MNEMOSYNE_VERSION` if you want a newer
   Mnemosyne). Commit to `main`.
3. GitHub Actions rebuilds and publishes automatically. The build-time
   assertion re-validates the integration against the new base — if upstream
   changed the memory-provider loader contract, the build FAILS loudly rather
   than shipping a silently-broken image.
4. Repoint the Unraid template to the new tag and Apply.

A weekly scheduled rebuild (`.github/workflows/build.yml`) also refreshes the
pinned base + Mnemosyne for security patches even without a manual bump. Remove
the `schedule:` block if you prefer fully manual control.

---

## Manual build (optional, without CI)

```bash
docker build \
  --build-arg HERMES_BASE_TAG=v2026.7.7.2 \
  --build-arg MNEMOSYNE_VERSION=3.11.1 \
  -t ghcr.io/justinbowes/hermes-mnemosyne:v2026.7.7.2 .
docker push ghcr.io/justinbowes/hermes-mnemosyne:v2026.7.7.2   # needs write:packages
```

---

## Files

- `Dockerfile` — the thin layer + build-time integration assertion.
- `plugins/memory/mnemosyne/__init__.py` — bundled provider shim.
- `.github/workflows/build.yml` — build + push to GHCR (uses in-workflow
  `GITHUB_TOKEN`, `packages: write`).
- `HERMES_BASE_TAG`, `MNEMOSYNE_VERSION` — the two pins. Edit these to update.
