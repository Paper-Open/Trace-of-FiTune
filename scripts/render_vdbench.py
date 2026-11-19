#!/usr/bin/env python3
"""Render a Vdbench template with a safe two-stage shared-FSD formatter."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import sys


TOKEN = re.compile(r"@[A-Z][A-Z0-9_]*@")
FORMAT_NO = re.compile(r"(^|,)format=no(?=,|$)")
PATH_FIELD = re.compile(r"(?:^|,)(?:anchor|lun)=([^,\s]+)")
MARKER_NAME = ".fitune-generated"
MARKER_VALUE = "fitune-public-workload-data-v1"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"render_vdbench.py: {message}")


def check_inside(root: Path, candidate: Path, label: str, allow_root: bool = False) -> None:
    if not candidate.is_absolute():
        fail(f"{label} must be an absolute path: {candidate}")
    if ".." in candidate.parts:
        fail(f"{label} contains a parent traversal: {candidate}")
    try:
        relative = candidate.relative_to(root)
    except ValueError:
        fail(f"{label} is outside the dataset root: {candidate}")
    if not allow_root and not relative.parts:
        fail(f"{label} must be below the dataset root: {candidate}")

    current = root
    for component in relative.parts:
        current /= component
        if current.is_symlink():
            fail(f"{label} contains a symlink path component: {current}")


def safe_write(path: Path, text: str, root: Path, force: bool) -> None:
    check_inside(root, path, "output")
    path.parent.mkdir(parents=True, exist_ok=True)
    check_inside(root, path, "output")
    if path.is_symlink():
        fail(f"refusing symlink output: {path}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
    flags |= os.O_TRUNC if force else os.O_EXCL
    try:
        fd = os.open(path, flags, 0o640)
    except FileExistsError:
        fail(f"output already exists (use --force explicitly): {path}")
    except OSError as exc:
        fail(f"cannot create output {path}: {exc}")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(text)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def render_shared_format(text: str) -> str:
    output: list[str] = []
    replacements = 0
    for line in text.splitlines():
        if line.lstrip().startswith("#") or not FORMAT_NO.search(line):
            output.append(line)
            continue
        if not re.match(r"^\s*rd=", line):
            fail("format=no must appear on an rd= line")
        body = line.split("rd=", 1)[1]
        fields = body.split(",")
        if not any(field.startswith("fwd=") for field in fields):
            fail("formatting rd= line must specify fwd=")
        fields = [field for field in fields if field != "format=no"]
        indent = line[: len(line) - len(line.lstrip())]
        for stage, mode in (("step1", "format=(clean,only)"), ("step2", "format=(restart,only)")):
            stage_fields = fields.copy()
            stage_fields[0] = stage
            stage_fields.append(mode)
            output.append(f"{indent}rd={','.join(stage_fields)}")
        replacements += 1

    if replacements == 0:
        fail("input template does not contain format=no on an rd= line")
    output.insert(0, "# FiTune shared-FSD preparation: clean,only then restart,only")
    return "\n".join(output) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--vdbench", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--hosts", required=True, help="comma-separated host names in HOST01..HOST16 order")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if args.data.is_symlink() or not args.data.is_dir():
        fail(f"dataset root must be a real directory: {args.data}")
    root = args.data.resolve(strict=True)
    marker = root / MARKER_NAME
    if marker.is_symlink() or not marker.is_file() or marker.read_text().strip() != MARKER_VALUE:
        fail(f"dataset root is not marked by {MARKER_NAME}: {root}")

    text = args.input.read_text()
    hosts = [host.strip() for host in args.hosts.split(",") if host.strip()]
    replacements = {
        "@DATA@": str(root),
        "@VDBENCH@": args.vdbench,
        "@VDBENCH_INDEXED@": args.vdbench,
        "@USER@": args.user,
    }
    for index, host in enumerate(hosts, start=1):
        replacements[f"@HOST{index:02d}@"] = host
    for token, value in replacements.items():
        text = text.replace(token, value)

    unresolved = sorted(set(TOKEN.findall(text)))
    if unresolved:
        fail(f"unresolved placeholders: {', '.join(unresolved)}")

    anchors = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("#"):
            continue
        if re.match(r"^\s*(?:fsd|sd)=", line):
            for value in PATH_FIELD.findall(line):
                anchors.append((line_number, value))
    if not anchors:
        fail("input template contains no FSD anchor or SD lun path")
    for line_number, value in anchors:
        check_inside(root, Path(value), f"FSD path on line {line_number}")

    safe_write(args.output, render_shared_format(text), root, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
