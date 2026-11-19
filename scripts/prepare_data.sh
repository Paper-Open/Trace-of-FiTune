#!/usr/bin/env bash
set -euo pipefail

# Prepare public workload data. Vdbench profiles are always formatted by
# Vdbench itself; this script never invents a Vdbench file tree.

SCRIPT_DIR=$(cd -P "$(dirname "$0")" && pwd)
ROOT=${DATA_ROOT:-$PWD/fitune-data}
MODE="vdbench-format"
PROFILE_LIST=""
MAX_FILES=0
CLEAN=0
FORCE=0
DRY_RUN=0
INIT_ROOT=0
VDBENCH=""
HOSTS=""
USER_NAME=${USER:-}
TEMPLATE=""
CREATED=0
ROOT_CREATED=0
MARKER_NAME=".fitune-generated"
MARKER_VALUE="fitune-public-workload-data-v1"

usage() {
    cat <<'USAGE'
Usage: scripts/prepare_data.sh --profile LIST [options]

Required:
  --profile LIST          Comma-separated workload IDs (w01..w14)

General options:
  --root PATH             Dedicated dataset root (default: ./fitune-data)
  --mode MODE             vdbench-format, random-prefill, zero, sparse,
                          allocate, or directory (default: vdbench-format)
  --init-root             Initialize an existing empty directory with a marker
  --clean                 Remove selected generated subtrees; marker required
  --force                 Permit overwriting existing regular data files
  --dry-run               Print the planned operation without changing data
  --max-files N           Limit direct-file preparation for smoke tests only

Vdbench format options (w01-w09 and w13):
  --vdbench PATH          Executable or wrapper for Vdbench 5.04.06
  --hosts LIST            Comma-separated hosts in HOST01..HOST16 order
  --user USER             Remote execution user (default: $USER)
  --template PATH         One source template, when --profile has one ID

Examples:
  scripts/prepare_data.sh --root /mnt/fitune-data --init-root \
    --profile w01 --mode vdbench-format --clean \
    --vdbench /opt/vdbench50406/vdbench \
    --hosts node01,node02,node03,node04,node05,node06,node07,node08 \
    --user bench
  scripts/prepare_data.sh --root /mnt/fitune-data --profile w10 \
    --mode random-prefill --init-root
  scripts/prepare_data.sh --root /mnt/fitune-data --profile w05 \
    --mode vdbench-format --dry-run --vdbench /opt/vdbench/vdbench \
    --hosts node01,node02,node03,node04,node05,node06,node07,node08

The Vdbench mode renders a format-only copy of the selected template, changes
the run definition to format=only, and invokes Vdbench. Vdbench therefore
creates its native vdb*.dir/vdb_f*.file structure. The runtime template keeps
format=no and must be run only after this preparation step.
USAGE
}

die() { echo "prepare_data.sh: $*" >&2; exit 2; }

while (($#)); do
    case "$1" in
        --root) [[ $# -ge 2 ]] || die "--root needs a value"; ROOT=$2; shift 2 ;;
        --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; PROFILE_LIST=$2; shift 2 ;;
        --mode) [[ $# -ge 2 ]] || die "--mode needs a value"; MODE=$2; shift 2 ;;
        --max-files) [[ $# -ge 2 ]] || die "--max-files needs a value"; MAX_FILES=$2; shift 2 ;;
        --vdbench) [[ $# -ge 2 ]] || die "--vdbench needs a value"; VDBENCH=$2; shift 2 ;;
        --hosts) [[ $# -ge 2 ]] || die "--hosts needs a value"; HOSTS=$2; shift 2 ;;
        --user) [[ $# -ge 2 ]] || die "--user needs a value"; USER_NAME=$2; shift 2 ;;
        --template) [[ $# -ge 2 ]] || die "--template needs a value"; TEMPLATE=$2; shift 2 ;;
        --init-root) INIT_ROOT=1; shift ;;
        --clean) CLEAN=1; shift ;;
        --force) FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -n "$PROFILE_LIST" ]] || die "--profile is required; refusing an implicit all-profile run"
[[ "$PROFILE_LIST" != all ]] || die "all profiles must be selected explicitly"
[[ "$PROFILE_LIST" =~ ^w(0[1-9]|1[0-4])(,w(0[1-9]|1[0-4]))*$ ]] || \
    die "--profile must be a comma-separated list of w01..w14"
[[ "$MAX_FILES" =~ ^[0-9]+$ ]] || die "--max-files must be a non-negative integer"
case "$MODE" in
    vdbench-format|random-prefill|zero|sparse|allocate|directory) ;;
    *) die "unsupported --mode: $MODE" ;;
esac

IFS=',' read -ra PROFILES <<< "$PROFILE_LIST"

canonicalize_root() {
    local raw=$ROOT parent base
    [[ -n "$raw" && "$raw" != "/" ]] || die "--root must be a dedicated non-root directory"
    if [[ -L "$raw" ]]; then
        die "--root must not be a symbolic link: $raw"
    fi
    if [[ -e "$raw" ]]; then
        [[ -d "$raw" ]] || die "--root is not a directory: $raw"
        ROOT=$(cd -P -- "$raw" && pwd)
    else
        parent=$(dirname -- "$raw")
        base=$(basename -- "$raw")
        [[ "$base" != "." && "$base" != ".." && -n "$base" ]] || die "invalid --root: $raw"
        [[ -d "$parent" ]] || die "parent directory does not exist: $parent"
        parent=$(cd -P -- "$parent" && pwd)
        ROOT="$parent/$base"
        if (( ! DRY_RUN )); then
            mkdir -- "$ROOT"
            ROOT_CREATED=1
            ROOT=$(cd -P -- "$ROOT" && pwd)
        fi
    fi
    [[ "$ROOT" != "/" ]] || die "refusing root directory"
}

canonicalize_root
MARKER="$ROOT/$MARKER_NAME"

if (( DRY_RUN )); then
    echo "[dry-run] dataset root: $ROOT"
    echo "[dry-run] profile(s): $PROFILE_LIST; mode: $MODE"
else
    if [[ -L "$MARKER" ]]; then
        die "dataset marker must not be a symbolic link: $MARKER"
    fi
    if [[ -e "$MARKER" ]]; then
        [[ -f "$MARKER" ]] || die "dataset marker is not a regular file: $MARKER"
        grep -Fqx "$MARKER_VALUE" "$MARKER" || die "unexpected dataset marker: $MARKER"
    else
        if find "$ROOT" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
            (( INIT_ROOT )) || die "existing root is not marked; use --init-root only for an empty dedicated directory"
            die "--init-root requires an empty directory: $ROOT"
        fi
        (( INIT_ROOT || ROOT_CREATED )) || die "use --init-root to initialize this dedicated directory"
        printf '%s\n' "$MARKER_VALUE" > "$MARKER"
    fi
    if (( CLEAN != 0 )) && [[ ! -f "$MARKER" ]]; then
        die "--clean requires a marked dataset root"
    fi
fi

is_under_root() {
    case "$1" in
        "$ROOT"/*) return 0 ;;
        *) die "refusing path outside dataset root: $1" ;;
    esac
}

assert_no_symlink_path() {
    local path=$1 current=$ROOT part
    is_under_root "$path"
    local relative=${path#"$ROOT"/}
    IFS='/' read -ra parts <<< "$relative"
    for part in "${parts[@]}"; do
        current="$current/$part"
        [[ ! -L "$current" ]] || die "refusing symlink path component: $current"
    done
}

safe_mkdir() {
    local path=$1
    assert_no_symlink_path "$path"
    mkdir -p -- "$path"
}

remove_generated_root() {
    local path=$1
    assert_no_symlink_path "$path"
    if (( CLEAN )); then
        [[ ! -L "$path" ]] || die "refusing to remove symlink: $path"
        if (( DRY_RUN )); then
            echo "[dry-run] would remove $path"
        else
            rm -rf -- "$path"
        fi
    fi
    if (( ! DRY_RUN )); then
        safe_mkdir "$path"
    fi
}

create_file() {
    local path=$1 bytes=$2
    assert_no_symlink_path "$path"
    (( MAX_FILES == 0 || CREATED < MAX_FILES )) || return 1
    if (( DRY_RUN )); then
        echo "[dry-run] would create $path ($bytes bytes, mode=$MODE)"
    else
        if (( FORCE )); then
            python3 "$SCRIPT_DIR/create_data_file.py" \
                --root "$ROOT" --path "$path" --size "$bytes" --mode "$MODE" --force
        else
            python3 "$SCRIPT_DIR/create_data_file.py" \
                --root "$ROOT" --path "$path" --size "$bytes" --mode "$MODE"
        fi
    fi
    CREATED=$((CREATED + 1))
}

template_for_profile() {
    case "$1" in
        w01) echo "workloads/01-std-rand-write/workload.vdb" ;;
        w02) echo "workloads/02-std-rand-read/workload.vdb" ;;
        w03) echo "workloads/03-std-seq-write/workload.vdb" ;;
        w04) echo "workloads/04-std-seq-read/workload.vdb" ;;
        w05) echo "workloads/05-small-write/workload.vdb" ;;
        w06) echo "workloads/06-small-read/workload.vdb" ;;
        w07) echo "workloads/07-mixed400k/workload.vdb" ;;
        w08) echo "workloads/08-operation-mix/workload.vdb" ;;
        w09) echo "workloads/09-bandwidth-mix/workload.vdb" ;;
        w13) echo "workloads/13-inference/workload.vdb" ;;
        *) return 1 ;;
    esac
}

format_vdbench_profile() {
    local profile=$1 input output run_dir
    input=${TEMPLATE:-$(template_for_profile "$profile")}
    [[ -f "$input" ]] || die "template does not exist: $input"
    [[ -n "$VDBENCH" ]] || die "--vdbench is required for --mode vdbench-format"
    [[ -n "$HOSTS" ]] || die "--hosts is required for --mode vdbench-format"
    [[ -n "$USER_NAME" ]] || die "--user is required for --mode vdbench-format"
    if (( ! DRY_RUN )) && ! command -v "$VDBENCH" >/dev/null 2>&1 && [[ ! -x "$VDBENCH" ]]; then
        die "Vdbench executable or wrapper is not executable: $VDBENCH"
    fi
    if (( DRY_RUN )); then
        echo "[dry-run] would render $input with format=only and invoke $VDBENCH -f <rendered-$profile.vdb>"
        return 0
    fi
    run_dir="$ROOT/.fitune-vdbench"
    safe_mkdir "$run_dir"
    output="$run_dir/$profile.format.vdb"
    python3 "$SCRIPT_DIR/render_vdbench.py" \
        --input "$input" --output "$output" --data "$ROOT" \
        --vdbench "$VDBENCH" --user "$USER_NAME" --hosts "$HOSTS"
    (cd "$run_dir" && "$VDBENCH" -f "$output")
    echo "formatted $profile with native Vdbench format=only structure"
}

prepare_direct_profile() {
    local profile=$1
    CREATED=0
    case "$profile" in
        w10)
            remove_generated_root "$ROOT/fio"
            if (( MAX_FILES == 0 || CREATED < MAX_FILES )); then
                create_file "$ROOT/fio/testfile1" 109949485056
            fi
            echo "prepared $ROOT/fio/testfile1 ($CREATED file, mode=$MODE)"
            ;;
        w14)
            remove_generated_root "$ROOT/indexed"
            if (( MAX_FILES == 0 || CREATED < MAX_FILES )); then
                create_file "$ROOT/indexed/edge-records" 6871947673600
            fi
            if (( MAX_FILES == 0 || CREATED < MAX_FILES )); then
                create_file "$ROOT/indexed/vertex-records" 54760833024
            fi
            echo "prepared $ROOT/indexed ($CREATED files, mode=$MODE)"
            ;;
        w11) remove_generated_root "$ROOT/checkpoint-short"; echo "prepared $ROOT/checkpoint-short (directory only)" ;;
        w12) remove_generated_root "$ROOT/checkpoint-long"; echo "prepared $ROOT/checkpoint-long (directory only)" ;;
        *) die "$profile requires --mode vdbench-format" ;;
    esac
}

if [[ "$MODE" == "vdbench-format" ]]; then
    if (( ! DRY_RUN && ! CLEAN )); then
        die "Vdbench format=only can delete an existing native tree; pass --clean explicitly"
    fi
    [[ -z "$TEMPLATE" || ${#PROFILES[@]} -eq 1 ]] || die "--template is valid only with one profile"
    for profile in "${PROFILES[@]}"; do
        template_for_profile "$profile" >/dev/null || die "$profile is not a Vdbench FSD profile; use a direct-file mode"
        format_vdbench_profile "$profile"
    done
else
    for profile in "${PROFILES[@]}"; do
        case "$MODE:$profile" in
            random-prefill:w10|random-prefill:w14|zero:w10|zero:w14|sparse:w10|sparse:w14|allocate:w10|allocate:w14|directory:w11|directory:w12)
                prepare_direct_profile "$profile" ;;
            *) die "$profile is incompatible with --mode $MODE" ;;
        esac
    done
fi
