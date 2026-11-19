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
out_path="@DATA@/checkpoint-long/$run_id"
log_path="@DATA@/.fitune-runs/checkpoint-long-$run_id"

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
    [[ -n ${2:-} ]] && tail --pid="$2" -f /dev/null
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s "$((419392 / M))" \
        -a posix -i 1 -m -k -e -t 1M -b 1M -o "$out_path/checkpoint$1" \
        > "$log_path/perf_checkpoint$1.log"
}

cal_avg() {
    local sum=0 count=0 log mean_bw
    for log in "$@"; do
        mean_bw=$(grep "write" "$log" | tail -n 1 | awk '{print $4}')
        [[ -n "$mean_bw" ]] || { echo "missing write summary: $log" >&2; return 1; }
        sum=$(echo "$sum + $mean_bw" | bc)
        count=$((count + 1))
    done
    echo "$(echo "scale=2; $sum / $count" | bc)"
}

run_outputs() {
    local i
    for i in 1 2 3; do
        output_gen "$i"
        echo "output $i done"
    done
}

run_checkpoints() {
    local i
    for i in 1 2 3; do
        checkpoint_gen "$i"
        echo "checkpoint $i done"
    done
}

run_all() {
    output_gen 1
    echo "output 1 done"
    checkpoint_gen 1 &
    checkpoint1_pid=$!
    output_gen 2
    echo "output 2 done"
    checkpoint_gen 2 "$checkpoint1_pid" &
    checkpoint2_pid=$!
    output_gen 3
    echo "output 3 done"
    checkpoint_gen 3 "$checkpoint2_pid" &
    checkpoint3_pid=$!
    wait "$checkpoint1_pid"
    wait "$checkpoint2_pid"
    wait "$checkpoint3_pid"
}

case "$mode" in
    output)
        run_outputs
        output_logs=("$log_path/perf_output1.log" "$log_path/perf_output2.log" "$log_path/perf_output3.log")
        echo "output Average Mean(MiB) = $(cal_avg "${output_logs[@]}")"
        ;;
    checkpoint)
        run_checkpoints
        checkpoint_logs=("$log_path/perf_checkpoint1.log" "$log_path/perf_checkpoint2.log" "$log_path/perf_checkpoint3.log")
        echo "checkpoint Average Mean(MiB) = $(cal_avg "${checkpoint_logs[@]}")"
        ;;
    all)
        run_all
        output_logs=("$log_path/perf_output1.log" "$log_path/perf_output2.log" "$log_path/perf_output3.log")
        checkpoint_logs=("$log_path/perf_checkpoint1.log" "$log_path/perf_checkpoint2.log" "$log_path/perf_checkpoint3.log")
        echo "output Average Mean(MiB) = $(cal_avg "${output_logs[@]}")"
        echo "checkpoint Average Mean(MiB) = $(cal_avg "${checkpoint_logs[@]}")"
        ;;
esac
