# syntax=docker/dockerfile:1

# XFR_VERSION has no default — must be supplied via --build-arg or the CI workflow.
# Example: docker buildx build --build-arg XFR_VERSION=v0.9.12 --platform linux/amd64 .
ARG XFR_VERSION

# ┌─┐ Per-architecture runtime bases ┌─┐
# amd64: Alpine – upstream ships a musl/static binary (zero runtime deps).
# arm64: Debian slim – upstream ships a glibc-linked binary; Debian has glibc
#        natively, so no compatibility shim is needed.
# Digests pin the exact multi-platform manifest; update via:
#   TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/alpine:pull" | jq -r '.token')
#   curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" -I "https://registry-1.docker.io/v2/library/alpine/manifests/3.21" | grep docker-content-digest
FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d \
    AS runtime-amd64
FROM debian:bookworm-slim@sha256:f9c6a2fd2ddbc23e336b6257a5245e31f996953ef06cd13a59fa0a1df2d5c252 \
    AS runtime-arm64

# ┌─┐ Downloader (runs on build machine's native arch, never needs QEMU) ┌─┐
FROM --platform=$BUILDPLATFORM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d \
    AS downloader

ARG XFR_VERSION
ARG TARGETARCH

RUN [ -n "${XFR_VERSION}" ] || { echo "ERROR: XFR_VERSION build-arg is required" >&2; exit 1; }

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) ASSET="xfr-x86_64-unknown-linux-musl.tar.gz" ;; \
        arm64) ASSET="xfr-aarch64-unknown-linux-gnu.tar.gz" ;; \
        *)     echo "ERROR: unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    BASE_URL="https://github.com/lance0/xfr/releases/download/${XFR_VERSION}"; \
    apk add --no-cache curl; \
    mkdir -p /tmp/xfr-install; \
    curl -fsSL "${BASE_URL}/SHA256SUMS"  -o /tmp/xfr-install/SHA256SUMS; \
    curl -fsSL "${BASE_URL}/${ASSET}"    -o "/tmp/xfr-install/${ASSET}"; \
    cd /tmp/xfr-install; \
    MATCH="$(awk -v asset="${ASSET}" '$2==asset{print}' SHA256SUMS)"; \
    [ -n "$MATCH" ] || { echo "ERROR: ${ASSET} not found in SHA256SUMS" >&2; exit 1; }; \
    printf '%s\n' "$MATCH" | sha256sum -c -; \
    mkdir -p /tmp/xfr-extract; \
    tar -xzf "${ASSET}" -C /tmp/xfr-extract; \
    BIN="$(find /tmp/xfr-extract -type f -name 'xfr' | head -1)"; \
    [ -n "$BIN" ] || { echo "ERROR: binary 'xfr' not found inside ${ASSET}" >&2; exit 1; }; \
    install -m 0755 "$BIN" /tmp/xfr-bin

# ┌─┐ Final image – selects base via runtime-${TARGETARCH} ┌─┐
FROM runtime-${TARGETARCH}

ARG XFR_VERSION

COPY --from=downloader /tmp/xfr-bin /usr/local/bin/xfr
COPY LICENSE      /usr/share/licenses/docker-xfr/LICENSE
COPY LICENSES/    /usr/share/licenses/xfr/

# Run as non-root. Port 5201 is unprivileged so no capabilities needed.
# Alpine (busybox adduser): adduser -S -H -D
# Debian (adduser package): adduser --system --no-create-home
RUN if [ -f /etc/debian_version ]; then \
        adduser --system --no-create-home --group xfr; \
    else \
        adduser -S -H -D xfr; \
    fi

USER xfr

LABEL org.opencontainers.image.title="xfr" \
      org.opencontainers.image.description="Unofficial container image for xfr – a modern iperf3 alternative with live TUI, multi-client server, MPTCP, and QUIC support" \
      org.opencontainers.image.url="https://github.com/lance0/xfr" \
      org.opencontainers.image.source="https://github.com/rusnino/docker-xfr" \
      org.opencontainers.image.version="${XFR_VERSION}" \
      org.opencontainers.image.licenses="MIT OR Apache-2.0" \
      org.opencontainers.image.vendor="Unofficial"

# TCP: control + data (single-port mode); UDP: UDP test mode; QUIC uses UDP
EXPOSE 5201/tcp
EXPOSE 5201/udp

ENTRYPOINT ["xfr"]
