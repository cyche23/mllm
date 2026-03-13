# 任务板

## 使用说明

- 本文件是当前阶段唯一任务看板。
- 新任务必须补齐全部字段后再开工。
- `Pass Condition` 只写可验证结果，不写主观描述。
- 若任务依赖未满足，不得跳过依赖直接宣称完成。

## 状态定义

| Status | 含义 |
| --- | --- |
| Todo | 未开始 |
| Doing | 进行中 |
| Blocked | 被依赖、环境或方案阻塞 |
| Review | 已提交，待复核 |
| Done | 已满足通过条件 |

## 当前纠偏说明

- `T001` 当前仅完成 `x86 dev host` 上的独立 benchmark scaffold，证明“入口已搭起、主路径未破坏、最小脚手架可运行”。
- `T001` 不代表已进入 `target device host` 上的 `arm64 + QNN + NPU` 核心路径验证。
- 对 context restore 成本模型、QNN staging、CPU/NPU 协作、cache relayout / materialization 等任务，后续 `host` 默认一律解释为 `target device host`。

## 初始任务

| Task ID | Task Name | Owner | Status | Priority | Dependency | Deliverable | Pass Condition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T001 | 独立 restore benchmark 框架 | Planner/Coder | Done | P0 | 无 | 独立 benchmark target/入口、最小运行说明、默认关闭开关 | 可在不改主路径默认行为的情况下独立启动，并输出至少一条基线结果 |
| T013 | arm64 + QNN target-device baseline bring-up | Planner/Coder/Tester | Done | P0 | T001 | `target device host` 上的构建/部署/运行基线、环境记录、最小成功日志 | 能在 `target device host` 上完成至少一次 restore benchmark 入口启动或最小 QNN 相关成功验证，并附真实设备/命令/日志证据 |
| T002 | 统一参数与结构化日志 | Coder | Todo | P0 | T001 | 参数结构、阶段命名约定、日志字段、样例输出 | 同一场景多次运行的关键字段稳定一致，且包含测试规则要求的必填字段 |
| T003 | 基线场景矩阵与样例输入 | Planner/Coder | Todo | P0 | T001,T002 | 三条路径的场景定义、样例配置/输入、复现说明 | direct KV load / hidden restore / token recompute 可在统一输入维度下切换运行，无需手改源码常量 |
| T004 | flash/device-host payload profiling | Coder/Tester | Todo | P0 | T002,T003,T013 | hidden payload / KV payload 的 I/O 计时点、字节量记录、样例日志 | 能分别给出 hidden 与 KV 路径的 payload 大小和 flash/device-host 读取耗时，并附 `target device host` 运行证据 |
| T005 | QNN staging / tensor 注册 profiling | Coder/Tester | Todo | P0 | T002,T003,T013 | staging 阶段 profiling 数据与样例日志 | 能稳定记录 QNN 输入 staging 或 tensor 注册耗时，且日志字段符合统一格式 |
| T006 | CPU relayout / materialization profiling | Coder/Tester | Todo | P0 | T002,T003,T013 | CPU relayout 计时点、结果记录、样例日志 | 能确认 relayout/materialization 是否为显著瓶颈，并给出 `target device host` 原始日志与复现实验命令 |
| T007 | hidden reprojection profiling | Coder/Tester | Todo | P0 | T002,T003,T013 | hidden → KV reprojection 阶段计时与样例日志 | 能输出 hidden reprojection 的独立阶段耗时，并说明输入维度与 backend 条件 |
| T008 | token recompute profiling | Coder/Tester | Todo | P0 | T002,T003,T013 | token → prefill recompute 计时与样例日志 | 能区分 recompute 开销并至少完成一次可重复采样 |
| T009 | 非流水端到端 restore microbenchmark | Coder/Tester | Todo | P1 | T004,T005,T006,T007,T008,T013 | 端到端 restore 基准入口、结果表、三路径对比记录 | 可输出总耗时与关键分阶段耗时，并完成 direct KV load / hidden restore / token recompute 的至少一次同条件对比 |
| T010 | 第一阶段瓶颈归因与下一步建议 | Planner/Auditor | Todo | P1 | T004,T005,T006,T007,T008,T009 | 瓶颈结论、关键证据引用、下一阶段建议 | 能明确指出当前最可能主瓶颈、CPU relayout 是否在关键路径、下一步最值得投入的优化方向 |
| T011 | decode-friendly layout feasibility | Planner/Coder | Todo | P2 | T010 | 可行性结论与原型范围建议 | 结论基于已有 profiling 证据，明确收益假设、侵入范围、风险与回滚路径 |
| T012 | async submission feasibility | Planner/Coder/Auditor | Todo | P2 | T009,T011 | 异步方案评估记录 | 仅在同步基线稳定后进入评估，且不直接改默认执行流 |

## 新任务录入模板

| Task ID | Task Name | Owner | Status | Priority | Dependency | Deliverable | Pass Condition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Txxx | 待填写 | 待填写 | Todo | Px | 待填写 | 待填写 | 待填写 |
