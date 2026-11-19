# Trace-of-FiTune：公开工作负载套件

[English](README.md) | [中文](README.zh-CN.md)

本仓库提供从两个 30 天真实部署中复现的、按阶段组织的匿名工作负载模板和工作负载序列。内容保留工作负载模式、阶段边界和重复关系，同时排除原始 I/O 请求及敏感生产遥测数据。

这些工作负载阶段根据论文 FiTune 实验中使用的 Trace 复现，并将应用标签映射为中性的工作负载编号（`w01`--`w14`）。原生模板使用 `@HOST01@`、`@DATA@` 和 `@VDBENCH@` 等占位符，运行前请在本地填写。

## 目录内容

- `workloads/`：14 类使用 Vdbench、fio 和 IOR/MPI 的工作负载模板。
- `catalog.json`：工作负载编号、模式、客户端映射、具体入口文件和变体。
- `trace/30day_trace.json`：`trace_a`/`deployment_a` 与 `trace_b`/`deployment_b` 的阶段序列。
- `trace/30day_trace.csv`：相同阶段序列的扁平格式。
- `scripts/prepare_data.sh`：安全的数据准备和原生 Vdbench 格式化入口。
- `scripts/render_vdbench.py`：生成仅格式化的 Vdbench 临时配置。
- `scripts/create_data_file.py`：为 fio 和 `formatsds=no` 负载安全创建确定性的直接文件。
- `scripts/check_placeholders.py`：占位符清单和校验脚本。
- `scripts/validate_release.py`：目录、Trace、持续时间、CSV 和客户端映射校验脚本。
- `tool_versions.json`：参考工具版本和分类后的运行依赖。
- `workloads/11-checkpoint-short/hosts64.example`：16 个客户端、每客户端 4 个 slot 的 MPI 主机文件示例。
- `PUBLIC_SHA256SUMS`：发布文件的 SHA-256 校验值。
- `LICENSE`：仓库模板和脚本使用 MIT 许可证。
- `.github/workflows/validate.yml`：在 push 和 pull request 时自动执行发布校验。

## 阶段级工作负载序列

两个匿名部署标签与 30 天 Trace 的对应关系如下：

| Trace | 匿名部署标签 | 持续时间 |
|:--|:--|--:|
| `trace_a` | `deployment_a` | 30 天 |
| `trace_b` | `deployment_b` | 30 天 |

每个阶段记录 `workload_id`、公开模板路径、可选变体、`start_day`、`end_day`、`duration_days` 和 `repeat_of`。阶段持续时间表示工作负载序列中的运行区间，本仓库不再记录调优窗口和反应时间字段。

## 工作负载数据准备

所有 Vdbench 运行入口使用 `format=no`，因此已有文件树必须与 FSD 定义匹配。准备脚本不会自行发明 Vdbench 文件名或目录。对于 `w01`--`w09` 和 `w13`，脚本会渲染仅用于格式化的配置，依次执行 `format=(clean,only)` 和 `format=(restart,only)` 两个阶段，并调用 Vdbench 5.04.06；由 Vdbench 创建原生的 `vdb*.dir` 和 `vdb_f*.file` 结构，随后再使用原始的 `format=no` 模板进行测量。两个阶段都只执行格式化，不执行测量 RD。

数据根目录必须是专用目录，并由 `.fitune-generated` 标记保护。下面的第一条命令会初始化新目录；已有目录必须为空并显式使用 `--init-root`。只有带有正确标记的根目录才允许使用 `--clean`；直接文件默认拒绝覆盖已有文件和符号链接，必须显式使用 `--force` 才能覆盖普通文件。

准备入口只使用仓库 catalog 中的 Vdbench 模板，不再接受任意的 `--template` 路径。底层渲染器也会在写入格式化配置前，检查所有 `anchor=` 和 `lun=` 路径是否位于带标记的数据根目录下。

Vdbench 报告会写入每个 profile 的独立输出目录。格式化配置默认在运行后删除；排查失败或保留诊断信息时才使用 `--keep-config`。

```bash
# 原生 Vdbench 准备；请替换主机名和可执行文件路径。
scripts/prepare_data.sh --root /mnt/fitune-data --init-root \
  --profile w01 --mode vdbench-format --clean \
  --vdbench /opt/vdbench50406/vdbench \
  --hosts node01,node02,node03,node04,node05,node06,node07,node08 \
  --user bench

# 为 fio 准备确定性的直接文件。
scripts/prepare_data.sh --root /mnt/fitune-data --profile w10 \
  --mode random-prefill

# 只查看操作范围，不创建或删除数据。
scripts/prepare_data.sh --root /mnt/fitune-data --profile w14 \
  --mode random-prefill --dry-run
```

`random-prefill` 使用确定性的 SHAKE-256 派生字节，适合真实读性能测试。`zero` 会写入真实的零值，`sparse` 创建稀疏文件，`allocate` 只预留文件空间，不能保证数据块已经被写入；后三种模式适合冒烟配置或容量检查，不能直接替代读性能测试数据。`--max-files` 只用于直接文件负载的受限冒烟准备，不得用于正式性能实验。脚本要求显式指定 `--profile`，不会隐式准备全部负载。

`w14` 的随机预填充需要向 edge 和 vertex 文件实际写入约 6.30 TiB，可能消耗较长时间和大量空间。执行前请检查可用容量以及目标存储挂载点。

如果一次选择的多个 profile 共用同一棵 FSD 文件树，准备脚本只会格式化一次，并跳过重复的格式化请求。

| 编号 | 准备方式 | 结构或逻辑容量 |
|:--:|---|---:|
| `w01`--`w04` | 使用 `depth=1,width=1,files=1024` 执行 Vdbench `format=only` | 一个原生叶目录，1,024 个 1 GiB 文件 |
| `w05`--`w06` | 使用 `depth=1,width=10000,files=1000` 执行 Vdbench `format=only` | 10,000 个原生叶目录，每个 1,000 个文件 |
| `w07` | 使用 `depth=1,width=100,files=100000` 执行 Vdbench `format=only` | 100 个原生叶目录，每个 100,000 个文件 |
| `w08`--`w09` | 按模板中的深度、宽度和加权大小执行 Vdbench `format=only` | 由 Vdbench 在格式化时应用各大小权重 |
| `w10` | 直接创建 `fio/testfile1` | 109,949,485,056 字节；读测试使用 `random-prefill` |
| `w11`--`w12` | 创建输出根目录 | IOR 负责创建输出和检查点文件 |
| `w13` | 使用 `depth=4,width=6,files=10` 执行 Vdbench `format=only` | 由 Vdbench 应用声明的 3/4/3 大小分布 |
| `w14` | 模板指定 `formatsds=no`，因此直接创建文件 | 6.25 TiB edge 文件和 51 GiB vertex 文件 |

因此，`w08` 和 `w09` 的加权文件大小由 Vdbench 原生格式化过程生成；准备脚本不会循环使用短列表，也不会遗漏 1 GiB 文件类别。

文件数量较大的 `w05`--`w07` 会让 Vdbench 跟踪大量文件和目录元数据，需要较大的 Java 堆。可以将 `JAVA_OPTS="-Xms2g -Xmx8g"` 作为启动配置的示例起点，然后分别测量 Master 和 Client 的内存开销；该数值只是指导，不是已经验证的最优值。请记录首次格式化耗时，以及后续使用 `format=no` 时的启动/目录扫描耗时。在 `shared=yes` 场景下，后续运行仍可能需要扫描目录，不应假设每个主机都有可直接恢复的控制文件。

## 占位符、客户端和主机文件

| 占位符 | 含义 | 使用位置 |
|:--|:--|:--|
| `@HOST01@`--`@HOST16@` | Vdbench 客户端主机名或地址 | Vdbench 负载 |
| `@USER@` | 远程执行用户 | Vdbench 负载 |
| `@DATA@` | 数据根目录 | 全部负载 |
| `@VDBENCH@` | Vdbench 5.04.06 可执行文件或包装器 | w01--w09、w13 |
| `@VDBENCH_INDEXED@` | 索引负载使用的 Vdbench 可执行文件或包装器 | w14 |
| `@HOSTS64@` | MPI 主机文件路径 | w11--w12 |
| `@IOR@` | IOR 4.0.0 可执行文件 | w11--w12 |
| `@MPIRUN@` | MPI 启动器 | w11--w12 |

8 客户端负载声明 `hd1`--`hd8`，并将一个 FWD 显式分配到每台主机。`w07` 声明 `hd1`--`hd16`，并执行相同的一对一分配。`w08`、`w09` 和 `w13` 声明 `hd1`--`hd16`，但不设置 FWD 的 `host` 字段，因此由 Vdbench 在声明的主机集合上执行默认分布。`w14` 使用 `h1`--`h16`，每个 `sdN` 分配到 `hN`，并使用不重叠的数据范围。

运行多客户端 Vdbench 前，请配置从 Master 到所有 Client 的免密 SSH 或等效认证。所有 Client 应使用一致的 Vdbench 安装路径，访问相同的 `@DATA@` 挂载路径，并确保测试用户具有创建、读取、写入和删除测试目录的权限。

IOR 脚本在启动 `-np 64` 前要求主机文件包含 16 个非注释条目，并且每个条目为 `slots=4`。请从 [`hosts64.example`](workloads/11-checkpoint-short/hosts64.example) 开始，替换主机名，并将 `@HOSTS64@` 设置为该文件。长检查点序列会在每个阶段完成后写入退出状态文件，后续阶段只有在前一阶段成功时才会启动；如果阶段失败或被中断，后续阶段和最终带宽汇总都会被阻止，同时父进程仍会收集所有后台阶段的状态。

IOR 变体可以独立执行：`run.sh output` 只运行输出阶段，`run.sh checkpoint` 只运行检查点阶段，`run.sh all` 运行完整序列。每次执行都会校验带标记的数据根目录，拒绝不安全的 `FITUNE_RUN_ID`，并将输出文件和日志写入同一个新的 `checkpoint-*/runs/<run-id>` 目录，具体命令记录在 `catalog.json` 的 `variant_entries` 中。

运行 IOR 脚本前请先准备对应的 `w11` 或 `w12` 目录 profile；运行入口会要求存在子树标记，并拒绝未标记或作为挂载点的 profile 目录。

## 工具版本和运行依赖

`tool_versions.json` 记录参考版本矩阵：Vdbench 5.04.06、fio 3.36 和 IOR 4.0.0。运行 IOR 前请固定 MPI 实现并记录 `mpirun --version`；启动器和主机文件语法需要支持 `mpirun -f`。

| 依赖类别 | 必需组件 |
|:--|:--|
| Python | Python 3，用于发布校验、配置渲染和安全直接文件创建 |
| Shell | Bash 4 或更新版本 |
| GNU Coreutils | `mkdir`、`grep`、`awk`、`tail`、`sha256sum` |
| util-linux / 文件系统工具 | `--mode allocate` 需要文件系统支持 POSIX fallocate；util-linux `fallocate` 为可选工具，原生 Vdbench 格式化不使用 `truncate` |
| 工作负载工具 | Vdbench 5.04.06、fio 3.36、IOR 4.0.0 |
| MPI | 支持 `mpirun -f` 的 Hydra 兼容 MPI 运行时 |
| Java | Vdbench 5.04.06 需要 Java 8 或更新版本 |
| 数值工具 | 长检查点汇总需要 `bc` |

## 复现

先运行发布校验：

```bash
python3 scripts/validate_release.py
python3 scripts/check_placeholders.py
sha256sum -c PUBLIC_SHA256SUMS
```

安装固定版本的工具，使用匹配的模式准备选定工作负载，替换占位符，并运行 `catalog.json` 中列出的具体入口。请将日志和测量输出与对应运行记录放在一起，同时保存工具版本输出和输入模板的 SHA-256 值。
