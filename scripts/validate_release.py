#!/usr/bin/env python3
"""Validate catalog entries, phase metadata, and client-to-host assignments."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
cat = json.loads((ROOT / "catalog.json").read_text())
trace = json.loads((ROOT / "trace/30day_trace.json").read_text())
errors = []

if trace.get("workload_mapping", {}).get("catalog") != "catalog.json":
    errors.append("trace: workload_mapping.catalog must point to catalog.json")
if "operation_policy" in trace:
    errors.append("trace: tuning operation policy must not be published")

for item in cat["workloads"]:
    entry = ROOT / item["entry"]
    if not entry.is_file():
        errors.append(f"{item['id']}: entry is not a file: {item['entry']}")
    for path in item.get("entries", []):
        if not (ROOT / path).is_file():
            errors.append(f"{item['id']}: missing variant file: {path}")

    if item["id"] in {f"w{i:02d}" for i in range(1, 10)} | {"w13"}:
        text = entry.read_text()
        declared_hd = sorted({int(x) for x in re.findall(r"^hd=hd(\d+),", text, re.MULTILINE)})
        declared = list(range(1, item["clients"] + 1))
        if declared_hd != declared:
            errors.append(f"{item['id']}: declared hosts {declared_hd} != clients {declared}")
        fwd_hosts = sorted({int(x) for x in re.findall(r"host=hd(\d+)", text)})
        if item["id"] in {"w08", "w09", "w13"}:
            if fwd_hosts:
                errors.append(f"{item['id']}: expected Vdbench default host distribution, found explicit FWD hosts {fwd_hosts}")
        elif fwd_hosts != declared:
            errors.append(f"{item['id']}: FWD hosts {fwd_hosts} != declared clients {declared}")
    if item["id"] == "w14":
        text = "\n".join((ROOT / p).read_text() for p in item["entries"])
        hosts = sorted({int(x) for x in re.findall(r"host=h(\d+)", text)})
        if hosts != list(range(1, 17)):
            errors.append(f"w14: SD hosts {hosts} != h1-h16")
    if item["id"] in {"w11", "w12"}:
        script = entry.read_text()
        if "M=64" not in script or "mkdir -p \"$out_path\"" not in script:
            errors.append(f"{item['id']}: missing 64-rank or output-directory declaration")

for tr in trace["traces"]:
    if tr["id"] not in trace["deployment_mapping"]:
        errors.append(f"missing deployment mapping for {tr['id']}")
    prev = 0.0
    for ph in tr["phases"]:
        required = {"phase_id", "workload_id", "profile", "start_day", "end_day", "duration_days", "repeat_of"}
        missing = required - set(ph)
        if missing:
            errors.append(f"{tr['id']}/{ph['phase_id']}: missing {sorted(missing)}")
        if any(k in ph for k in ("reaction_time_hours", "tuning_window_hours", "maintenance_window_hours", "coverage_class", "recommendation_policy")):
            errors.append(f"{tr['id']}/{ph['phase_id']}: tuning metadata remains")
        unexpected = set(ph) - required - {"variant"}
        if unexpected:
            errors.append(f"{tr['id']}/{ph['phase_id']}: unexpected fields {sorted(unexpected)}")
        if abs(ph["duration_days"] - (ph["end_day"] - ph["start_day"])) > 1e-6:
            errors.append(f"{tr['id']}/{ph['phase_id']}: duration mismatch")
        if ph["start_day"] < prev:
            errors.append(f"{tr['id']}/{ph['phase_id']}: phases are not ordered")
        prev = ph["end_day"]
    if abs(prev - 30.0) > 1e-6:
        errors.append(f"{tr['id']}: end day {prev} != 30")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"validated {len(cat['workloads'])} catalog entries and {sum(len(t['phases']) for t in trace['traces'])} phases")
print("validated client mappings: w01-w06=8 hosts, w07=16 explicit FWD hosts, w08/w09/w13=16 default-distributed hosts, w14=16 explicit SD hosts, w11/w12=64 ranks over 16 clients")
