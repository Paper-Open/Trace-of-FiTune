# Trace-of-FiTune: Public Workload Suite

[English](README.md) | [中文](README.zh-CN.md)

This repository provides workload templates and anonymized phase-level workload sequences reconstructed from two 30-day production deployments. It preserves workload patterns, phase boundaries, and recurrence relationships while excluding raw I/O requests and sensitive production telemetry.

The workload phases were reconstructed from the trace used in our FiTune experiments, with application labels mapped to neutral workload IDs (`w01`--`w14`). Native templates use placeholders such as `@HOST01@`, `@DATA@`, and `@VDBENCH@`; fill them locally before running a workload.

## Contents

- `workloads/`: 14 workload families using Vdbench, fio, and IOR/MPI templates.
- `catalog.json`: workload IDs, patterns, client mappings, concrete entry files, and variants.
- `trace/30day_trace.json`: phase-level sequences for `trace_a`/`deployment_a` and `trace_b`/`deployment_b`.
- `trace/30day_trace.csv`: the same phase-level sequence in a flat format.
- `scripts/prepare_data.sh`: safe data preparation and native Vdbench formatting entry point.
- `scripts/render_vdbench.py`: placeholder rendering for a format-only Vdbench copy.
- `scripts/create_data_file.py`: no-follow, deterministic direct-file creation for fio and `formatsds=no` profiles.
- `scripts/check_placeholders.py`: placeholder inventory and validation.
- `scripts/validate_release.py`: catalog, trace, duration, CSV, and client-mapping checks.
- `tool_versions.json`: reference versions and separated runtime dependencies.
- `workloads/11-checkpoint-short/hosts64.example`: 16-client, four-slots-per-client MPI hostfile example.
- `PUBLIC_SHA256SUMS`: SHA-256 checksums for release files.
- `LICENSE`: MIT license for the repository templates and scripts.
- `.github/workflows/validate.yml`: automated release validation on push and pull request.

## Phase-level workload sequences

The two anonymous deployment labels map to the 30-day traces as follows:

| Trace | Anonymous deployment label | Duration |
|:--|:--|--:|
| `trace_a` | `deployment_a` | 30 days |
| `trace_b` | `deployment_b` | 30 days |

Each phase records `workload_id`, a public template path, an optional variant, `start_day`, `end_day`, `duration_days`, and `repeat_of`. Phase durations are the intervals used to represent the workload sequence; tuning-window and reaction-time fields are not part of this release.

## Workload data preparation

All Vdbench runtime entries use `format=no`, which requires the existing file tree to match the FSD definition. The preparation script does not synthesize Vdbench names or directories. For `w01`--`w09` and `w13`, it renders a format-only copy with two sequential stages, `format=(clean,only)` followed by `format=(restart,only)`, and invokes Vdbench 5.04.06; Vdbench creates the native `vdb*.dir` and `vdb_f*.file` structure, then the original `format=no` template can be used for measurement. Both stages format without executing the measurement RD.

The dataset root is intentionally explicit and protected by a `.fitune-generated` marker. A new root is initialized by the first command below; an existing root must be empty and passed with `--init-root`. `--clean` is accepted only for a marked root, and direct-file creation rejects existing files and symlinks unless `--force` is explicitly supplied.

The preparation entry point uses only the repository's catalogued Vdbench templates; it does not accept an arbitrary `--template` path. The lower-level renderer also checks every `anchor=` and `lun=` path against the marked dataset root before writing a format configuration.

```bash
# Native Vdbench preparation; replace hosts and executable for the testbed.
scripts/prepare_data.sh --root /mnt/fitune-data --init-root \
  --profile w01 --mode vdbench-format --clean \
  --vdbench /opt/vdbench50406/vdbench \
  --hosts node01,node02,node03,node04,node05,node06,node07,node08 \
  --user bench

# Deterministic direct-file preparation for fio.
scripts/prepare_data.sh --root /mnt/fitune-data --profile w10 \
  --mode random-prefill

# Inspect the operation without creating or deleting data.
scripts/prepare_data.sh --root /mnt/fitune-data --profile w14 \
  --mode random-prefill --dry-run
```

The `random-prefill` mode writes deterministic SHAKE-256-derived bytes and is the recommended mode for real read-performance measurements. `zero` writes actual zero bytes, while `sparse` creates holes and `allocate` reserves extents without guaranteeing that data blocks were written; the latter three modes are useful for smoke setup or capacity checks, not as interchangeable read-performance data. `--max-files` is available only for bounded smoke setup of direct-file profiles and must not be used for a formal run. The script requires an explicit `--profile`; it never creates all profiles implicitly.

The `w14` random prefill writes about 6.30 TiB across the edge and vertex files and can take substantial time and space. Check free capacity and the intended storage mount before starting it.

When several selected profiles share one FSD tree, the preparation script formats that tree once and skips duplicate formatting requests.

| ID | Preparation path | Structure or logical capacity |
|:--:|---|---:|
| `w01`--`w04` | Vdbench `format=only` using `depth=1,width=1,files=1024` | One native leaf directory, 1,024 files of 1 GiB |
| `w05`--`w06` | Vdbench `format=only` using `depth=1,width=10000,files=1000` | 10,000 native leaf directories, 1,000 files per leaf |
| `w07` | Vdbench `format=only` using `depth=1,width=100,files=100000` | 100 native leaf directories, 100,000 files per leaf |
| `w08`--`w09` | Vdbench `format=only` using the declared depth, width, and weighted sizes | Vdbench applies each size distribution during formatting |
| `w10` | Direct file `fio/testfile1` | 109,949,485,056 bytes; use `random-prefill` for read tests |
| `w11`--`w12` | Create the output root directory | IOR creates output and checkpoint files |
| `w13` | Vdbench `format=only` using `depth=4,width=6,files=10` | Vdbench applies the declared 3/4/3 size distribution |
| `w14` | Direct files because templates specify `formatsds=no` | 6.25 TiB edge file and 51 GiB vertex file |

The weighted file sizes in `w08` and `w09` are therefore generated by Vdbench itself; the preparation script does not cycle through a short size list and does not omit the 1 GiB category.

The large-file-count profiles `w05`--`w07` can require substantial Vdbench Java heap because Vdbench tracks file and directory metadata. As an illustrative starting point, a site may set `JAVA_OPTS="-Xms2g -Xmx8g"` in the Vdbench launcher, then measure master and client memory separately; this value is guidance, not a validated optimum. Record the first formatting time and a subsequent `format=no` startup/scan time for the selected client count. With `shared=yes`, later runs may still incur directory scanning because the usual per-host control-file shortcut is not assumed.

## Placeholders, clients, and host files

| Placeholder | Meaning | Used by |
|:--|:--|:--|
| `@HOST01@`--`@HOST16@` | Vdbench client host names or addresses | Vdbench profiles |
| `@USER@` | Remote execution user | Vdbench profiles |
| `@DATA@` | Dataset root | All profiles |
| `@VDBENCH@` | Vdbench 5.04.06 executable or wrapper | w01--w09, w13 |
| `@VDBENCH_INDEXED@` | Vdbench executable or wrapper for indexed profiles | w14 |
| `@HOSTS64@` | MPI host-file path | w11--w12 |
| `@IOR@` | IOR 4.0.0 executable | w11--w12 |
| `@MPIRUN@` | MPI launcher | w11--w12 |

The eight-client profiles declare `hd1`--`hd8` and explicitly assign one FWD entry to each host. `w07` declares `hd1`--`hd16` and does the same. `w08`, `w09`, and `w13` declare `hd1`--`hd16` and leave the FWD `host` field unset, so Vdbench applies its default distribution across the declared hosts. `w14` uses `h1`--`h16`, with each `sdN` assigned to `hN` and a non-overlapping range.

Before a multi-client Vdbench run, configure passwordless SSH or an equivalent authentication path from the master to every client. All clients must use the same Vdbench installation path, expose the same `@DATA@` mount path, and grant the test user permission to create, read, write, and remove the generated test tree.

The IOR scripts require a hostfile with 16 non-comment entries and `slots=4` on every entry before launching `-np 64`. Start from [`hosts64.example`](workloads/11-checkpoint-short/hosts64.example), replace the host names, and set `@HOSTS64@` to that file. The scripts save each checkpoint PID and wait for every background checkpoint, so a failed MPI process prevents the final bandwidth summary.

IOR variants are executable independently: `run.sh output` runs only output phases, `run.sh checkpoint` runs only checkpoint phases, and `run.sh all` runs the complete sequence. Each invocation writes its output files and logs under a unique run directory. The same commands are recorded in `catalog.json` under `variant_entries`.

## Tool versions and runtime dependencies

The reference matrix is recorded in `tool_versions.json`: Vdbench 5.04.06, fio 3.36, and IOR 4.0.0. Pin the MPI implementation before running IOR and record `mpirun --version`; the launcher and host-file syntax must support `mpirun -f`.

| Dependency group | Required components |
|:--|:--|
| Python | Python 3 for release validation, rendering, and safe direct-file creation |
| Shell | Bash 4 or newer |
| GNU Coreutils | `mkdir`, `grep`, `awk`, `tail`, `sha256sum` |
| util-linux / filesystem tools | POSIX fallocate support for `--mode allocate`; util-linux `fallocate` is optional, and `truncate` is not used for native Vdbench formatting |
| Workload tools | Vdbench 5.04.06, fio 3.36, IOR 4.0.0 |
| MPI | Hydra-compatible MPI runtime with `mpirun -f` support |
| Java | Java 8 or newer for Vdbench 5.04.06 |
| Numeric tools | `bc` for the long checkpoint summary |

## Reproduction

Run the release checks first:

```bash
python3 scripts/validate_release.py
python3 scripts/check_placeholders.py
sha256sum -c PUBLIC_SHA256SUMS
```

Install the pinned tools, prepare the selected profile with the appropriate mode, replace the placeholders, and run the concrete entry listed in `catalog.json`. Keep the generated logs and measurement outputs with the corresponding run record, together with tool-version output and the SHA-256 value of the input template.
