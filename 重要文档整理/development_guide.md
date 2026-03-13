# QNN 框架持续开发指南（MLLM v2）

> 文档目标：为团队提供可长期维护的 QNN 开发与交付标准流程（含 AOT 与常规 QNN 后端）。  
> 适用仓库：`mllm-v2`（当前工作区）。  
> 最后审查日期：2026-03-05。

---

## 目录

- [1. 架构与执行链路](#1-架构与执行链路)
- [2. 开发环境搭建](#2-开发环境搭建)
- [3. 编译流程（常规 QNN + AOT QNN）](#3-编译流程常规-qnn--aot-qnn)
- [4. 移动端部署与运行](#4-移动端部署与运行)
- [5. 开发规范](#5-开发规范)
- [6. 调试方法与常见问题](#6-调试方法与常见问题)
- [7. 性能分析与优化建议](#7-性能分析与优化建议)
- [8. 版本管理与 CI/CD 指南](#8-版本管理与-cicd-指南)
- [9. 对旧文档的勘误（qnn_framework_development_guide.md）](#9-对旧文档的勘误qnn_framework_development_guidemd)
- [10. 系统性审查与可执行性验证](#10-系统性审查与可执行性验证)
- [11. 参考资料](#11-参考资料)

---

## 1. 架构与执行链路

QNN 在本项目有两条主链路：

1. 常规 QNN 后端（运行时图构建/执行）
2. QNN AOT（x86 主机离线编译 + Android 端加载 context binary）

核心组件（以仓库代码为准）：

- `mllm/backends/qnn/QNNBackend.cpp`：QNN backend 管理入口
- `mllm/backends/qnn/passes/*`：常规图构建与 pattern 降级
- `mllm/backends/qnn/aot/*`：AOT 编译相关（QnnAOTEnv、AOT pipeline）
- `mllm/backends/qnn/aot_rt/*`：设备端 AOT runtime
- `examples/qwen3_qnn_aot/*`：Qwen3 AOT 编译/运行样例

架构示意（项目内已有图，建议团队评审时直接引用）：

![QNN 后端执行序列](docs/_static/img/qnn-trace-execute-seq.png)

技术依据：

- MLLM 官方 QNN 设计文档：`docs/qnn_backend/core_design.rst`
- MLLM 官方 QNN AOT 流程：`docs/qnn_backend/aot_execute.rst`

---

## 2. 开发环境搭建

### 2.1 主机要求

推荐基线：

- Ubuntu 22.04+
- Python 3.10+
- CMake + Ninja
- Android NDK（项目 CI 使用 `r28b`）
- Qualcomm QNN SDK（项目文档与示例默认 `2.41.0.251128`）
- Hexagon SDK（编译 LLaMA OpPackage 必需）

### 2.2 Python 依赖

```bash
pip install -r requirements.txt
pip install -r requirements-qnn-aot.txt
```

### 2.3 SDK 与环境变量（关键）

本仓库实际依赖变量名以 `QAIRT_SDK_ROOT` 为主（CMake 与 OpPackage Makefile 都直接读取该变量）。为兼容旧脚本，可同时导出 `QNN_SDK_ROOT`。

```bash
# QNN SDK
export QAIRT_SDK_ROOT=/opt/qcom/aistack/qairt/2.41.0.251128
export QNN_SDK_ROOT=$QAIRT_SDK_ROOT   # 兼容旧文档/旧脚本
source $QAIRT_SDK_ROOT/bin/envsetup.sh

# Hexagon SDK
export HEXAGON_SDK_ROOT=/opt/qcom/hexagon-sdk/6.x
source $HEXAGON_SDK_ROOT/setup_sdk_env.source

# Android NDK
export ANDROID_NDK_PATH=/opt/ndk/android-ndk-r28b
export ANDROID_NDK_ROOT=$ANDROID_NDK_PATH   # OpPackage Makefile 依赖该变量
```

环境检查：

```bash
test -d "$QAIRT_SDK_ROOT/include/QNN" && echo "QNN include OK"
test -d "$QAIRT_SDK_ROOT/lib/aarch64-android" && echo "QNN android libs OK"
test -d "$HEXAGON_SDK_ROOT" && echo "Hexagon SDK OK"
test -f "$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake" && echo "NDK toolchain OK"
```

### 2.4 OpPackage 编译（QNN offload 必需）

```bash
cd mllm/backends/qnn/custom-op-package/LLaMAPackage
make htp_aarch64
make htp_v75
```

说明：

- `htp_aarch64` 生成 Android 侧 `libQnnLLaMAPackage.so`
- `htp_v75` 生成 Hexagon 侧 `libQnnLLaMAPackage.so`
- Makefile 对 `QAIRT_SDK_ROOT` / `HEXAGON_SDK_ROOT` / `ANDROID_NDK_ROOT` 有硬检查

---

## 3. 编译流程（常规 QNN + AOT QNN）

## 3.1 常规 QNN Android 构建

```bash
python task.py tasks/build_android_qnn.yaml
```

关键 CMake 参数（来自 `tasks/build_android_qnn.yaml`）：

- `-DMLLM_BUILD_QNN_BACKEND=ON`：启用 QNN backend
- `-DMLLM_CROSS_COMPILE=ON` + `android.toolchain.cmake`：交叉编译
- `-DANDROID_ABI=arm64-v8a`，`-DANDROID_PLATFORM=android-28`

## 3.2 AOT 编译器（x86）构建

```bash
python task.py tasks/build_x86_qnn_aot.yaml
```

关键开关：

- `-DMLLM_QUALCOMM_QNN_AOT_ON_X86_ENABLE=ON`

构建后可执行文件（以 Qwen3 为例）：

- `build-qnn-aot/bin/mllm-qwen3-aot-c`
- `build-qnn-aot/bin/mllm-qwen3-aot-sha-c`

## 3.3 AOT 编译执行（生成 context binary）

```bash
./build-qnn-aot/bin/mllm-qwen3-aot-sha-c \
  -m /path/to/qwen3_1.7b.mllm \
  -c ./examples/qwen3_qnn_aot/config_1.7B.json \
  --aot_config ./examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json \
  --qnn_env_path "$QAIRT_SDK_ROOT/lib/x86_64-linux-clang/"
```

输出物：

- `qwen3_qnn_aot_sha_32.mir`
- `qwen3_qnn_aot_sha_1.mir`
- `qwen3-1.7B-lpbq-sha.bin`

参数解释：

- `-m|--model_path`：`.mllm` 模型路径
- `-c|--config`：模型结构配置（如 `config_1.7B.json`）
- `-aot_cfg|--aot_config`：QNN AOT 目标机与量化策略配置
- `-qnn_env|--qnn_env_path`：QNN x86 库目录

## 3.4 模型量化与转换（AOT 前置）

示例（Qwen3）：

```bash
cd pymllm/backends/qualcomm/transformers/qwen3
python train.py \
  --model_path /path/to/hf_model \
  --max_length 1024 \
  --num_samples 128 \
  --output_dir /path/to/output

mllm-convertor \
  --input_path /path/to/output/model.safetensors \
  --output_path /path/to/output/qwen3_1.7b.mllm \
  --verbose
```

## 3.5 qnn_android（非 AOT）标准编译部署流程

该流程用于“运行时构图 + QNN backend 执行”，不依赖 AOT context binary。

### 3.5.1 主机编译

```bash
python task.py tasks/build_android_qnn.yaml
```

该任务会同时执行：

- `HexagonMakeTask`：构建 `LLaMAPackage`（`htp_aarch64` + `htp_v75`）
- `CMakeConfigTask/CMakeBuildTask`：构建 Android QNN 可执行与动态库

### 3.5.2 设备端目录准备

```bash
adb shell "mkdir -p /data/local/tmp/mllm /data/local/tmp/zhanghao/models"
```

说明：`examples/qwen_npu/main.cpp` 当前写死模型路径为 `/data/local/tmp/zhanghao/models/*`，因此需要提前准备该目录并按固定文件名推送模型。

### 3.5.3 推送运行文件

```bash
DEVICE_DIR=/data/local/tmp/mllm

# mllm 产物
adb push build-android-arm64-v8a-qnn/bin/*.so $DEVICE_DIR/
adb push build-android-arm64-v8a-qnn/bin/mllm-qwen-npu $DEVICE_DIR/

# QNN SDK 库
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtp.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpV75Stub.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpPrepare.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnSystem.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/hexagon-v75/unsigned/libQnnHtpV75Skel.so $DEVICE_DIR/

# OpPackage
adb push mllm/backends/qnn/custom-op-package/LLaMAPackage/build/aarch64-android/libQnnLLaMAPackage.so \
  $DEVICE_DIR/libQnnLLaMAPackage_CPU.so
adb push mllm/backends/qnn/custom-op-package/LLaMAPackage/build/hexagon-v75/libQnnLLaMAPackage.so \
  $DEVICE_DIR/libQnnLLaMAPackage_HTP.so

# qwen_npu 配置与 tokenizer
adb push mllm/models/qwen_npu/config_1.8B_w8a16_qnn.json $DEVICE_DIR/config_1.8B_w8a16_qnn.json
adb push /path/to/tokenizer.json $DEVICE_DIR/tokenizer.json
adb push /path/to/qwen_merges.txt $DEVICE_DIR/qwen_merges.txt

# 固定模型文件名（与示例代码保持一致）
adb push /path/to/qwen1.5-1.8b-chat-rot-qnn.mllm /data/local/tmp/zhanghao/models/qwen1.5-1.8b-chat-rot-qnn.mllm
adb push /path/to/qwen1.5-1.8b-chat-rot_q4_0.mllm /data/local/tmp/zhanghao/models/qwen1.5-1.8b-chat-rot_q4_0.mllm
```

### 3.5.4 设备端运行

```bash
adb shell "cd /data/local/tmp/mllm && \
  export LD_LIBRARY_PATH=/data/local/tmp/mllm && \
  ./mllm-qwen-npu"
```

若日志出现 `Decode completed:`，可视为一次非 AOT 端到端推理流程完成。

---

## 4. 移动端部署与运行

统一部署根目录（强制规范）：

`/data/local/tmp/mllm`

不再使用裸目录 `/data/local/tmp` 作为直接落盘目标。

### 4.1 部署目录建议

```text
/data/local/tmp/mllm/
├── qwen3-1.7B-lpbq-sha.bin
├── config_1.7B.json
├── qwen3-tokenizer.json
├── libQnnHtp.so
├── libQnnHtpV75Stub.so
├── libQnnHtpPrepare.so
├── libQnnSystem.so
├── libQnnHtpV75Skel.so
├── libQnnLLaMAPackage_CPU.so
├── libQnnLLaMAPackage_HTP.so
└── mllm-qwen3-aot-runner
```

### 4.2 推送命令模板

```bash
DEVICE_DIR=/data/local/tmp/mllm
adb shell "mkdir -p $DEVICE_DIR"

# 模型与业务文件
adb push qwen3-1.7B-lpbq-sha.bin $DEVICE_DIR/
adb push examples/qwen3_qnn_aot/config_1.7B.json $DEVICE_DIR/
adb push /path/to/qwen3-tokenizer.json $DEVICE_DIR/

# QNN 库
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtp.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpV75Stub.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpPrepare.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/aarch64-android/libQnnSystem.so $DEVICE_DIR/
adb push $QAIRT_SDK_ROOT/lib/hexagon-v75/unsigned/libQnnHtpV75Skel.so $DEVICE_DIR/

# OpPackage（重命名以匹配运行时加载）
adb push mllm/backends/qnn/custom-op-package/LLaMAPackage/build/aarch64-android/libQnnLLaMAPackage.so \
  $DEVICE_DIR/libQnnLLaMAPackage_CPU.so
adb push mllm/backends/qnn/custom-op-package/LLaMAPackage/build/hexagon-v75/libQnnLLaMAPackage.so \
  $DEVICE_DIR/libQnnLLaMAPackage_HTP.so

# Runner
adb push build-android-arm64-v8a-qnn/bin/mllm-qwen3-aot-runner $DEVICE_DIR/
adb push build-android-arm64-v8a-qnn/bin/*.so $DEVICE_DIR/
```

### 4.3 设备端执行

```bash
adb shell "cd /data/local/tmp/mllm && \
  export LD_LIBRARY_PATH=/data/local/tmp/mllm && \
  ./mllm-qwen3-aot-runner \
    -m qwen3-1.7B-lpbq-sha.bin \
    -t qwen3-tokenizer.json \
    -c config_1.7B.json \
    --ar_len 32"
```

### 4.4 AOT 一键端到端脚本

脚本路径：

- `scripts/qnn/run_qnn_aot_android_e2e.sh`

示例：

```bash
scripts/qnn/run_qnn_aot_android_e2e.sh \
  --context-bin /path/to/qwen3-1.7B-lpbq-sha.bin \
  --model-config examples/qwen3_qnn_aot/config_1.7B.json \
  --aot-config examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json \
  --tokenizer /path/to/qwen3-tokenizer.json
```

如需脚本自动在主机端生成 context：

```bash
scripts/qnn/run_qnn_aot_android_e2e.sh \
  --compile-context \
  --model-mllm /path/to/qwen3_1.7b.mllm \
  --model-config examples/qwen3_qnn_aot/config_1.7B.json \
  --aot-config examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json \
  --tokenizer /path/to/qwen3-tokenizer.json
```

### 4.5 qnn_android（非 AOT）一键端到端脚本

脚本路径：

- `scripts/qnn/run_qnn_android_e2e.sh`

示例：

```bash
scripts/qnn/run_qnn_android_e2e.sh \
  --npu-model /path/to/qwen1.5-1.8b-chat-rot-qnn.mllm \
  --cpu-model /path/to/qwen1.5-1.8b-chat-rot_q4_0.mllm \
  --tokenizer-json /path/to/tokenizer.json \
  --qwen-merges /path/to/qwen_merges.txt
```

说明：该脚本基于 `examples/qwen_npu`，会自动将模型推送为示例代码要求的固定文件名。脚本日志输出到 `logs/` 目录，便于 CI 与问题追踪。

---

## 5. 开发规范

## 5.1 代码规范

仓库现有约束：

- C/C++ 格式：`.clang-format`
- 静态检查：`.clang-tidy`
- 编辑器基础：`.editorconfig`
- 预提交：`.pre-commit-config.yaml`（clang-format hook）

建议流程：

```bash
pre-commit install
pre-commit run --all-files
```

## 5.2 提交规范

建议采用 Conventional Commits（便于自动生成变更日志）：

- `feat(qnn): add xxx`
- `fix(qnn-aot): resolve xxx`
- `perf(qnn): optimize xxx`
- `docs(qnn): update development guide`

## 5.3 代码审查流程

1. 提交前本地完成格式化 + 构建 + 最小运行验证
2. PR 描述必须包含：改动范围、验证步骤、风险点、回滚策略
3. 至少 1 名熟悉 QNN 子系统的 reviewer 通过
4. 高风险改动（AOT pipeline / runtime / op package）要求附性能对比

---

## 6. 调试方法与常见问题

## 6.1 快速定位

- 看 `--help` 确认参数：

```bash
./build-qnn-aot/bin/mllm-qwen3-aot-sha-c --help
./build-android-arm64-v8a-qnn/bin/mllm-qwen3-aot-runner --help
```

- 先查文件是否齐全：

```bash
adb shell "ls -l /data/local/tmp/mllm"
```

- 再查动态库依赖：

```bash
adb shell "cd /data/local/tmp/mllm && LD_LIBRARY_PATH=. ./mllm-qwen3-aot-runner -h"
```

## 6.2 常见错误与处理

1. `QNN include path is not set`

- 原因：未设置 `QAIRT_SDK_ROOT`
- 处理：`export QAIRT_SDK_ROOT=... && source .../envsetup.sh`

2. `ANDROID_NDK_ROOT is not set`（OpPackage 编译时报错）

- 原因：只导出了 `ANDROID_NDK_PATH`
- 处理：补充 `export ANDROID_NDK_ROOT=$ANDROID_NDK_PATH`

3. `Unsupported config option 2`（旧版 QNN）

- 原因：`qnn_aot_cfg_*.json` 默认 `HtpSignedPd`
- 处理：改为 `HtpUnsignedPd` 或升级 SDK

4. 设备端 `dlopen` 失败

- 原因：库未放在 `/data/local/tmp/mllm` 或未设置 `LD_LIBRARY_PATH`
- 处理：统一目录并导出 `LD_LIBRARY_PATH=/data/local/tmp/mllm`

---

## 7. 性能分析与优化建议

## 7.1 分析方法

1. 编译期：关注 AOT 时长、IR 大小（`*.mir`）
2. 运行期：统计 prefill 与 decode 吞吐
3. 工具层：结合 QNN profiling reader 与 SDK 工具查看热点

## 7.2 优化抓手

1. 量化策略

- 优先使用项目已验证配方（`qnn_aot_cfg_*.json`）
- 控制 `LPBQ block_size` 与精度折中（如 `16` vs `32`）

2. 图切分

- 减少 CPU/HTP 来回拷贝
- 优先把高算子密度子图放入 QNN

3. 运行参数

- 调整 `--ar_len`，在吞吐/时延间取平衡
- 结合目标芯片（V75/V79）选择匹配配置

4. 内存

- 监控 context binary 与 KV cache 占用
- 保持 tokenizer/config 与模型严格匹配，避免隐性重分配

---

## 8. 版本管理与 CI/CD 指南

## 8.1 版本策略

建议双维度版本管理：

- 代码版本：`main` + 功能分支（`feature/qnn-*`）
- 环境版本矩阵：`MLLM commit` × `QNN SDK` × `Hexagon SDK` × `NDK`

推荐维护 `qnn_version_matrix.md`（团队内部）：

- 芯片（SM8650/SM8750）
- `qnn_aot_cfg` 版本
- 可运行模型列表
- 已知问题与 workaround

## 8.2 CI/CD 实施建议

当前仓库已有基础构建流水线（x86 / android / docs）。针对 QNN 建议新增两条专用流水线：

1. `qnn-build-check`（self-hosted runner）

- 检查环境变量与 SDK 目录
- 执行 `tasks/build_x86_qnn_aot.yaml`
- 执行 `tasks/build_android_qnn.yaml`

2. `qnn-smoke-test`（接真机 farm）

- 推送到 `/data/local/tmp/mllm`
- 跑固定 prompt
- 记录 TTFT、TPS、峰值内存

示例（片段）：

```yaml
name: qnn-build-check
on: [pull_request]
jobs:
  qnn-build:
    runs-on: [self-hosted, linux, qnn]
    steps:
      - uses: actions/checkout@v4
      - run: python -m pip install -r requirements.txt
      - run: |
          source $QAIRT_SDK_ROOT/bin/envsetup.sh
          export ANDROID_NDK_ROOT=$ANDROID_NDK_PATH
          python task.py tasks/build_x86_qnn_aot.yaml
          python task.py tasks/build_android_qnn.yaml
```

---

## 9. 对旧文档的勘误（qnn_framework_development_guide.md）

以下为已确认的问题（以仓库代码和脚本为准）：

1. 环境变量主名不一致

- 旧文档多处使用 `QNN_SDK_ROOT`
- 实际构建依赖 `QAIRT_SDK_ROOT`（见 `mllm/backends/qnn/CMakeLists.txt` 与 `mllm/ffi/CMakeLists.txt`）

2. NDK 变量不一致

- 任务脚本用 `ANDROID_NDK_PATH`
- OpPackage Makefile 用 `ANDROID_NDK_ROOT`
- 正确做法：两者同时设置

3. 设备目录规范冲突

- 旧流程仍含 `/data/local/tmp`
- 本指南统一并强制 `/data/local/tmp/mllm`

4. 运行器命令名有歧义

- 正确目标名为 `mllm-qwen3-aot-runner`（来自 `examples/qwen3_qnn_aot/CMakeLists.txt`）

5. 过度绑定单一 SDK 版本

- `2.41.0.251128` 可作为参考基线，但不应写成唯一有效版本
- 实际应以版本矩阵与回归结果为准

---

## 10. 系统性审查与可执行性验证

本节用于在每次文档更新后自动核验“步骤正确性 + 完整性 + 可操作性”。

### 10.1 一键核验脚本

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1) 文件与任务存在性
for f in \
  tasks/build_x86_qnn_aot.yaml \
  tasks/build_android_qnn.yaml \
  examples/qwen3_qnn_aot/CMakeLists.txt \
  examples/qwen3_qnn_aot/compile_sha.cpp \
  examples/qwen3_qnn_aot/aot_run.cpp \
  examples/qwen_npu/main.cpp \
  scripts/qnn/run_qnn_aot_android_e2e.sh \
  scripts/qnn/run_qnn_android_e2e.sh \
  mllm/backends/qnn/CMakeLists.txt \
  mllm/backends/qnn/custom-op-package/LLaMAPackage/Makefile
  do
  test -f "$f" || { echo "missing: $f"; exit 1; }
done

# 2) 关键可执行名校验
rg -n "mllm-qwen3-aot-sha-c|mllm-qwen3-aot-runner" examples/qwen3_qnn_aot/CMakeLists.txt >/dev/null

# 3) 关键环境变量约束校验
rg -n "QAIRT_SDK_ROOT" mllm/backends/qnn/CMakeLists.txt mllm/ffi/CMakeLists.txt >/dev/null
rg -n "ANDROID_NDK_ROOT" mllm/backends/qnn/custom-op-package/LLaMAPackage/Makefile >/dev/null

# 4) 部署目录规范校验
rg -n "/data/local/tmp/mllm" development_guide.md >/dev/null

echo "QNN guide validation passed."
```

### 10.2 审查结论模板（建议放入 PR）

- 准确性：命令、变量、目标名均已对齐仓库当前实现
- 完整性：覆盖环境、编译、部署、规范、调试、优化、版本/CI
- 可操作性：包含可执行命令、路径规范、常见错误处理与核验脚本

---

## 11. 参考资料

1. MLLM QNN Backend 文档入口  
   https://ubiquitouslearning.github.io/mllm/qnn_backend/
2. MLLM QNN Environment Setup  
   https://ubiquitouslearning.github.io/mllm/qnn_backend/setup_env.html
3. MLLM QNN AOT Execution Flow  
   https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html
4. MLLM QNN Core Design  
   https://ubiquitouslearning.github.io/mllm/qnn_backend/core_design.html
5. PyTorch ExecuTorch Qualcomm LLM Flow（AOT/Hybird 思路参考）  
   https://pytorch.org/executorch/stable/llm/build-run-llama3-qualcomm-ai-engine-direct-backend.html
6. Qualcomm QNN Linux Setup（官方）  
   https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-50/linux_setup.html
7. Qualcomm QNN Op Package（官方）  
   https://docs.qualcomm.com/bundle/publicresource/topics/80-63442-10/op_packages.html
8. MLLM 文档首页（安装与构建总览）  
   https://ubiquitouslearning.github.io/mllm/
9. MLLM Service 文档（Android 部署路径与 `LD_LIBRARY_PATH` 实践）  
   https://ubiquitouslearning.github.io/mllm/service/mllm_cli.html
