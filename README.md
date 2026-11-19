# Trace-of-FiTune: Public Workload Suite

[English](README.md) | [中文](README.zh-CN.md)

This repository provides workload definitions and an anonymized 30-day workload sequence. The workload phases were reconstructed from the trace used in our FiTune experiments, with application labels mapped to neutral workload IDs (`w01`--`w14`) so that workload shapes and phase relationships can be reproduced on an independently configured testbed.

Native templates use placeholders such as `@HOST01@`, `@DATA@`, and `@VDBENCH@`. Fill these values locally before running a workload.

## Contents

- `workloads/`: 14 workload families using Vdbench, fio, and IOR/MPI templates.
- `catalog.json`: neutral workload IDs, patterns, client counts, and entry points.
- `trace/30day_trace.json`: two anonymized 30-day workload sequences with phase boundaries and repeat relationships.
- `trace/30day_trace.csv`: the same sequence in a flat format.
- `PUBLIC_SHA256SUMS`: SHA-256 checksums for the release files.

The sequence records workload IDs, public template paths, timing, repeat relationships, and coverage conditions.

## Reproduction

Install the upstream tools and prepare datasets locally. Expand the placeholders for the selected testbed, then record tool versions, client count, data layout, cache state, warmup, measurement window, and result hashes for each run.
