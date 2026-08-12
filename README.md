# otel-collector-obi

Builds the `otelcol-contrib` distribution with a patched OBI receiver, to measure
the memory behaviour of eBPF instrumentation under process churn.

## Why this exists

Two sources of heap retention in OBI scale with the number of instrumented
processes and the volume of spans:

1. **Process environment retained per span.** `procs.EnvVars` reads the whole of
   `/proc/<pid>/environ` into `svc.Attrs.EnvVars`, and `FileInfo.ServiceAttrs`
   deep-copies it with `maps.Clone`. That method is called once per span in
   `PIDsFilter.Filter`, so every span in flight carries a copy of its process
   environment — while only a fixed handful of variables are ever read.

2. **Symbol tables retained for attachments that cannot succeed.** Uprobes are
   attached with an empty symbol name and an explicit address.
   `link.Executable.Uprobe` only takes the address fast path when the address is
   greater than zero; with a zero address it falls back to symbol resolution,
   parsing the executable's full symbol table and caching it on the `Executable`
   for its lifetime, before failing to find the empty symbol.

`patches/` holds one patch per issue, so each can be measured on its own:

| file | addresses |
|---|---|
| `01-envvar-retention.patch` | issue 1 |
| `02-uprobe-zero-offset.patch` | issue 2 |

Both apply to OBI `v0.10.0`, the version embedded in
`otel/opentelemetry-collector-contrib:0.156.0`.

## How the build works

`manifest.yaml` is the official
[otelcol-contrib manifest](https://github.com/open-telemetry/opentelemetry-collector-releases/blob/v0.156.0/distributions/otelcol-contrib/manifest.yaml)
at v0.156.0, with the OBI `replaces:` target repointed at `/src/obi-src`.
Component set and versions are otherwise untouched, so the binary is a drop-in
for the upstream image.

OBI cannot be built from the module proxy: its bpf2go bindings are gitignored and
absent from the published module. Upstream solves this with
`scripts/prepare-obi.sh`, which downloads a `source-generated` release tarball.
The Dockerfile mirrors that exactly — same tarball, verified against the same
`SHA256SUMS` — and then optionally applies the patch.

## Images

The workflow builds all three variants through an identical pipeline, so they
differ only by which patches are applied:

| tag | `PATCH_SET` | contents |
|---|---|---|
| `ghcr.io/clode-labs/otel-collector-obi:baseline` | `none` | upstream, unmodified |
| `ghcr.io/clode-labs/otel-collector-obi:envonly` | `env` | issue 1 only |
| `ghcr.io/clode-labs/otel-collector-obi:patched` | `full` | issues 1 and 2 |

The `envonly` variant exists so the two fixes can be attributed separately
rather than only as a pair.

Entrypoint and binary name match the upstream contrib image, so an existing pod
spec works unchanged.

## Building locally

```sh
docker build --build-arg PATCH_SET=none -t otel-collector-obi:baseline .
docker build --build-arg PATCH_SET=env  -t otel-collector-obi:envonly  .
docker build --build-arg PATCH_SET=full -t otel-collector-obi:patched  .
```
