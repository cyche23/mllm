# 测试规则

## 权威范围

本文件是测试设计、日志字段、结果记录和回归要求的唯一权威来源。是否通过交付，请看 [ACCEPTANCE_RULES.md](./ACCEPTANCE_RULES.md)。

## 测试总原则

1. 无测试证据不算完成。
2. 当前阶段优先验证“可运行、可复现、可比较”，再追求大规模覆盖。
3. 任何实验任务都至少要证明两件事：
   - 实验入口按预期工作
   - 主路径默认行为未被破坏
4. profiling 数据必须可重复收集，且口径一致。
5. 真机测试很重要，但若依赖设备环境，必须保留 `x86 dev host` 侧最小验证链路。

## 平台命名要求

- 记录核心 restore 路径结果时，`host` 默认指 `target device host`，即 target device 上的 `arm64 CPU` 宿主侧。
- 若结果来自 desktop / x86 Linux 开发机，必须显式写为 `x86 dev host`、`desktop host` 或 `host-side scaffold`。
- `x86 dev host` 侧结果不能直接作为 QNN staging、CPU/NPU 协作、cache materialization 等 target-device 核心路径任务的完成证据。

## 测试分类

| 分类 | 目标 | 最低要求 |
| --- | --- | --- |
| Smoke Test | 验证程序能启动、参数能解析、开关有效 | 至少 1 次成功运行记录 |
| Functional Test | 验证功能路径按预期执行 | 输出结果、关键阶段或文件产物符合预期 |
| Profiling Test | 验证计时点与日志字段有效 | 能输出分阶段耗时，字段完整 |
| Regression Test | 验证默认路径未退化 | 实验关闭时结果与原有行为一致或差异可解释 |
| Device Validation | 验证 Android/QNN 真机链路 | 记录设备、构建方式、运行命令和结果 |

## 真机环境准备

- 涉及 `Device Validation`、QNN AOT 构建、Android 部署脚本时，先阅读并使用 [LOCAL_ENV.md](./LOCAL_ENV.md)。
- 若测试依赖当前服务器预置环境，测试记录中的 `Environment` 或 `Command` 必须能看出已激活对应工具链和 Python 环境。
- 若仅完成 `x86 dev host` 侧验证，需在记录中明确写明“仅完成 host-side scaffold，未进入 target device 验证”。

## 日志字段要求

以下字段用于测试记录与结果对比，新增任务原则上应覆盖：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `task_id` | 是 | 当前任务编号 |
| `test_case` | 是 | 测试名称 |
| `run_id` | 是 | 单次运行标识 |
| `date` | 是 | 执行日期 |
| `commit` | 是 | 对应提交或工作区说明 |
| `device` | 是 | `x86 dev host` / Android 设备名 / `target device host` 等 |
| `build` | 是 | Debug/Release/RelWithDebInfo 等 |
| `command` | 是 | 实际运行命令 |
| `flags` | 是 | 显式开启的实验开关 |
| `stage` | 条件必填 | 有 profiling 时填写阶段名 |
| `latency_ms` | 条件必填 | 有 profiling 时填写耗时 |
| `result` | 是 | Pass/Fail |
| `artifact` | 否 | 日志文件、截图、结果文件路径 |

## 测试结果记录格式

每个任务至少保留一份结构化测试记录，推荐直接写入 handoff：

| Field | 内容要求 |
| --- | --- |
| Task ID | 与任务板一致 |
| Test Type | Smoke / Functional / Profiling / Regression / Device Validation |
| Environment | 主机或设备、系统、构建方式 |
| Command | 可直接复现的命令 |
| Input | 模型、配置、prompt、token 数等 |
| Expected | 预期行为或度量项 |
| Actual | 实际结果 |
| Artifact | 日志或结果文件位置 |
| Verdict | Pass / Fail |

## 回归测试要求

### 必做回归

- 实验逻辑关闭时，主路径应至少完成一次 smoke 或已有对应测试。
- 若修改了 `mllm/backends/qnn/`、`examples/` 公共入口或公共参数解析，必须补一条明确回归记录。
- 若新增 profiling 开关，需验证关闭该开关时不会额外输出噪声日志或改变默认行为。
- 若执行了真机验证，需在 handoff 中补充 `Required Env`，并引用 [LOCAL_ENV.md](./LOCAL_ENV.md)。
- 若任务目标属于 target-device 核心路径，只有 `x86 dev host` 结果时不得标记为完成。

### 回归失败处理

- 回归失败不得标记任务完成。
- 可接受已知问题，但必须在 handoff 中标为 `Risk / Limitation`，并由 planner 明确是否拆成阻塞项。
