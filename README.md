# Trace-of-FiTune: Public Workload Suite

## English

This repository releases only workload definitions and an anonymized 30-day workload sequence. We reconstructed these workload phases from the trace used in our FiTune experiments, then replaced application labels with neutral workload IDs (`w01`--`w14`). The release is intended to make workload shapes and phase relationships reproducible; it is not a release of the tested system or deployment environment.

The repository contains no organization, site, product, cluster, machine model, host name, IP address, credential, AI model, raw production trace, dataset, system configuration, throughput, latency, baseline, or tuning-result identifier. Native templates use placeholders such as `@HOST01@`, `@DATA@`, and `@VDBENCH@`; fill them locally for an independently configured testbed.

### Contents

- `workloads/`: 14 workload families using Vdbench, fio, and IOR/MPI templates.
- `catalog.json`: neutral workload IDs, patterns, client counts, and entry points.
- `trace/30day_trace.json`: two anonymized 30-day workload sequences with phase boundaries and repeat relationships.
- `trace/30day_trace.csv`: the same sequence in a flat format.
- `PUBLIC_SHA256SUMS`: SHA-256 checksums for all release files.

The sequence contains only workload IDs, public template paths, timing, repeat relationships, and coverage conditions. It does not execute a benchmark and contains no measured performance values.

### Reproduction boundary

Install the upstream tools and prepare datasets separately. Replace the placeholders locally, record tool versions, client count, data layout, cache state, warmup, measurement window, and result hashes, and keep any resulting logs outside this release. A completed template expansion is not a benchmark result.

## 中文

本仓库只公开工作负载定义和匿名的 30 天工作负载序列。我们根据论文 FiTune 实验中使用的 Trace 复现了这些工作负载阶段，并将应用标签替换为中性的工作负载编号（`w01`--`w14`）。该仓库用于复现工作负载形态和阶段关系，不公开被测系统或部署环境。

仓库中不包含组织名称、场地名称、产品名称、集群名称、机器型号、主机名、IP 地址、凭据、AI 模型、原始生产 Trace、数据集、系统配置、吞吐、延迟、基线或调优结果标识。原生模板只使用 `@HOST01@`、`@DATA@` 和 `@VDBENCH@` 等占位符，请在独立配置的测试环境中本地填写。

### 目录内容

- `workloads/`：14 类使用 Vdbench、fio 和 IOR/MPI 的工作负载模板。
- `catalog.json`：中性工作负载编号、模式、客户端数量和入口文件。
- `trace/30day_trace.json`：两个匿名的 30 天工作负载序列，包含阶段边界和重复关系。
- `trace/30day_trace.csv`：相同序列的扁平格式。
- `PUBLIC_SHA256SUMS`：所有发布文件的 SHA-256 校验值。

序列只包含工作负载编号、公开模板路径、时间信息、重复关系和覆盖条件，不执行基准测试，也不包含任何测得的性能数值。

### 复现边界

请在本地单独安装上游工具并准备数据集，在独立测试环境中替换占位符，同时记录工具版本、客户端数量、数据布局、缓存状态、预热时间、测量窗口和结果哈希。模板展开完成不等于已经得到基准测试结果。

### Disclosure audit / 敏感信息审核

Reviewed on 2026-11-19. The released files were scanned for organization, site, product, machine, host, network, credential, private-path, AI-model, and performance-result identifiers; none were found. The only host and tool references are neutral execution placeholders or public dependency names. / 审核日期：2026-11-19。已扫描组织、场地、产品、机器、主机、网络、凭据、私有路径、AI 模型和性能结果标识，发布文件中未发现上述敏感名称；其中主机和工具相关内容仅为通用执行占位符或公开依赖名称。
