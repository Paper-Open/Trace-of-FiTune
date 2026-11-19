#!/usr/bin/env python3
"""Render a Vdbench template and turn its runtime RD into format=only."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


TOKEN = re.compile(r"@[A-Z][A-Z0-9_]*@")


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"render_vdbench.py: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--data", required=True)
    parser.add_argument("--vdbench", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--hosts", required=True, help="comma-separated host names in HOST01..HOST16 order")
    args = parser.parse_args()

    text = args.input.read_text()
    hosts = [host.strip() for host in args.hosts.split(",") if host.strip()]
    replacements = {
        "@DATA@": args.data,
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
    if "format=no" not in text:
        fail("input template does not contain format=no")
    text = text.replace("format=no", "format=only")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
