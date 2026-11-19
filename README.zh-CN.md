# Trace-of-FiTune：公开工作负载套件

[English](README.md) | [中文](README.zh-CN.md)

本仓库提供从两个 30 天真实部署中复现的、按阶段组织的匿名工作负载模板和工作负载序列。内容保留工作负载模式、阶段边界和重复关系，同时排除原始 I/O 请求及敏感生产遥测数据。

这些工作负载阶段根据论文 FiTune 实验中使用的 Trace 复现，并将应用标签映射为中性的工作负载编号（`w01`--`w14`）。仓库发布的是用于表示两个部署的匿名工作负载序列和模板。原生模板使用 `@HOST01@`、`@DATA@` 和 `@VDBENCH@` 等占位符，运行前请在本地填写。

## 目录内容

- `workloads/`：14 类使用 Vdbench、fio 和 IOR/MPI 的工作负载模板。
- `catalog.json`：工作负载编号、模式、客户端映射、具体入口文件和变体。
- `trace/30day_trace.json`：`trace_a`/`deployment_a` 与 `trace_b`/`deployment_b` 的阶段序列。
- `trace/30day_trace.csv`：相同阶段序列的扁平格式。
- `scripts/prepare_data.sh`：为全部工作负载准备数据目录和文件树。
- `scripts/check_placeholders.py`：占位符清单和校验脚本。
- `scripts/validate_release.py`：目录、Trace、持续时间和客户端映射校验脚本。
- `tool_versions.json`：参考工具版本和运行命令。
- `PUBLIC_SHA256SUMS`：发布文件的 SHA-256 校验值。
- `LICENSE`：仓库模板和脚本使用 MIT 许可证。

## 阶段级工作负载序列

两个匿名部署标签与 30 天 Trace 的对应关系如下：

| Trace | 匿名部署标签 | 持续时间 |
|:--|:--|--:|
| `trace_a` | `deployment_a` | 30 天 |
| `trace_b` | `deployment_b` | 30 天 |

每个阶段记录 `workload_id`、公开模板路径、可选变体、`start_day`、`end_day`、`duration_days` 和 `repeat_of`。阶段持续时间表示工作负载序列中的运行区间，本仓库不再记录调优窗口和反应时间字段。

## 工作负载数据准备

所有 Vdbench 运行入口使用 `format=no`，因此运行前必须准备对应文件树。准备脚本会创建模板中使用的目录锚点、目录深度、文件数量和逻辑大小；数据初始化与运行时工作负载分开执行。

```bash
python3 scripts/validate_release.py
python3 scripts/check_placeholders.py
scripts/prepare_data.sh --root /mnt/test-data --profile w01,w02 --mode allocate
```

`--mode sparse` 创建逻辑大小正确的稀疏文件，读取时返回确定性的零值并尽量减少物理空间占用；`--mode allocate` 使用 `fallocate` 预留请求的文件空间；`--mode zero` 向请求的范围写入零值。需要物理预填充时使用 `allocate` 或 `zero`。对于文件数量很大的负载，可用 `--max-files` 创建受限的冒烟测试数据。

| 编号 | 准备要求 | 逻辑容量或结构 |
|:--:|---|---:|
| `w01`--`w04` | 在 `standard-large` 下创建 1,024 个 1 GiB 文件 | 1 TiB |
| `w05`--`w06` | 创建 `depth=1`、`width=10000`、`files=1000` 的 `smallfile`，每个文件 4 KiB | 1,000 万个文件，逻辑 40 GB |
| `w07` | 创建 100 个 anchor，每个 anchor 100,000 个文件的 `mixed400k` | 1,000 万个文件，逻辑 4.096 TB |
| `w08` | 在 `mixed-ops` 下创建 8 个 depth-4、width-5 树，并使用模板中的大小分布 | 操作率混合文件树 |
| `w09` | 在 `mixed-bandwidth` 下创建 8 个 depth-4、width-5 树，并使用模板中的大小分布 | 带宽混合文件树 |
| `w10` | 在四个 fio 作业运行前创建 `fio/testfile1` | 109,949,485,056 字节 |
| `w11` | 创建 `checkpoint-short`，运行脚本会创建输出根目录 | IOR 输出和检查点文件 |
| `w12` | 创建 `checkpoint-long`，运行脚本会创建输出根目录 | 三组输出与检查点阶段 |
| `w13` | 创建 depth-4、width-6 树，每个叶节点 10 个文件，并使用模板大小分布 | 12,960 个文件，逻辑约 1.46 TiB |
| `w14` | 创建 `indexed/edge-records` 和 `indexed/vertex-records` | 6.25 TiB 和 51 GiB |

读负载（`w02`、`w04`、`w06`、`w10` 以及 `w13`/`w14` 的读变体）使用上述步骤准备的文件。需要固定文件命名空间时，写负载也可以复用同一文件树。

## 占位符和客户端映射

| 占位符 | 含义 | 使用位置 |
|:--|:--|:--|
| `@HOST01@`--`@HOST16@` | 客户端主机名或地址 | Vdbench 负载 |
| `@USER@` | 远程执行用户 | Vdbench 负载 |
| `@DATA@` | 数据根目录 | 全部负载 |
| `@VDBENCH@` | Vdbench 5.04.06 可执行文件或包装器 | w01--w09、w13 |
| `@VDBENCH_INDEXED@` | 索引负载使用的 Vdbench 可执行文件或包装器 | w14 |
| `@HOSTS64@` | MPI 主机文件路径 | w11--w12 |
| `@IOR@` | IOR 4.0.0 可执行文件 | w11--w12 |
| `@MPIRUN@` | MPI 启动器 | w11--w12 |

8 客户端负载声明 `hd1`--`hd8`，并将一个 FWD 显式分配到每台主机。`w07` 声明 `hd1`--`hd16`，并将一个 FWD 显式分配到每台主机。`w08`、`w09` 和 `w13` 声明 `hd1`--`hd16`，但不设置 FWD 的 `host` 字段，因此由 Vdbench 在声明的主机集合上执行默认分布；校验脚本会检查主机声明以及没有冲突的显式分配。`w14` 使用 `h1`--`h16`，每个 `sdN` 分配到 `hN`，并使用不重叠的数据范围。IOR 负载使用 16 个客户端上的 64 个 rank，每客户端 4 个 rank，由 `@HOSTS64@` 表示。

## 工具版本和运行依赖

`tool_versions.json` 记录参考版本矩阵：Vdbench 5.04.06、fio 3.36 和 IOR 4.0.0。运行 IOR 负载前请固定 MPI 实现并记录 `mpirun --version` 输出；启动器和主机文件语法需要支持 `mpirun -f`。Vdbench 需要 Java 8 或更新版本。检查点脚本依赖 Bash、`bc`、GNU `tail`、`grep`、`awk`、`expr` 和标准目录/文件工具。

## 复现

安装固定版本的工具，准备选定的工作负载数据，替换占位符，并运行 `catalog.json` 中列出的入口文件。请将生成的日志和测量输出与对应运行记录放在一起，同时保存工具版本输出和输入模板的 SHA-256 值。
