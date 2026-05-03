# Design notes

## Dockerfile

### Per-architecture runtime bases

xfr ships two distinct Linux binaries:

- `xfr-x86_64-unknown-linux-musl` — statically linked against musl libc; runs on Alpine with zero additional runtime deps
- `xfr-aarch64-unknown-linux-gnu` — dynamically linked against glibc; requires Debian/Ubuntu-family base

Using a single Alpine base for both architectures would require installing glibc compatibility shims on arm64, adding complexity and image size. Two separate runtime stages (`runtime-amd64`, `runtime-arm64`) keep each base minimal and dependency-free.

### Digest pinning

Both runtime bases are pinned by multi-platform manifest digest (`@sha256:…`). This ensures:

- Reproducible builds across time and machines
- Protection against tag mutation (a tag like `alpine:3.21` can silently point to a new digest)
- Auditability — exact base image is recorded in the Dockerfile

Update digests intentionally when base images receive security patches. See CLAUDE.md for the update commands.

### Downloader stage

The `downloader` stage uses `--platform=$BUILDPLATFORM` so it always runs natively on the build machine — never under QEMU emulation. This matters because:

- Network operations (curl) are slow under QEMU
- The downloader only fetches and verifies files; it doesn't compile architecture-specific code

The stage downloads the correct tarball based on `$TARGETARCH`, verifies it against the upstream `SHA256SUMS` file using `awk` for exact-line matching (guards against format changes where a filename is a prefix of another), then installs the binary to `/tmp/xfr-bin`.

`curl` is installed in the downloader stage via `apk add` and is not present in the final image.

### Checksum verification

The verification pattern:

```sh
MATCH="$(awk -v asset="${ASSET}" '$2==asset{print}' SHA256SUMS)"
[ -n "$MATCH" ] || { echo "ERROR: ${ASSET} not found in SHA256SUMS" >&2; exit 1; }
printf '%s\n' "$MATCH" | sha256sum -c -
```

Uses field-exact matching (`$2==asset`) rather than `grep asset` to avoid false positives when one asset name is a substring of another. Fails explicitly if the asset is absent from the checksum file.

## CI workflows

### Separation of concerns

Two workflows handle two distinct responsibilities:

- **`watch-upstream.yml`** — detection: is anything missing?
- **`build.yml`** — remediation: build and publish what is missing

This separation means `build.yml` is also useful standalone (manual triggers, forced rebuilds) without the detection logic.

### Registry synchronization strategy

The watcher checks three tags per registry: `vX.Y.Z`, `X.Y.Z`, `latest`. A registry is "missing" if any of the three is absent. The watcher then passes one of two modes to `build.yml`:

- `force=false` when GHCR's versioned tag (`vX.Y.Z`) is missing — `build.yml` runs its normal idempotency check, finds the image absent, proceeds with build
- `force=true` when GHCR's versioned tag exists but something else is missing (bare tag, latest, or a mirror registry) — `build.yml` skips the idempotency check and pushes everything

This avoids a trigger→skip loop: without `force=true`, a watcher trigger for a missing `latest` tag would hit `build.yml`'s idempotency guard and exit with a skip summary.

### Mirror strategy

Codeberg and Quay.io receive images via `docker buildx imagetools create`, which copies the multi-platform manifest + layer references from Docker Hub without a rebuild. This:

- Avoids a second full build for each mirror
- Ensures all registries serve identical content (same layer digests)
- Makes mirror step failures non-fatal (`continue-on-error: true`) — primary registries always get the image

### force / publish_latest inputs

| Input | Default | Purpose |
|-------|---------|---------|
| `version` | latest upstream | Version to build |
| `force` | `false` | Skip idempotency check |
| `publish_latest` | `true` | Whether to push `latest` tag |

`publish_latest=false` is used when rebuilding an old version (e.g., to regenerate digests after a base image update) to avoid rolling back `latest` to an older xfr version.

### GitHub Release management

Each release gets a `digests.txt` asset with the multi-platform index digest and per-platform digests. This allows users to pin images by digest for production deployments. When `build.yml` runs with `force=true` (rebuilt image, new digests), it updates the release notes and replaces `digests.txt` to keep the release authoritative.

Git tag is not moved on forced rebuilds. When a forced rebuild updates an existing release, the GitHub Release notes and `digests.txt` are refreshed, but the Git tag (`vX.Y.Z`) continues to point to the original commit. The release is treated as image metadata for the upstream `xfr` version, not as a source snapshot of this repository. `digests.txt` is the authoritative source of truth for the currently published image.

## Security practices

- SHA256 verification against upstream-provided checksums before any binary enters the image
- Digest-pinned base images — no silent tag mutations
- `curl` not present in final image — reduced attack surface
- License files included in images at `/usr/share/licenses/` — compliance for redistribution
- SBOM and provenance attestations generated by `docker/build-push-action` — supply chain transparency
- No secrets or credentials in any image layer or repository file
