# Hermes Agent + Mnemosyne — thin derived image.
#
# Layers the Mnemosyne memory provider on top of the OFFICIAL published Hermes
# image. No source fork, no rebasing: we FROM a pinned upstream tag and add one
# dependency + a bundled provider shim. When upstream ships a new version, bump
# HERMES_BASE_TAG (and MNEMOSYNE_VERSION if desired), rebuild, redeploy.
#
# Why this beats baking mnemosyne into the durable lazy-install dir
# (/opt/data/lazy-packages): that store is WIPED on a Python-ABI bump with no
# repopulate step, so a base-image Python uprev silently drops the package.
# Installing into the image's real venv here means mnemosyne is re-resolved
# against whatever Python the base ships, every build. It is a first-class
# image dependency, immune to the ABI-wipe footgun.

ARG HERMES_BASE_TAG=v2026.7.7.2
FROM nousresearch/hermes-agent:${HERMES_BASE_TAG}

# Pin the mnemosyne version for reproducible images (NOT floating latest).
ARG MNEMOSYNE_VERSION=3.11.1

# The base image ships uv at /usr/local/bin/uv and the app venv at
# /opt/hermes/.venv. Install into that venv so `hermes` (which runs on that
# venv's python) can import both `mnemosyne` and `hermes_memory_provider`.
# --system-site-packages is NOT needed; --python targets the venv directly.
# Root layer: site-packages is root-owned in the base image, which is correct
# for a baked dependency (unlike the writable-at-runtime lazy dir).
RUN /usr/local/bin/uv pip install \
        --python /opt/hermes/.venv/bin/python \
        --no-cache-dir \
        "mnemosyne-memory==${MNEMOSYNE_VERSION}" \
    && /opt/hermes/.venv/bin/python -c "import mnemosyne, hermes_memory_provider; print('mnemosyne', mnemosyne.__version__)"

# Drop the bundled provider shim so Hermes discovers Mnemosyne as a first-class
# BUNDLED provider (plugins/memory/mnemosyne/) — no dependency on a runtime
# symlink in the persistent $HERMES_HOME/plugins dir. Bundled providers take
# precedence and are always present in the image.
COPY plugins/memory/mnemosyne/ /opt/hermes/plugins/memory/mnemosyne/

# Build-time sanity: the loader must classify + load the provider and report it
# available. Fails the build early if the integration is broken, so a bad image
# never ships.
RUN /opt/hermes/.venv/bin/python -c "\
import hermes_bootstrap; \
from plugins.memory import discover_memory_providers, load_memory_provider; \
avail = dict((n, a) for n, _d, a in discover_memory_providers()); \
assert avail.get('mnemosyne') is True, f'mnemosyne not available: {avail}'; \
p = load_memory_provider('mnemosyne'); \
assert p is not None and p.name == 'mnemosyne' and p.is_available(), 'provider load failed'; \
print('OK: mnemosyne bundled provider discovered + available')"

# Record provenance in image labels.
LABEL org.opencontainers.image.title="hermes-mnemosyne" \
      org.opencontainers.image.description="Hermes Agent with the Mnemosyne memory provider baked in" \
      org.opencontainers.image.source="https://github.com/justinbowes/hermes-mnemosyne" \
      org.opencontainers.image.base.name="docker.io/nousresearch/hermes-agent:${HERMES_BASE_TAG}"

# NOTE: no ENTRYPOINT/CMD/USER override — inherit ALL runtime behavior from the
# base image (s6-overlay supervision, privilege drop, HERMES_HOME, etc.).
# This image is behaviorally identical to upstream + one memory provider.
