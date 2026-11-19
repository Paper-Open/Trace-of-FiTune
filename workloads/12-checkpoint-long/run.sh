#!/usr/bin/env bash
set -euo pipefail

hosts="@HOSTS64@" #MPI host-file path
ior="@IOR@" #IOR executable path
M=64 #16 clients x 4 ranks/client
out_path="@DATA@/checkpoint-long/"
mkdir -p "$out_path"
output_gen() {
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s `expr 4096 / $M` -a posix -i 48 -m -k -e -t 1M -b 1M -o "$out_path/output$1" > perf_output$1.log
} #Generate one output phase
checkpoint_gen() {
    [[ -n ${2:-} ]] && tail --pid="$2" -f /dev/null; #Wait for the previous checkpoint (checkpoint) to finish
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s `expr 419392 / $M` -a posix -i 1 -m -k -e -t 1M -b 1M -o "$out_path/checkpoint$1" > perf_checkpoint$1.log
} #Generate one checkpoint phase
cal_avg() {
    local sum=0
    local count=0
    local log_files=("$@")
    for log in "${log_files[@]}"; do
        mean_bw=$(grep "write" "$log" | tail -n 1 | awk '{print $4}')
        sum=$(echo "$sum + $mean_bw" | bc)
        count=$((count + 1))
    done
    average=$(echo "scale=2; $sum / $count" | bc)
    echo "$average"
}

output_gen 1
echo "output 1 done"
checkpoint_gen 1 &
last_checkpoint_gen_pid=$!
output_gen 2
echo "output 2 done"
checkpoint_gen 2 $last_checkpoint_gen_pid &
last_checkpoint_gen_pid=$!
output_gen 3
echo "output 3 done"
checkpoint_gen 3 $last_checkpoint_gen_pid &
wait

output_log_files=("perf_output1.log" "perf_output2.log" "perf_output3.log")
checkpoint_log_files=("perf_checkpoint1.log" "perf_checkpoint2.log" "perf_checkpoint3.log")
output_bw=$(cal_avg "${output_log_files[@]}")
checkpoint_bw=$(cal_avg "${checkpoint_log_files[@]}")
echo "output Average Mean(MiB) = $output_bw"
echo "checkpoint Average Mean(MiB) = $checkpoint_bw"
