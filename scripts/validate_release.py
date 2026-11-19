#!/usr/bin/env python3
"""Validate the public catalog, traces, CSV projection, and launch mappings."""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path
import json
import math
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
cat = json.loads((ROOT / "catalog.json").read_text())
trace = json.loads((ROOT / "trace/30day_trace.json").read_text())
errors: list[str] = []
catalog_by_id = {item["id"]: item for item in cat["workloads"]}


def add(message: str) -> None:
    errors.append(message)


def item_matches_phase(item: dict, phase: dict) -> bool:
    profile = phase["profile"]
    aliases: set[str] = set()
    paths = [item["entry"], *item.get("entries", [])]
    for path in paths:
        relative = Path(path).relative_to("workloads").as_posix()
        aliases.add(relative)
        aliases.add(Path(relative).parent.as_posix())
    return profile in aliases


def validate_catalog() -> None:
    expected_vdbench = {f"w{i:02d}" for i in range(1, 10)} | {"w13"}
    for item in cat["workloads"]:
        entry = ROOT / item["entry"]
        if not entry.is_file():
            add(f"{item['id']}: entry is not a file: {item['entry']}")
        for path in item.get("entries", []):
            if not (ROOT / path).is_file():
                add(f"{item['id']}: missing variant file: {path}")
        if not item.get("variants"):
            add(f"{item['id']}: variants must be non-empty")
        variant_entries = item.get("variant_entries", {})
        if set(variant_entries) != set(item.get("variants", [])):
            add(f"{item['id']}: variant_entries must cover exactly variants")
        for variant, command in variant_entries.items():
            entry_path = command.split()[0]
            if not (ROOT / entry_path).is_file():
                add(f"{item['id']}/{variant}: variant entry is not a file: {entry_path}")

        if item["id"] in expected_vdbench and entry.is_file():
            text = entry.read_text()
            if text.count("format=no") != 1 or "format=only" in text:
                add(f"{item['id']}: runtime template must contain exactly one format=no and no format=only")
            declared_hd = sorted({int(x) for x in re.findall(r"^hd=hd(\d+),", text, re.MULTILINE)})
            declared = list(range(1, item["clients"] + 1))
            if declared_hd != declared:
                add(f"{item['id']}: declared hosts {declared_hd} != clients {declared}")
            fwd_hosts = sorted({int(x) for x in re.findall(r"host=hd(\d+)", text)})
            if item["id"] in {"w08", "w09", "w13"}:
                if fwd_hosts:
                    add(f"{item['id']}: expected default FWD distribution, found {fwd_hosts}")
            elif fwd_hosts != declared:
                add(f"{item['id']}: FWD hosts {fwd_hosts} != declared clients {declared}")

        if item["id"] == "w14":
            text = "\n".join((ROOT / p).read_text() for p in item["entries"])
            if "formatsds=no" not in text:
                add("w14: indexed templates must retain formatsds=no")
            hosts = sorted({int(x) for x in re.findall(r"host=h(\d+)", text)})
            if hosts != list(range(1, 17)):
                add(f"w14: SD hosts {hosts} != h1-h16")

        if item["id"] in {"w11", "w12"}:
            script = entry.read_text()
            if "M=64" not in script or "guard_run_paths" not in script or "out_path=" not in script:
                add(f"{item['id']}: missing 64-rank or guarded output-directory declaration")
            if "validate_hostfile" not in script:
                add(f"{item['id']}: missing hostfile validation")
            if item["id"] == "w12" and "wait \"$" not in script:
                add("w12: missing explicit background-job checks")
            hostfile = item.get("hostfile_example")
            if not hostfile or not (ROOT / hostfile).is_file():
                add(f"{item['id']}: missing hostfile example")
            elif item["id"] == "w11":
                lines = [line.split() for line in (ROOT / hostfile).read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")]
                names = [line[0] for line in lines if line]
                if len(lines) != 16 or len(set(names)) != 16 or any(len(line) != 2 or line[1] != "slots=4" for line in lines):
                    add("w11: hostfile example must contain 16 entries with slots=4")


def validate_trace_and_csv() -> None:
    required = {"phase_id", "workload_id", "profile", "start_day", "end_day", "duration_days", "repeat_of"}
    if trace.get("workload_mapping", {}).get("catalog") != "catalog.json":
        add("trace: workload_mapping.catalog must point to catalog.json")
    if "operation_policy" in trace:
        add("trace: tuning operation policy must not be published")
    deployment_mapping = trace.get("deployment_mapping", {})
    expected_rows: list[dict] = []

    for tr in trace["traces"]:
        trace_id = tr["id"]
        deployment_id = deployment_mapping.get(trace_id)
        if not deployment_id:
            add(f"missing deployment mapping for {trace_id}")
        if tr.get("deployment_id") != deployment_id:
            add(f"{trace_id}: deployment_id does not match deployment_mapping")
        previous_end = 0.0
        seen: dict[str, dict] = {}
        for phase in tr["phases"]:
            phase_name = f"{trace_id}/{phase.get('phase_id', '?')}"
            if phase.get("phase_id") in seen:
                add(f"{phase_name}: duplicate phase_id")
            missing = required - set(phase)
            if missing:
                add(f"{phase_name}: missing {sorted(missing)}")
                continue
            unexpected = set(phase) - required - {"variant"}
            if unexpected:
                add(f"{phase_name}: unexpected fields {sorted(unexpected)}")
            if any(k in phase for k in ("reaction_time_hours", "tuning_window_hours", "maintenance_window_hours", "coverage_class", "recommendation_policy")):
                add(f"{phase_name}: tuning metadata remains")
            if not math.isclose(phase["start_day"], previous_end, abs_tol=1e-6):
                add(f"{phase_name}: phases are not strictly contiguous")
            if phase["end_day"] <= phase["start_day"]:
                add(f"{phase_name}: end_day must be greater than start_day")
            if not math.isclose(phase["duration_days"], phase["end_day"] - phase["start_day"], abs_tol=1e-6):
                add(f"{phase_name}: duration mismatch")

            item = catalog_by_id.get(phase["workload_id"])
            if item is None:
                add(f"{phase_name}: unknown workload_id {phase['workload_id']}")
            else:
                if not item_matches_phase(item, phase):
                    add(f"{phase_name}: profile does not match catalog entry")
                variant = phase.get("variant")
                if variant is not None and variant not in item.get("variants", []):
                    add(f"{phase_name}: variant {variant} is not listed for {item['id']}")
                elif variant is not None:
                    mapped = item.get("variant_entries", {}).get(variant, "").split()[0]
                    if mapped and not (ROOT / mapped).is_file():
                        add(f"{phase_name}: variant entry is missing: {mapped}")
                    elif mapped:
                        mapped_relative = Path(mapped).relative_to("workloads").as_posix()
                        mapped_aliases = {mapped_relative, Path(mapped_relative).parent.as_posix()}
                        if phase["profile"] not in mapped_aliases:
                            add(f"{phase_name}: profile does not match variant entry {mapped}")

            repeat_of = phase["repeat_of"]
            if repeat_of is not None:
                earlier = seen.get(repeat_of)
                if earlier is None:
                    add(f"{phase_name}: repeat_of must reference an earlier phase")
                elif (earlier["workload_id"], earlier.get("variant")) != (phase["workload_id"], phase.get("variant")):
                    add(f"{phase_name}: repeat_of workload and variant do not match")

            seen[phase["phase_id"]] = phase
            previous_end = phase["end_day"]
            expected_rows.append({
                "trace": trace_id,
                "deployment_id": deployment_id,
                "phase_id": phase["phase_id"],
                "workload_id": phase["workload_id"],
                "profile": phase["profile"],
                "variant": phase.get("variant", ""),
                "start_day": phase["start_day"],
                "end_day": phase["end_day"],
                "duration_days": phase["duration_days"],
                "repeat_of": phase["repeat_of"] or "",
            })
        if not math.isclose(previous_end, 30.0, abs_tol=1e-6):
            add(f"{trace_id}: end day {previous_end} != 30")

    csv_path = ROOT / "trace/30day_trace.csv"
    try:
        with csv_path.open(newline="") as handle:
            actual_rows = list(csv.DictReader(handle))
    except OSError as exc:
        add(f"trace CSV cannot be read: {exc}")
        return
    fields = ["trace", "deployment_id", "phase_id", "workload_id", "profile", "variant", "start_day", "end_day", "duration_days", "repeat_of"]
    if actual_rows and list(actual_rows[0]) != fields:
        add(f"trace CSV header mismatch: {list(actual_rows[0])}")
    if len(actual_rows) != len(expected_rows):
        add(f"trace CSV row count {len(actual_rows)} != JSON row count {len(expected_rows)}")
    for index, (expected, actual) in enumerate(zip(expected_rows, actual_rows), start=1):
        for field in fields:
            if field in {"start_day", "end_day", "duration_days"}:
                try:
                    if not math.isclose(float(actual[field]), float(expected[field]), abs_tol=1e-6):
                        add(f"trace CSV row {index}: {field} mismatch")
                except (KeyError, ValueError):
                    add(f"trace CSV row {index}: invalid {field}")
            elif actual.get(field, "") != str(expected[field]):
                add(f"trace CSV row {index}: {field} mismatch")


def validate_checksums() -> None:
    checksum_path = ROOT / "PUBLIC_SHA256SUMS"
    if not checksum_path.is_file():
        add("PUBLIC_SHA256SUMS is missing")
        return
    expected: dict[str, str] = {}
    for line_number, line in enumerate(checksum_path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            digest, relative = line.split("  ", 1)
        except ValueError:
            add(f"PUBLIC_SHA256SUMS line {line_number}: invalid format")
            continue
        expected[relative] = digest

    actual: dict[str, str] = {}
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts or path.name in {"PUBLIC_SHA256SUMS", ".gitignore"} or "__pycache__" in path.parts:
            continue
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        relative = "./" + path.relative_to(ROOT).as_posix()
        actual[relative] = digest.hexdigest()

    if set(expected) != set(actual):
        add(f"PUBLIC_SHA256SUMS file set mismatch: missing={sorted(set(actual) - set(expected))}, extra={sorted(set(expected) - set(actual))}")
    for relative, digest in actual.items():
        if expected.get(relative) != digest:
            add(f"PUBLIC_SHA256SUMS mismatch: {relative}")


validate_catalog()
validate_trace_and_csv()
validate_checksums()
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"validated {len(cat['workloads'])} catalog entries and {sum(len(t['phases']) for t in trace['traces'])} phases")
print("validated JSON/CSV identity, contiguous phases, repeat links, catalog variants, host mappings, and IOR hostfiles")
