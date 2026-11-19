#!/usr/bin/env bash
set -euo pipefail

# Prepare the file trees referenced by the public workload templates.
# Default mode is sparse: reads return deterministic zeros without allocating
# the full logical capacity. Use --mode allocate to reserve filesystem blocks,
# or --mode zero to write zero bytes across every requested extent.

ROOT="${DATA_ROOT:-$PWD/fitune-data}"
MODE="sparse"
PROFILE_LIST="all"
MAX_FILES=0
CLEAN=0
CREATED=0

usage() {
    cat <<'USAGE'
Usage: scripts/prepare_data.sh [options]

Options:
  --root PATH             Dataset root (default: ./fitune-data)
  --profile LIST          Comma-separated w01..w14 or all (default: all)
  --mode MODE             sparse, allocate, or zero (default: sparse)
  --max-files N           Stop after N created files per profile (smoke setup)
  --clean                 Remove selected profile roots before preparing
  -h, --help              Show this help

Examples:
  scripts/prepare_data.sh --root /mnt/test-data --profile w01,w02 --mode allocate
  scripts/prepare_data.sh --root /mnt/test-data --profile w13 --mode sparse
  scripts/prepare_data.sh --root /mnt/test-data --profile w05 --max-files 1000
USAGE
}

while (($#)); do
    case "$1" in
        --root) ROOT=$2; shift 2 ;;
        --profile) PROFILE_LIST=$2; shift 2 ;;
        --mode) MODE=$2; shift 2 ;;
        --max-files) MAX_FILES=$2; shift 2 ;;
        --clean) CLEAN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$MODE" in
    sparse|allocate|zero) ;;
    *) echo "--mode must be sparse, allocate, or zero" >&2; exit 2 ;;
esac
if ! [[ "$MAX_FILES" =~ ^[0-9]+$ ]]; then
    echo "--max-files must be a non-negative integer" >&2; exit 2
fi
if ! [[ "$PROFILE_LIST" == all || "$PROFILE_LIST" =~ ^w(0[1-9]|1[0-4])(,w(0[1-9]|1[0-4]))*$ ]]; then
    echo "--profile must be all or a comma-separated list of w01..w14" >&2; exit 2
fi

profile_enabled() {
    [[ "$PROFILE_LIST" == all || ",${PROFILE_LIST}," == *",$1,"* ]]
}

reset_counter() { CREATED=0; }
limit_reached() { (( MAX_FILES > 0 && CREATED >= MAX_FILES )); }

make_file() {
    local path=$1 bytes=$2
    limit_reached && return 1
    mkdir -p "$(dirname "$path")"
    case "$MODE" in
        sparse) truncate -s "$bytes" "$path" ;;
        allocate)
            command -v fallocate >/dev/null 2>&1 || {
                echo "allocate mode requires fallocate" >&2; exit 2;
            }
            fallocate -l "$bytes" "$path"
            ;;
        zero)
            local full=$((bytes / 1048576)) rem=$((bytes % 1048576))
            : > "$path"
            if (( full > 0 )); then
                dd if=/dev/zero of="$path" bs=1M count="$full" conv=fsync status=none
            fi
            if (( rem > 0 )); then
                dd if=/dev/zero of="$path" bs=1 count="$rem" seek=$((full * 1048576)) conv=notrunc,fsync status=none
            fi
            ;;
    esac
    CREATED=$((CREATED + 1))
    return 0
}

remove_root() {
    local path=$1
    if (( CLEAN )); then rm -rf -- "$path"; fi
    mkdir -p "$path"
}

prepare_flat_files() {
    local root=$1 count=$2 bytes=$3 prefix=$4 i
    remove_root "$root"
    for ((i=0; i<count; i++)); do
        limit_reached && break
        make_file "$root/${prefix}-$(printf '%08d' "$i")" "$bytes"
    done
    echo "prepared $root ($CREATED files, mode=$MODE)"
}

prepare_single_file() {
    local root=$1 name=$2 bytes=$3
    remove_root "$root"
    if ! limit_reached; then
        make_file "$root/$name" "$bytes"
    fi
    echo "prepared $root/$name ($CREATED file, mode=$MODE)"
}

prepare_nested_files() {
    local anchor=$1 depth=$2 width=$3 files=$4 bytes_list=$5
    remove_root "$anchor"
    nested_recurse "$anchor" "$depth" "$width" "$files" "$bytes_list"
}

nested_recurse() {
    local base=$1 depth=$2 width=$3 files=$4 bytes_list=$5 i f bytes
    if (( depth == 0 )); then
        IFS=',' read -ra sizes <<< "$bytes_list"
        for ((f=0; f<files; f++)); do
            limit_reached && return 0
            bytes=${sizes[$((f % ${#sizes[@]}))]}
            make_file "$base/file-$(printf '%06d' "$f")" "$bytes"
        done
        return 0
    fi
    for ((i=0; i<width; i++)); do
        nested_recurse "$base/level${depth}-$(printf '%02d' "$i")" $((depth - 1)) "$width" "$files" "$bytes_list" || return 0
    done
}

prepare_profile() {
    local profile=$1
    reset_counter
    case "$profile" in
        w01|w02|w03|w04)
            prepare_flat_files "$ROOT/standard-large" 1024 1073741824 file ;;
        w05|w06)
            prepare_flat_files "$ROOT/smallfile" 10000000 4096 file ;;
        w07)
            # The template specifies width=100 and files=100000 per anchor.
            prepare_nested_files "$ROOT/mixed400k" 1 100 100000 409600 ;;
        w08)
            local i
            for i in 0 1 2 3; do prepare_nested_files "$ROOT/mixed-ops/dir$i" 4 5 36 '65536,131072'; done
            for i in 4 5 6 7; do prepare_nested_files "$ROOT/mixed-ops/dir$i" 4 5 4 '1048576,2097152,8388608,134217728,1073741824'; done
            ;;
        w09)
            local i
            for i in 0 1 2 3; do prepare_nested_files "$ROOT/mixed-bandwidth/dir$i" 4 5 36 '65536,131072'; done
            for i in 4 5 6 7; do prepare_nested_files "$ROOT/mixed-bandwidth/dir$i" 4 5 4 '1048576,2097152,8388608,134217728,1073741824'; done
            ;;
        w10)
            prepare_single_file "$ROOT/fio" testfile1 109949485056 ;;
        w11) remove_root "$ROOT/checkpoint-short"; echo "prepared $ROOT/checkpoint-short (directory only)" ;;
        w12) remove_root "$ROOT/checkpoint-long"; echo "prepared $ROOT/checkpoint-long (directory only)" ;;
        w13)
            prepare_nested_files "$ROOT/ai" 4 6 10 '53739520,53739520,53739520,107347968,107347968,107347968,107347968,214695936,214695936,214695936' ;;
        w14)
            remove_root "$ROOT/indexed"
            if ! limit_reached; then
                make_file "$ROOT/indexed/edge-records" 6871947673600
            fi
            if ! limit_reached; then
                make_file "$ROOT/indexed/vertex-records" 54760833024
            fi
            echo "prepared $ROOT/indexed (edge and vertex files)" ;;
    esac
}

mkdir -p "$ROOT"
if [[ "$PROFILE_LIST" == all ]]; then
    for profile in w01 w02 w03 w04 w05 w06 w07 w08 w09 w10 w11 w12 w13 w14; do
        prepare_profile "$profile"
    done
else
    IFS=',' read -ra profiles <<< "$PROFILE_LIST"
    for profile in "${profiles[@]}"; do prepare_profile "$profile"; done
fi
