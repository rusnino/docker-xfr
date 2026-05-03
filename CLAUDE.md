# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo does

Unofficial Docker image builder for [xfr](https://github.com/lance0/xfr) (modern iperf3 alternative, Rust). Downloads pre-built upstream release binaries, verifies SHA256 checksums, packages into multi-platform OCI images, publishes to Docker Hub + GHCR (+ optional Codeberg/Quay.io mirrors).

No application source code. Only Dockerfile + GitHub Actions.

## Local build

```sh
# amd64 only, load into local daemon
docker buildx build --build-arg XFR_VERSION=v0.9.12 --platform linux/amd64 -t xfr:local --load .

# Multi-platform (requires push target)
docker buildx build --build-arg XFR_VERSION=v0.9.12 --platform linux/amd64,linux/arm64 -t xfr:local .

# Smoke test (no server needed)
docker run --rm xfr:local --version

# Test server+client (two terminals)
docker run --rm -p 5201:5201/tcp -p 5201:5201/udp xfr:local serve           # terminal 1
docker run --rm --network host xfr:local 127.0.0.1 --no-tui                 # terminal 2 (Linux)
# On Docker Desktop: docker run --rm xfr:local host.docker.internal --no-tui
```

`XFR_VERSION` is mandatory — the build errors immediately without it.

## Dockerfile architecture (4 stages)

1. **`runtime-amd64`** — Alpine 3.21 (digest-pinned). Zero-dep base for static musl binary.
2. **`runtime-arm64`** — Debian bookworm-slim (digest-pinned). glibc base for GNU binary.
3. **`downloader`** — Runs on `$BUILDPLATFORM` (no QEMU). Fetches the correct release tarball from `lance0/xfr`, verifies SHA256 against upstream `SHA256SUMS`, extracts binary to `/tmp/xfr-bin`.
4. **Final** — `FROM runtime-${TARGETARCH}`. Copies binary + license files. Exposes 5201/tcp + 5201/udp.

The downloader stage never runs under QEMU — it always runs native on the build machine. Only the final `COPY` is architecture-aware.

## CI workflows

### `watch-upstream.yml`
- Runs every 15 minutes (cron)
- Fetches latest release tag from `https://api.github.com/repos/lance0/xfr/releases/latest`
- Checks 3 tags (`vX.Y.Z`, `X.Y.Z`, `latest`) across all configured registries
- Triggers `build.yml` if any tag is missing in any registry
- Sets `force=true` when GHCR has the versioned tag but bare/latest or a mirror is missing

### `build.yml`
- Triggered by `watch-upstream.yml` or manually via `workflow_dispatch`
- Job 1 (`check-version`): resolves + normalizes version, checks GHCR for existing tag
- Job 2 (`skip-summary`): writes a summary explaining the skip when already published
- Job 3 (`build-and-push`): builds linux/amd64 + linux/arm64, pushes to Docker Hub + GHCR, mirrors to optional registries via `docker buildx imagetools create`, creates/updates GitHub Release with `digests.txt`

## Required secrets

| Secret | Required |
|--------|----------|
| `DOCKERHUB_USERNAME` | Yes |
| `DOCKERHUB_TOKEN` | Yes |
| `DOCKERHUB_NAMESPACE` | Yes |
| `CODEBERG_USERNAME/TOKEN/NAMESPACE` | Optional |
| `QUAY_USERNAME/TOKEN/NAMESPACE` | Optional |

Optional registries are enabled only when all three of their secrets are set.

## Updating base image digests

```sh
# Alpine 3.21
TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/alpine:pull" | jq -r '.token')
curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" -I "https://registry-1.docker.io/v2/library/alpine/manifests/3.21" | grep docker-content-digest

# Debian bookworm-slim
TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull" | jq -r '.token')
curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" -I "https://registry-1.docker.io/v2/library/debian/manifests/bookworm-slim" | grep docker-content-digest
```

Update the four `FROM` lines in `Dockerfile` with the new digest.
