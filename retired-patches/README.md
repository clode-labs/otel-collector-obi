# Retired patches

These patches were carried against OBI `v0.10.0` (otelcol-contrib `0.156.0`).
They no longer apply to OBI `v0.15.2` and are not needed there, because both
fixes are upstream:

| patch | upstream in v0.15.2 |
|---|---|
| `01-envvar-retention.patch` | `PIDsFilter.Filter` (`pkg/ebpf/common/pids.go`) reads `FileInfo.UnsafeServiceAttrs()`, which does not clone `EnvVars`. The cloning `ServiceAttrs()` remains only on per-process paths. |
| `02-uprobe-zero-offset.patch` | `gatherGoOffsets` (`pkg/ebpf/instrumenter.go`) marks probes `Skip` when the symbol has no offsets, and sets `probe.Skip = probe.StartOffset == 0 \|\| offs.PadOffset == 0`, so nothing is attached with `Address=0`. |

Kept for reference only; the Dockerfile neither copies nor applies them.
