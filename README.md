# Trace-of-FiTune: Public Workload Suite

[English](README.md) | [中文](README.zh-CN.md)

This repository provides workload templates and anonymized phase-level workload sequences reconstructed from two 30-day production deployments. It preserves workload patterns, phase boundaries, and recurrence relationships while excluding raw I/O requests and sensitive production telemetry.

The workload phases were reconstructed from the trace used in our FiTune experiments, with application labels mapped to neutral workload IDs (`w01`--`w14`). The repository publishes the anonymous workload sequences and templates used to represent the two deployments. Native templates use placeholders such as `@HOST01@`, `@DATA@`, and `@VDBENCH@`; fill them locally before running a workload.

## Contents

- `workloads/`: 14 workload families using Vdbench, fio, and IOR/MPI templates.
- `catalog.json`: workload IDs, patterns, client mappings, concrete entry files, and variants.
- `trace/30day_trace.json`: phase-level sequences for `trace_a`/`deployment_a` and `trace_b`/`deployment_b`.
- `trace/30day_trace.csv`: the same phase-level sequence in a flat format.
- `scripts/prepare_data.sh`: dataset-tree preparation for all workload families.
- `scripts/check_placeholders.py`: placeholder inventory and validation.
- `scripts/validate_release.py`: catalog, trace, duration, and client-mapping checks.
- `tool_versions.json`: reference versions and runtime commands.
- `PUBLIC_SHA256SUMS`: SHA-256 checksums for release files.
- `LICENSE`: MIT license for the repository templates and scripts.

## Phase-level workload sequences

The two anonymous deployment labels map to the two 30-day traces as follows:

| Trace | Anonymous deployment label | Duration |
|:--|:--|--:|
| `trace_a` | `deployment_a` | 30 days |
| `trace_b` | `deployment_b` | 30 days |

Each phase records `workload_id`, a public template path, an optional variant, `start_day`, `end_day`, `duration_days`, and `repeat_of`. Phase durations are the intervals used to represent the workload sequence; tuning-window and reaction-time fields are not part of this release.

## Workload data preparation

All Vdbench runtime entries use `format=no`, so the referenced file trees must be prepared before a run. The preparation script creates the exact anchor paths, directory depths, file counts, and logical sizes used by the templates; data initialization is kept separate from the runtime workload.

```bash
python3 scripts/validate_release.py
python3 scripts/check_placeholders.py
scripts/prepare_data.sh --root /mnt/test-data --profile w01,w02 --mode allocate
```

`--mode sparse` creates logically sized files whose reads return deterministic zeros with minimal physical allocation. `--mode allocate` uses `fallocate` to reserve the requested extents, and `--mode zero` writes zero bytes across the requested extents. Use `allocate` or `zero` when the experiment requires physically materialized data. The `--max-files` option provides a bounded smoke setup for the large file-count profiles.

| ID | Preparation requirement | Logical capacity / structure |
|:--:|---|---:|
| `w01`--`w04` | Create `standard-large` with 1,024 files of 1 GiB | 1 TiB |
| `w05`--`w06` | Create `smallfile` with `depth=1`, `width=10000`, `files=1000`, 4 KiB each | 10 million files, 40 GB logical |
| `w07` | Create `mixed400k` with 100 anchors and 100,000 files per anchor | 10 million files, 4.096 TB logical |
| `w08` | Create eight depth-4, width-5 trees under `mixed-ops` with the declared size distributions | Operation-mix file tree |
| `w09` | Create eight depth-4, width-5 trees under `mixed-bandwidth` with the declared size distributions | Bandwidth-mix file tree |
| `w10` | Create `fio/testfile1` before all four fio jobs | 109,949,485,056 bytes |
| `w11` | Create `checkpoint-short`; the script creates its output root | IOR output and checkpoint files |
| `w12` | Create `checkpoint-long`; the script creates its output root | Three output/checkpoint phases |
| `w13` | Create a depth-4, width-6 tree with 10 files per leaf and the declared size distribution | 12,960 files, about 1.46 TiB logical |
| `w14` | Create `indexed/edge-records` and `indexed/vertex-records` | 6.25 TiB and 51 GiB |

The read profiles (`w02`, `w04`, `w06`, `w10`, and the read variants of `w13`/`w14`) use the files prepared by this step. Write profiles can reuse the same tree when the experiment requires a fixed file namespace.

## Placeholders and client mapping

| Placeholder | Meaning | Used by |
|:--|:--|:--|
| `@HOST01@`--`@HOST16@` | Client host names or addresses | Vdbench profiles |
| `@USER@` | Remote execution user | Vdbench profiles |
| `@DATA@` | Dataset root | All profiles |
| `@VDBENCH@` | Vdbench 5.04.06 executable or wrapper | w01--w09, w13 |
| `@VDBENCH_INDEXED@` | Vdbench executable or wrapper for indexed profiles | w14 |
| `@HOSTS64@` | MPI host-file path | w11--w12 |
| `@IOR@` | IOR 4.0.0 executable | w11--w12 |
| `@MPIRUN@` | MPI launcher | w11--w12 |

The eight-client profiles declare `hd1`--`hd8` and explicitly assign one FWD entry to each host. `w07` declares `hd1`--`hd16` and explicitly assigns one FWD entry to each host. `w08`, `w09`, and `w13` declare `hd1`--`hd16` and leave the FWD `host` field unset, so Vdbench applies its default distribution across the declared hosts; the validator checks this declaration and the absence of conflicting explicit assignments. `w14` uses `h1`--`h16`, with each `sdN` assigned to `hN` and a non-overlapping range. The IOR profiles use 64 ranks over 16 clients, four ranks per client, as represented by `@HOSTS64@`.

## Tool versions and runtime dependencies

The reference matrix is recorded in `tool_versions.json`: Vdbench 5.04.06, fio 3.36, and IOR 4.0.0. Pin the MPI implementation before running the IOR profiles and record the output of `mpirun --version`; the launcher and host-file syntax must support `mpirun -f`. Vdbench requires Java 8 or newer. The checkpoint scripts use Bash, `bc`, GNU `tail`, `grep`, `awk`, `expr`, and standard directory/file utilities.

## Reproduction

Install the pinned tools, prepare the selected dataset profile, replace the placeholders, and run the template entry listed in `catalog.json`. Keep the generated logs and measurement outputs with the corresponding run record, together with the tool-version output and the SHA-256 value of the input template.
