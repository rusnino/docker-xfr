[![Build and Push](https://github.com/rusnino/docker-xfr/actions/workflows/build.yml/badge.svg)](https://github.com/rusnino/docker-xfr/actions/workflows/build.yml)

# docker-xfr

Unofficial multi-platform container images for [xfr](https://github.com/lance0/xfr) — a modern iperf3 alternative with a live TUI, multi-client server, MPTCP, and QUIC support. Built in Rust.

## Registries

| Registry | Image |
|----------|-------|
| Docker Hub | `docker.io/rusnino/xfr` |
| GHCR | `ghcr.io/rusnino/xfr` |
| Codeberg | `codeberg.org/rusnino/xfr` _(optional)_ |
| Quay.io | `quay.io/rusnino/xfr` _(optional)_ |

## Usage

### Client mode

```sh
# Interactive terminal — live TUI with real-time graphs
docker run --rm -it ghcr.io/rusnino/xfr 192.168.1.1
docker run --rm -it ghcr.io/rusnino/xfr 192.168.1.1 -t 30s -P 4
docker run --rm -it ghcr.io/rusnino/xfr 192.168.1.1 -u -b 500M   # UDP
docker run --rm -it ghcr.io/rusnino/xfr 192.168.1.1 --quic        # QUIC/TLS 1.3

# Non-interactive / CI — plain text output
docker run --rm ghcr.io/rusnino/xfr 192.168.1.1 --no-tui
docker run --rm ghcr.io/rusnino/xfr 192.168.1.1 --no-tui --json   # JSON output
```

### Server mode

UDP and QUIC both use the UDP socket on port 5201, so publish both protocols:

```sh
# TCP + UDP/QUIC (recommended)
docker run --rm \
  -p 5201:5201/tcp \
  -p 5201:5201/udp \
  ghcr.io/rusnino/xfr serve

# TCP only (if you don't need UDP/QUIC)
docker run --rm -p 5201:5201/tcp ghcr.io/rusnino/xfr serve

# Custom port (-p sets TCP, UDP, and QUIC on the same port)
docker run --rm \
  -p 9000:9000/tcp \
  -p 9000:9000/udp \
  ghcr.io/rusnino/xfr serve -p 9000

# With PSK authentication
docker run --rm \
  -p 5201:5201/tcp \
  -p 5201:5201/udp \
  ghcr.io/rusnino/xfr serve --psk mysecret
```

### Docker Compose

```yaml
services:
  xfr-server:
    image: ghcr.io/rusnino/xfr:latest
    command: ["serve"]
    ports:
      - "5201:5201/tcp"
      - "5201:5201/udp"
    restart: unless-stopped
```

## Tags

| Tag | Meaning |
|-----|---------|
| `latest` | Latest upstream release |
| `vX.Y.Z` | Exact version with v-prefix |
| `X.Y.Z` | Exact version, bare |

## Platforms

| Platform | Base image | Binary |
|----------|-----------|--------|
| `linux/amd64` | Alpine 3.21 | `xfr-x86_64-unknown-linux-musl` (static) |
| `linux/arm64` | Debian bookworm-slim | `xfr-aarch64-unknown-linux-gnu` (glibc) |

**MPTCP:** requires host kernel ≥ 5.6 with MPTCP enabled. The container image does not enable or configure MPTCP by itself — it depends entirely on the host kernel and network stack.

## Update policy

A watcher workflow polls [lance0/xfr releases](https://github.com/lance0/xfr/releases) every 15 minutes. When a new version appears — or any configured registry is missing a tag — a build is triggered automatically. New releases typically appear in registries within 15–20 minutes of the upstream release.

## Required secrets

Configure these in your fork's repository settings → Secrets and variables → Actions:

| Secret | Required | Description |
|--------|----------|-------------|
| `DOCKERHUB_USERNAME` | Yes | Docker Hub login username |
| `DOCKERHUB_TOKEN` | Yes | Docker Hub access token |
| `DOCKERHUB_NAMESPACE` | Yes | Docker Hub org or username for image path |

## Optional secrets (registry mirrors)

Configure all three secrets for a registry to enable mirroring. Partial configuration is ignored.

| Secret | Registry |
|--------|----------|
| `CODEBERG_USERNAME` | Codeberg |
| `CODEBERG_TOKEN` | Codeberg |
| `CODEBERG_NAMESPACE` | Codeberg |
| `QUAY_USERNAME` | Quay.io (robot account: `namespace+robotname`) |
| `QUAY_TOKEN` | Quay.io |
| `QUAY_NAMESPACE` | Quay.io |

## Manual build trigger

```sh
# Build a specific version
gh workflow run build.yml --repo rusnino/docker-xfr --field version=v0.9.12

# Force-rebuild latest version (e.g. after base image update)
gh workflow run build.yml --repo rusnino/docker-xfr --field version=v0.9.12 --field force=true

# Force-rebuild an old version — publish_latest=false prevents rolling back the latest pointer
gh workflow run build.yml --repo rusnino/docker-xfr \
  --field version=v0.9.7 \
  --field force=true \
  --field publish_latest=false
```

## Security

- Final image runs as an unprivileged non-root user (`10001:10001`)
- Release binaries verified against upstream `SHA256SUMS` before inclusion
- Base images pinned by digest for reproducible builds
- `curl` present only in the build stage; not in the final image
- SBOM and provenance attestations attached to every image
- Pin by digest for production: `docker run --rm -it ghcr.io/rusnino/xfr@sha256:<digest> <host>`

## License

This repository (Dockerfile, workflows, documentation): [MIT](LICENSE)

The xfr binary distributed inside images is copyright lance0 and licensed under
[MIT](LICENSES/upstream-MIT.txt) OR [Apache-2.0](LICENSES/upstream-APACHE-2.0.txt) at your option.
