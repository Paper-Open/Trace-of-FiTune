#!/usr/bin/env python3
"""List and validate public-template placeholders."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    *{f"@HOST{i:02d}@" for i in range(1, 17)},
    "@USER@", "@DATA@", "@VDBENCH@", "@VDBENCH_INDEXED@",
    "@HOSTS64@", "@IOR@", "@MPIRUN@",
}
TOKEN = re.compile(r"@[A-Z][A-Z0-9_]*@")
files = sorted((ROOT / "workloads").rglob("*"))
seen = set()
errors = []
for path in files:
    if not path.is_file():
        continue
    text = path.read_text(errors="replace")
    tokens = sorted(set(TOKEN.findall(text)))
    unknown = [t for t in tokens if t not in EXPECTED]
    if unknown:
        errors.append(f"{path.relative_to(ROOT)}: unknown {unknown}")
    if tokens:
        print(f"{path.relative_to(ROOT)}: {', '.join(tokens)}")
        seen.update(tokens)
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"validated {len(seen)} known placeholder types")
