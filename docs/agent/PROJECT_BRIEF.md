# 项目简报

## 项目背景

本项目围绕 `mllm + QNN/NPU` 推理栈，目标是在现有 QNN AOT 与运行时基础上，补齐一套可重复执行的 `context restore` benchmarking 与 profiling 支撑能力。重点不是立即重构主干推理实现，而是先把实验入口、度量口径、日志结构、最小回归链路搭起来，便于后续多 agent 并行推进。

## 当前阶段目标

当前阶段只做最小可行性平台，目标如下：

1. 能独立运行 context restore 相关 microbenchmark 或最小端到端实验。
2. 能对 restore 过程中的关键阶段做 profiling 与日志采集。
3. 能将实验代码与原始推理主路径隔离，默认不影响现有行为。
4. 能为 planner / coder / tester / auditor 提供统一任务、测试、验收和交接框架。

## 术语约定

- 对于本项目的核心 restore 路径，`host` 默认指 target device 上的 `arm64 CPU 宿主侧`，即与 QNN/NPU 同处一个移动 SoC 的 CPU 侧。
- 若指 desktop / x86 Linux 开发机，必须显式写作 `x86 dev host`、`desktop host` 或 `host-side scaffold`。
- `x86 dev host` 侧结果仅可用于脚手架验证、参数联调、格式联调或最小 smoke，不默认代表目标平台成本模型结论。

## 当前非目标

以下事项不属于当前阶段默认目标：

- 直接重写 `mllm` 主推理流程。
- 未经 profiling 证据支持的大范围性能优化。
- 默认开启的实验逻辑或侵入式异步流水改造。
- 一次性解决全部 restore 瓶颈。
- 没有最小复现与回滚点的大改动提交。

## 当前优先级

| 优先级 | 方向 | 说明 |
| --- | --- | --- |
| P0 | benchmark 基础设施 | 先有独立入口、统一参数、统一日志 |
| P0 | profiling 拆分 | 先拆清 flash/device-host、QNN staging、hidden reprojection、token recompute、CPU relayout 等阶段 |
| P1 | end-to-end restore microbenchmark | 在可控输入下得到稳定、可比较的总时延 |
| P1 | 回归保护 | 验证主路径未被破坏，实验默认关闭 |
| P2 | layout / async feasibility | 仅在已有 profiling 证据后再进入可行性分析 |

## 当前约束

- 仓库已存在 `examples/`、`benchmarks/`、`tests/`、`scripts/qnn/` 等入口，优先复用现有工程结构。
- QNN 相关构建涉及 `x86 dev host` AOT 编译与 Android 运行侧，实验设计必须允许“脚手架可验证”和“target device 真机验证”两层执行。
- 若任务需要使用当前服务器已准备好的 Qualcomm / Android 真机环境，以 [LOCAL_ENV.md](./LOCAL_ENV.md) 为准，不在任务说明中重复散落路径。
- 部分工作区可能处于未提交状态，任务执行应避免顺带覆盖无关改动。

## 已知风险

| 风险 | 影响 | 当前策略 |
| --- | --- | --- |
| 实验逻辑侵入主路径 | 可能引入行为回归 | 独立入口、默认关闭、显式开关 |
| profiling 粒度不统一 | 数据不可比较 | 统一日志字段与阶段命名 |
| QNN / 设备环境依赖重 | 复现门槛高 | 先保证 `x86 dev host` 侧脚手架可运行，再补 `target device host` 真机验证 |
| 日志与测试证据缺失 | 无法验收或 handoff | 所有任务必须附测试结果与运行方式 |
| 过早讨论异步流水 | 掩盖真实瓶颈 | 严格执行“先 profiling，后优化，最后异步” |

## 角色使用方式

- planner：以本文件定义目标、非目标和优先级，决定任务排期。
- coder：以本文件限制改动边界，不将实验任务扩展为主路径重构。
- tester：以本文件识别当前阶段必须补齐的证据。
- auditor：以本文件判断交付是否偏离阶段目标。
