#!/usr/bin/env bash
set -euo pipefail

mode=${1:-all}
case "$mode" in
    output|checkpoint|all) ;;
    *) echo "usage: $0 [output|checkpoint|all]" >&2; exit 2 ;;
esac

hosts="@HOSTS64@" # MPI host-file path
ior="@IOR@" # IOR executable path
M=64 # 16 clients x 4 ranks/client
data_root="@DATA@"
run_id=${FITUNE_RUN_ID:-$(date +%Y%m%dT%H%M%S)-$$}
[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || {
    echo "Invalid FITUNE_RUN_ID" >&2
    exit 2
}
run_root="$data_root/checkpoint-short/runs/$run_id"
out_path="$run_root/output"
log_path="$run_root/logs"

guard_run_paths() {
    python3 - "$data_root" "checkpoint-short" "w11" "$run_id" <<'PY'
import os
from pathlib import Path
import re
import sys

root_arg, profile, subtree_label, run_id = sys.argv[1:]
root_arg = Path(root_arg)
if root_arg.is_symlink() or not root_arg.is_dir():
    raise SystemExit(f"invalid IOR data root: {root_arg}")
root = root_arg.resolve(strict=True)
if (root / ".fitune-generated").is_symlink() or not (root / ".fitune-generated").is_file() or (root / ".fitune-generated").read_text().strip() != "fitune-public-workload-data-v1":
    raise SystemExit(f"IOR data root is not marked: {root}")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", run_id):
    raise SystemExit("invalid FITUNE_RUN_ID")

def check_component(path: Path, allow_missing: bool = False) -> None:
    relative = path.relative_to(root)
    current = root
    for component in relative.parts:
        current /= component
        if current.is_symlink():
            raise SystemExit(f"IOR path contains a symlink: {current}")
        if current.exists() and not current.is_dir():
            raise SystemExit(f"IOR path component is not a directory: {current}")
        if not current.exists() and not allow_missing:
            raise SystemExit(f"IOR path component is missing: {current}")

profile_dir = root / profile
check_component(profile_dir)
marker = profile_dir / ".fitune-subtree"
if marker.is_symlink() or not marker.is_file() or marker.read_text().strip() != f"fitune-public-subtree-v1:{subtree_label}":
    raise SystemExit(f"IOR profile subtree is not marked: {profile_dir}")
if os.path.ismount(profile_dir):
    raise SystemExit(f"refusing mounted IOR profile subtree: {profile_dir}")

runs = profile_dir / "runs"
if runs.is_symlink():
    raise SystemExit(f"IOR runs directory is a symlink: {runs}")
if runs.exists():
    check_component(runs)
    runs_marker = runs / ".fitune-runs"
    if runs_marker.is_symlink() or not runs_marker.is_file() or runs_marker.read_text().strip() != "fitune-public-runs-v1":
        raise SystemExit(f"IOR runs directory is not marked: {runs}")
    if os.path.ismount(runs):
        raise SystemExit(f"refusing mounted IOR runs directory: {runs}")
else:
    os.mkdir(runs, 0o750)
    fd = os.open(runs / ".fitune-runs", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o640)
    with os.fdopen(fd, "w") as handle:
        handle.write("fitune-public-runs-v1\n")

run_root = runs / run_id
if run_root.exists() or run_root.is_symlink():
    raise SystemExit(f"IOR run directory already exists: {run_root}")
os.mkdir(run_root, 0o750)
fd = os.open(run_root / ".fitune-run", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o640)
with os.fdopen(fd, "w") as handle:
    handle.write(f"fitune-public-run-v1:{profile}:{run_id}\n")
os.mkdir(run_root / "output", 0o750)
os.mkdir(run_root / "logs", 0o750)
PY
}

validate_hostfile() {
    [[ -f "$hosts" ]] || { echo "missing MPI hostfile: $hosts" >&2; return 1; }
    awk '
        /^[[:space:]]*#/ || NF == 0 { next }
        NF != 2 || $2 != "slots=4" || seen[$1]++ { bad=1 }
        { count++ }
        END { if (count != 16 || bad) exit 1 }
    ' "$hosts" || { echo "hostfile must contain 16 unique clients with slots=4" >&2; return 1; }
}

validate_hostfile
guard_run_paths

output_gen() {
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s "$((4096 / M))" \
        -a posix -i 48 -m -k -e -t 1M -b 1M -o "$out_path/output$1" \
        > "$log_path/perf_output$1.log"
}

checkpoint_gen() {
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s "$((419392 / M))" \
        -a posix -i 1 -m -k -e -t 1M -b 1M -o "$out_path/checkpoint$1" \
        > "$log_path/perf_checkpoint$1.log"
}

summary() {
    local label=$1 log=$2 line bw
    line=$(grep "write" "$log" | tail -n 1 || true)
    [[ -n "$line" ]] || { echo "missing write summary: $log" >&2; return 1; }
    bw=$(awk '{print $4}' <<< "$line")
    echo "$label Average Mean(MiB) = $bw"
}

case "$mode" in
    output)
        output_gen 1
        summary output "$log_path/perf_output1.log"
        ;;
    checkpoint)
        checkpoint_gen 1
        summary checkpoint "$log_path/perf_checkpoint1.log"
        ;;
    all)
        output_gen 1
        echo "output 1 done"
        checkpoint_gen 1
        summary output "$log_path/perf_output1.log"
        summary checkpoint "$log_path/perf_checkpoint1.log"
        ;;
esac
