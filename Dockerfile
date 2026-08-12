# syntax=docker/dockerfile:1.7

# Builds the otelcol-contrib distribution with the OBI module taken from a local
# source tree, which is how upstream builds it too: OBI's bpf2go bindings are not
# committed and are absent from the published module, so the release pipeline
# consumes a "source-generated" tarball instead.
#
# This mirrors scripts/prepare-obi.sh from opentelemetry-collector-releases: the
# same tarball, verified against the same SHA256SUMS. The only difference is
# which patches are applied on top, selected by PATCH_SET, so every variant
# comes out of an identical pipeline:
#
#   none  upstream, unmodified
#   env   env-var retention fix only
#   full  env-var retention fix plus the zero-offset uprobe guard
#
# Building all three lets each fix be attributed on its own rather than as a pair.

ARG GO_IMG=golang:1.25-bookworm
ARG RUNTIME_IMG=gcr.io/distroless/static-debian12

# 1. Fetch and verify the OBI source-generated tarball, then optionally patch it.
FROM ${GO_IMG} AS obi-src
ARG OBI_VERSION=v0.10.0
ARG PATCH_SET=full
WORKDIR /tmp/obi
RUN set -eux; \
    base="https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/releases/download/${OBI_VERSION}"; \
    tarball="obi-${OBI_VERSION}-source-generated.tar.gz"; \
    curl --fail --show-error --location --silent --retry 3 --retry-delay 1 -o "${tarball}" "${base}/${tarball}"; \
    curl --fail --show-error --location --silent --retry 3 --retry-delay 1 -o SHA256SUMS "${base}/SHA256SUMS"; \
    expected="$(awk -v f="${tarball}" '{ n = $2; sub(/^\*/, "", n); if (n == f) { print $1; exit } }' SHA256SUMS)"; \
    test -n "${expected}"; \
    actual="$(sha256sum "${tarball}" | awk '{print $1}')"; \
    test "${expected}" = "${actual}"; \
    echo "SHA256 verified: ${tarball}"; \
    mkdir -p /src/obi-src; \
    tar -xzf "${tarball}" -C /src/obi-src --strip-components=1

COPY patches/ /tmp/patches/
RUN set -eux; \
    cd /src/obi-src; \
    case "${PATCH_SET}" in \
      none) echo "PATCH_SET=none: building upstream unmodified" ;; \
      env)  git apply --verbose /tmp/patches/01-envvar-retention.patch ;; \
      full) git apply --verbose /tmp/patches/01-envvar-retention.patch; \
            git apply --verbose /tmp/patches/02-uprobe-zero-offset.patch ;; \
      *)    echo "unknown PATCH_SET: ${PATCH_SET}" >&2; exit 1 ;; \
    esac; \
    echo "PATCH_SET=${PATCH_SET} applied"

# 2. Build the collector against that source tree.
FROM ${GO_IMG} AS build
ARG TARGETARCH=amd64
ARG PATCH_SET=full
ENV CGO_ENABLED=0 GOOS=linux
WORKDIR /build
COPY --from=obi-src /src/obi-src /src/obi-src
COPY manifest.yaml ./manifest.yaml
RUN go install go.opentelemetry.io/collector/cmd/builder@v0.156.0
RUN GOARCH=${TARGETARCH} builder --config=./manifest.yaml

# 3. Runtime. Entrypoint and binary name match the upstream contrib image so the
#    same pod spec and arguments work unchanged.
FROM ${RUNTIME_IMG}
COPY --from=build /build/_build/otelcol-contrib /otelcol-contrib
ENTRYPOINT ["/otelcol-contrib"]
