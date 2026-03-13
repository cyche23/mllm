# 验收规则

## 权威范围

本文件是任务是否可交付的唯一判定标准。测试怎么做看 [TEST_RULES.md](./TEST_RULES.md)，交付如何写看 [HANDOFF_TEMPLATE.md](./HANDOFF_TEMPLATE.md)。

## 验收总原则

1. 验收以证据为准，不以主观判断为准。
2. 当前阶段优先验收“平台可用性、度量可用性、主路径稳定性”。
3. 没有通过条件就不能宣称完成；没有测试记录就不能进入通过判断。
4. 任何会改变默认行为的实现，在当前阶段默认不通过，除非 planner 明确批准。

## 平台术语约定

- 对核心 restore 路径任务，`host` 默认指 `target device host`，即 target device 上的 `arm64 CPU` 宿主侧。
- `x86 dev host` / `desktop host` / `host-side scaffold` 仅指 desktop / x86 Linux 开发机环境。
- 若任务目标本身是 target-device 核心路径，`x86 dev host` 证据只能证明脚手架可运行，不能单独作为通过依据。

## 必须满足的基础条件

所有任务在进入 `Done` 前必须同时满足：

| 条件 | 要求 |
| --- | --- |
| 任务对齐 | 与 [TASK_BOARD.md](./TASK_BOARD.md) 中的 Task ID、Deliverable、Pass Condition 一致 |
| 改动边界 | 未无故扩大为主路径重构或无关优化 |
| 默认关闭 | 实验逻辑默认关闭，开启方式明确 |
| 测试证据 | 至少附 1 份可复现测试记录 |
| 回滚能力 | 能说明回滚点、开关关闭方式或最小撤销范围 |
| 结构化 handoff | 使用 [HANDOFF_TEMPLATE.md](./HANDOFF_TEMPLATE.md) 或等价结构 |

## 各类任务通过条件

### 基建类任务

适用：benchmark 框架、统一参数、日志规范。

通过条件：

- 能独立运行，不依赖手工修改源码常量。
- 运行方式写清楚，至少有一条成功记录。
- 不改变主路径默认行为。

### profiling 类任务

适用：flash/device-host、QNN staging、hidden reprojection、token recompute、CPU relayout。

通过条件：

- 阶段命名稳定且可复用。
- 至少有一次有效耗时输出。
- 日志字段满足测试规则。
- 能说明该 profiling 结果将支持哪一个后续决策。
- 若任务针对 target-device 核心路径，结果必须来自 `target device host` 或有 planner 明确批准的阶段性例外。

### 端到端 benchmark 类任务

适用：restore microbenchmark。

通过条件：

- 能输出总耗时与关键分阶段耗时。
- 能说明输入条件，如模型、context 长度、token 数、设备。
- 至少完成一次基线记录；若有对比，需标明对比对象和条件。

### feasibility 类任务

适用：decode-friendly layout、async submission。

通过条件：

- 结论必须基于已有 profiling 或 benchmark 证据。
- 明确收益假设、侵入范围、风险和回滚路径。
- 不直接把 feasibility 讨论包装成已落地优化。

## 直接退回条件

出现以下任一情况，任务直接退回：

- 修改主路径但没有明确隔离开关。
- 无测试记录、无日志证据、无运行命令。
- 交付物与 `TASK_BOARD` 描述不一致。
- 把异步流水作为首轮方案，跳过 profiling 与同步基线。
- 一个提交混入多类无关改动，难以回滚。
- 用 `x86 dev host` 结果宣称 target-device 核心路径任务完成。

## 需要 planner 决策的情况

以下情况不得由 coder 或 tester 自行拍板：

| 情况 | 需要决策内容 |
| --- | --- |
| 必须改默认推理路径才能继续 | 是否允许扩大范围 |
| 实验收益不明确但侵入性较高 | 是否继续投入 |
| 真机依赖导致无法及时复现 | 是否接受阶段性的 `x86 dev host` scaffold 证据 |
| profiling 结果互相矛盾 | 是否先补测还是调整任务拆分 |
| async 方案需要新增线程或队列模型 | 是否进入设计评审 |
