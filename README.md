# otel-collector-obi

Builds the `otelcol-contrib` distribution with the OBI (eBPF instrumentation)
receiver compiled from a verified upstream source tree, so the node-agent
collector can run a newer OBI than the published contrib image ships.

Current build: otelcol-contrib `0.165.0` with OBI `v0.15.2`, Go 1.26.

## Why this exists

It started as a way to carry two OBI `v0.10.0` heap-retention fixes (env-var
cloning per span; symbol tables retained for zero-address uprobes). Both are
upstream as of OBI `v0.15.x`, so no patches are applied any more — see
[`retired-patches/`](retired-patches/README.md) for what they were and where
upstream fixed them.

It is kept because OBI `v0.12+` runs the GenAI payload parsers (OpenAI,
Anthropic, Bedrock, Gemini) on Go `net/http` client spans too, not only on the
generic (non-Go) HTTP path, which is what gives `gen_ai.*` attributes on
outbound LLM calls from Go services.

## How the build works

`manifest.yaml` is the official
[otelcol-contrib manifest](https://github.com/open-telemetry/opentelemetry-collector-releases/blob/v0.165.0/distributions/otelcol-contrib/manifest.yaml)
at v0.165.0, with the OBI `replaces:` target repointed at `/src/obi-src`.
Component set and versions are otherwise untouched, so the binary is a drop-in
for the upstream image.

OBI cannot be built from the module proxy: its bpf2go bindings are gitignored and
absent from the published module. Upstream solves this with
`scripts/prepare-obi.sh`, which downloads a `source-generated` release tarball.
The Dockerfile mirrors that exactly — same tarball, verified against the same
`SHA256SUMS`.

## Images

The workflow builds one variant, `upstream` (OBI unmodified), into
`ghcr.io/clode-labs/otel-collector-obi`. Images built before the move to OBI
`v0.15.2` used the variants `patched`, `envonly` and `baseline`; those tags still
exist and are immutable.

Each variant is pushed under three tags:

| tag | mutable? | use |
|---|---|---|
| `<variant>-sha-<short>` | **no** | **what we deploy** — short form |
| `<contrib>-obi-<obi>-<variant>-sha-<short>` | **no** | same image, fully described |
| `<variant>` | yes | convenience only — "the current one" |

`<contrib>` is read from `manifest.yaml`, so it cannot drift from the binary.
Every tag that carries meaning ends in `-sha-<short>`; only the bare variant
name floats.

### Deploy by `<variant>-sha-<short>`, never by a floating tag

These images are consumed through an **ECR pull-through cache**, which caches by
tag and does not re-resolve a tag it has already seen. Repushing `:upstream`
therefore leaves nodes running the old image while the tag, the pod spec and the
manifest all still look correct — a silent failure with nothing to alert on.

Pinning a digest does **not** solve it either: pull-through import is
tag-driven, so a digest ECR has never cached has no import path and the pull
fails with `manifest unknown: Requested image not found`. That breaks precisely
the case you need — rolling out a newly pushed build.

An immutable tag is both the safe form and the readable one: `upstream-sha-a1b2c3d`
tells you which commit produced the image; a bare digest does not.

Entrypoint and binary name match the upstream contrib image, so an existing pod
spec works unchanged.

## Building locally

```sh
docker build -t otel-collector-obi:upstream .
docker build --build-arg OBI_VERSION=v0.15.2 -t otel-collector-obi:upstream .
```
