# MLLM Restore Benchmark

`mllm-restore-benchmark` 是面向 `context restore benchmarking` 的独立最小入口。

当前 T001 只提供 host 侧 scaffold：

- 显式选择 `scenario` 和 `backend`
- 独立构建、独立运行
- 输出单行 JSON baseline 结果
- 不修改原始 `mllm` 推理主路径，也不改变现有 benchmark/example 行为

## Build

在仓库根目录执行：

```bash
mkdir -p build
cmake -S . -B build
cmake --build build --target mllm-restore-benchmark
```

当前仓库依赖要求 `cmake >= 3.25`。

## Usage

列出当前支持的场景和后端：

```bash
./build/bin/mllm-restore-benchmark --list
```

运行最小 baseline/scaffold：

```bash
./build/bin/mllm-restore-benchmark \
  --scenario direct-kv-scaffold \
  --backend host-sim \
  --payload-bytes 4096 \
  --iterations 2 \
  --touch-stride 64
```

示例输出：

```json
{"task_id":"T001","run_id":"1760000000000000","scenario":"direct-kv-scaffold","backend":"host-sim","stage":"restore_scaffold_total","latency_ms":0.012,"payload_bytes":4096,"iterations":2,"touch_stride":64,"bytes_copied":8192,"checksum":123456789,"result":"ok"}
```

## Notes

- `direct-kv-scaffold` 目前是 host-only 的 synthetic restore baseline，不依赖 QNN 设备环境。
- 该工具实现为独立可执行程序，不进入原始 `mllm` 推理默认执行流。
- 完整参数统一、阶段字段扩展和多场景矩阵留给后续 T002/T003。
