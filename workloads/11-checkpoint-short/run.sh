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
run_id=${FITUNE_RUN_ID:-$(date +%Y%m%dT%H%M%S)-$$}
out_path="@DATA@/checkpoint-short/$run_id"
log_path="@DATA@/.fitune-runs/checkpoint-short-$run_id"

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
mkdir -p "$out_path" "$log_path"

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
