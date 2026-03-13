# 项目 Agent 入口

本项目当前目标：在不破坏原始 mllm 推理主路径的前提下，建立面向 `mllm + QNN/NPU + context restore benchmarking` 的最小可行测试与 profiling 平台。

## 进入任务前

必读：
1. [项目简报](docs/agent/PROJECT_BRIEF.md)
2. [任务板](docs/agent/TASK_BOARD.md)

按需阅读：
- 涉及代码改动时看 [编码规则](docs/agent/CODING_RULES.md)
- 涉及测试执行时看 [测试规则](docs/agent/TEST_RULES.md)
- 涉及交付判定时看 [验收规则](docs/agent/ACCEPTANCE_RULES.md)
- 需要结果移交时看 [交付模板](docs/agent/HANDOFF_TEMPLATE.md)
- 涉及 QNN / Android 真机实验时看 [本地环境说明](docs/agent/LOCAL_ENV.md)

## 术语纠偏

- 在本项目中，涉及 context restore 成本模型、QNN staging、CPU/NPU 协作、cache relayout / materialization 等核心路径时，`host` 默认指 target device 上与 QNN/NPU 处于同一 SoC 的 `arm64 CPU 宿主侧`。
- 若指 desktop / x86 Linux 开发机，必须显式写为 `x86 dev host`、`desktop host` 或 `host-side scaffold`，不得直接简写为 `host`。
- 任何任务、测试、handoff 若混用上述概念，视为描述不清，需要先纠偏再继续推进。

## 不可违反的硬规则

- 不得破坏或悄悄改写原始 `mllm` 推理主路径。
- 实验逻辑优先放独立目录、独立入口、独立开关，默认关闭。
- 默认顺序是：先建立 profiling / 可测量性，再做局部优化，最后才讨论异步流水。
- 若基础缺陷阻塞 profiling，可先做最小必要修复，并在 handoff 中说明原因。
- 任何涉及代码实现、实验执行或行为变更的任务，没有测试证据、日志证据或可复现实验记录，都不算完成。
- git 必须小步提交、可回滚；避免大杂烩改动。
- 当前阶段默认开发基线为 `dev/v2-next`，默认稳定基线为 `v2`；`main` / `v1` 不作为当前任务合入目标。

## 冲突裁决优先级

- 若实验实现与主路径稳定冲突，优先主路径稳定。
- 若功能扩展与可测量性闭环冲突，优先可测量性闭环。
- 若长期泛化设计与当前最小可回滚实现冲突，优先最小可回滚实现。

## 当前阶段不主动做

- 不主动重构原始 `mllm` 主执行流。
- 不主动扩大到与 benchmarking 无关的泛化改造。
- 不主动为未来需求预埋大规模抽象层。
- 不在默认配置中启用实验逻辑。

## 不确定时怎么做

- 先查 `TASK_BOARD` 的依赖、交付物和通过条件。
- 若规则冲突，以对应权威文件为准；`AGENTS.md` 不承载细则。
- 若仍不确定，选择“更小改动、更易回滚、默认关闭实验逻辑”的方案，并在 handoff 中明确假设、风险和未验证项。

## 当前阶段完成定义

- 主路径未破坏
- 实验逻辑默认关闭
- 有可复现实验/日志证据
- 改动可回滚
