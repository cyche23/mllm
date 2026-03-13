# 统一交付模板

以下模板用于 coder / tester / auditor 之间交接。除非已有更严格的上层要求，否则交付时按此结构填写。

## 模板

```md
# Task Information

- Task ID:
- Task Name:
- Owner:
- Status:
- Related Commit / Branch:

# What Changed

- 改动范围:
- 新增入口/脚本/配置:
- 默认关闭的实验开关:
- 未改动但已确认不受影响的主路径:

# How to Run

- Build:
- Command:
- Required Env:
- Platform Scope:
- Input / Model / Config:

# Test Result

| Test Type | Environment | Command | Expected | Actual | Artifact | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | Pass/Fail |

# Risk / Limitation

- 已知风险:
- 未覆盖场景:
- 需要额外设备或依赖:

# Rollback Point

- 回滚方式:
- 关闭实验逻辑方式:
- 最小撤销范围:

# Next Suggested Step

- 建议下一步 1:
- 建议下一步 2:
```

## 填写要求

- `Task Information` 必须与 [TASK_BOARD.md](./TASK_BOARD.md) 一致。
- `What Changed` 只写实际改动，不写计划中的内容。
- `How to Run` 必须可复现，不省略环境变量和输入条件。
- `Platform Scope` 必须明确写明结果适用于 `target device host`、`x86 dev host` 或 `host-side scaffold`，不得只写含糊的 `host`。
- 若涉及 QNN / Android 真机实验，在 `Required Env` 中明确写明已使用 [LOCAL_ENV.md](./LOCAL_ENV.md) 及任何额外环境差异。
- `Test Result` 至少填写一条真实执行记录。
- `Risk / Limitation` 不得留空；没有明显风险时写“未发现新增风险，仍缺少 xx 验证”。
- `Rollback Point` 必须能指导他人快速撤回或关闭实验逻辑。
- `Next Suggested Step` 只给 1 到 2 条最直接的后续建议，避免发散。
