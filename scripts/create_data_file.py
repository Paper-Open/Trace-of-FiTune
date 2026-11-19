#!/usr/bin/env python3
"""Safely create one non-Vdbench data file under a marked dataset root."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import sys
import stat
import tempfile


CHUNK = 1024 * 1024
MARKER_NAME = ".fitune-generated"
MARKER_VALUE = "fitune-public-workload-data-v1"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"create_data_file.py: {message}")


def check_path(root: Path, path: Path) -> None:
    root = root.resolve(strict=True)
    if not path.is_absolute():
        path = root / path
    try:
        if os.path.commonpath((str(root), str(path.parent.resolve(strict=False)))) != str(root):
            fail(f"refusing path outside dataset root: {path}")
    except ValueError:
        fail(f"refusing path outside dataset root: {path}")

    current = root
    relative = path.relative_to(root)
    for component in relative.parts[:-1]:
        current /= component
        if current.is_symlink():
            fail(f"refusing symlink directory: {current}")
        if current.exists() and not current.is_dir():
            fail(f"path component is not a directory: {current}")

    if path.is_symlink():
        fail(f"refusing symlink target: {path}")


def deterministic_bytes(seed: bytes, index: int, size: int) -> bytes:
    return hashlib.shake_256(seed + index.to_bytes(8, "big")).digest(size)


def check_existing_target(path: Path, force: bool) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISLNK(info.st_mode):
        fail(f"refusing symlink target: {path}")
    if not stat.S_ISREG(info.st_mode):
        fail(f"refusing non-regular target: {path}")
    if info.st_nlink != 1:
        fail(f"refusing multiply-linked target: {path}")
    if not force:
        fail(f"refusing to overwrite existing file (use --force): {path}")


def fsync_parent(path: Path) -> None:
    try:
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass


def write_file(path: Path, size: int, mode: str, seed: bytes, force: bool) -> None:
    check_existing_target(path, force)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.fitune-", dir=path.parent)
    temporary = Path(temporary_name)
    published = False
    try:
        try:
            if mode == "sparse":
                os.ftruncate(fd, size)
            elif mode == "allocate":
                if not hasattr(os, "posix_fallocate"):
                    fail("allocate mode requires os.posix_fallocate")
                os.posix_fallocate(fd, 0, size)
            else:
                digest_seed = seed
                written = 0
                block = b"\0" * CHUNK if mode == "zero" else None
                chunk_index = 0
                while written < size:
                    nbytes = min(CHUNK, size - written)
                    payload = block[:nbytes] if block is not None else deterministic_bytes(digest_seed, chunk_index, nbytes)
                    view = memoryview(payload)
                    while view:
                        written_now = os.write(fd, view)
                        if written_now <= 0:
                            fail(f"short write while creating {path}")
                        written += written_now
                        view = view[written_now:]
                    chunk_index += 1
            os.fsync(fd)
            os.fchmod(fd, 0o640)
        finally:
            os.close(fd)

        if force:
            check_existing_target(path, True)
            os.replace(temporary, path)
            published = True
        else:
            try:
                os.link(temporary, path)
            except FileExistsError:
                fail(f"refusing to overwrite existing file (use --force): {path}")
            temporary.unlink()
            published = True
        fsync_parent(path)
    finally:
        # The finally block also runs for KeyboardInterrupt/SystemExit.  A
        # linked-but-not-yet-unlinked temporary is safe to remove because the
        # published target has its own directory entry.
        if not published:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--path", required=True, type=Path)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--mode", choices=("sparse", "allocate", "zero", "random-prefill"), required=True)
    parser.add_argument("--seed", default="fitune-public-workload-v1")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if args.size < 0:
        fail("--size must be non-negative")
    if args.root.is_symlink() or not args.root.is_dir():
        fail(f"dataset root must be a real directory: {args.root}")
    root = args.root.resolve(strict=True)
    marker = root / MARKER_NAME
    if marker.is_symlink() or not marker.is_file() or marker.read_text().strip() != MARKER_VALUE:
        fail(f"dataset root is not marked by {MARKER_NAME}: {root}")
    path = args.path if args.path.is_absolute() else root / args.path
    check_path(root, path)
    path.parent.mkdir(parents=True, exist_ok=True)
    check_path(root, path)
    relative_path = path.relative_to(root).as_posix().encode("utf-8")
    file_seed = args.seed.encode("utf-8") + b":" + relative_path
    write_file(path, args.size, args.mode, file_seed, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
