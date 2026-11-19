# Trace-of-FiTune: Public Workload Suite

## English

This repository provides workload definitions and an anonymized 30-day workload sequence. The workload phases were reconstructed from the trace used in our FiTune experiments, with application labels mapped to neutral workload IDs (`w01`--`w14`) so that workload shapes and phase relationships can be reproduced on an independently configured testbed.

Native templates use placeholders such as `@HOST01@`, `@DATA@`, and `@VDBENCH@`. Fill these values locally before running a workload.

### Contents

- `workloads/`: 14 workload families using Vdbench, fio, and IOR/MPI templates.
- `catalog.json`: neutral workload IDs, patterns, client counts, and entry points.
- `trace/30day_trace.json`: two anonymized 30-day workload sequences with phase boundaries and repeat relationships.
- `trace/30day_trace.csv`: the same sequence in a flat format.
- `PUBLIC_SHA256SUMS`: SHA-256 checksums for the release files.

The sequence records workload IDs, public template paths, timing, repeat relationships, and coverage conditions.

### Reproduction

Install the upstream tools and prepare datasets locally. Expand the placeholders for the selected testbed, then record tool versions, client count, data layout, cache state, warmup, measurement window, and result hashes for each run.

## 中文

本仓库提供工作负载定义和匿名的 30 天工作负载序列。工作负载阶段根据论文 FiTune 实验中使用的 Trace 复现，并将应用标签映射为中性的工作负载编号（`w01`--`w14`），便于在独立配置的测试环境中复现工作负载形态和阶段关系。

原生模板使用 `@HOST01@`、`@DATA@` 和 `@VDBENCH@` 等占位符，运行前请在本地填写。

### 目录内容

- `workloads/`：14 类使用 Vdbench、fio 和 IOR/MPI 的工作负载模板。
- `catalog.json`：中性工作负载编号、模式、客户端数量和入口文件。
- `trace/30day_trace.json`：两个匿名的 30 天工作负载序列，包含阶段边界和重复关系。
- `trace/30day_trace.csv`：相同序列的扁平格式。
- `PUBLIC_SHA256SUMS`：发布文件的 SHA-256 校验值。

序列记录工作负载编号、公开模板路径、时间信息、重复关系和覆盖条件。

### 复现

请在本地安装上游工具并准备数据集，在选定的测试环境中展开占位符，然后记录工具版本、客户端数量、数据布局、缓存状态、预热时间、测量窗口和每次运行的结果哈希。
