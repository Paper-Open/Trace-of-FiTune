#!/usr/bin/env bash
set -euo pipefail

hosts="@HOSTS64@" #MPI host-file path
ior="@IOR@" #IOR executable path
M=64 #16 clients x 4 ranks/client
out_path="@DATA@/checkpoint-short/"
validate_hostfile() {
    [[ -f "$hosts" ]] || { echo "missing MPI hostfile: $hosts" >&2; return 1; }
    awk '
        /^[[:space:]]*#/ || NF == 0 { next }
        $2 != "slots=4" { bad=1 }
        { count++ }
        END { if (count != 16 || bad) exit 1 }
    ' "$hosts" || { echo "hostfile must contain 16 clients with slots=4" >&2; return 1; }
}
validate_hostfile
mkdir -p "$out_path"
output_gen() {
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s `expr 4096 / $M` -a posix -i 48 -m -k -e -t 1M -b 1M -o "$out_path/output$1" > perf_output$1.log
} #Generate one output phase
checkpoint_gen() {
    "@MPIRUN@" -f "$hosts" -np "$M" "$ior" -w -s `expr 419392 / $M` -a posix -i 1 -m -k -e -t 1M -b 1M -o "$out_path/checkpoint$1" > perf_checkpoint$1.log
} #Generate one checkpoint phase

output_gen 1
echo "output 1 done"
checkpoint_gen 1

output_bw=$(grep "write" "perf_output1.log" | tail -n 1 | awk '{print $4}')
checkpoint_bw=$(grep "write" "perf_checkpoint1.log" | tail -n 1 | awk '{print $4}')

echo "output Average Mean(MiB) = $output_bw"
echo "checkpoint Average Mean(MiB) = $checkpoint_bw"
