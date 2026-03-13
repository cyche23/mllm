# 本地环境说明

## 适用范围

- 本文档记录当前服务器已准备好的 QNN / Hexagon SDK / Android NDK / Python 虚拟环境。
- 适用于需要执行 Qualcomm QNN、Android 真机部署、AOT 构建或设备侧验证的 coder / tester。
- 若任务仅做 `x86 dev host` 侧 smoke、profiling scaffold 或文档更新，可不启用本文档中的真机环境。

## 平台命名提醒

- 在本项目中，`host` 默认指 target device 上的 `arm64 CPU` 宿主侧。
- desktop / x86 Linux 开发机请显式写为 `x86 dev host`、`desktop host` 或 `host-side scaffold`。

## 服务器高通工具链路径

- Hexagon SDK: `/local/mnt/workspace/Qualcomm/Hexagon_SDK/6.4.0.1`
- QNN: `/opt/qcom/aistack/qairt/2.40.0.251030`

## 激活高通工具链和 Android NDK

按以下顺序执行：

```bash
source /opt/qcom/aistack/qairt/2.40.0.251030/bin/envsetup.sh
source /local/mnt/workspace/Qualcomm/Hexagon_SDK/6.4.0.1/setup_sdk_env.source
export ANDROID_NDK_PATH=$ANDROID_NDK_ROOT
```

## mllm 项目专用 Python 虚拟环境

- conda 环境名: `pymllm-py311`

激活命令：

```bash
conda activate pymllm-py311
```

该环境用于提供当前项目常用的 Python 工具链，例如较新的 `cmake`、`pymllm` 等。

## mllm-qnn-aot-qwen3 端到端测试部署脚本

- 脚本路径: `scripts/qnn/run_qnn_aot_android_e2e.sh`

## 推荐使用流程

建议在执行 QNN / Android 真机实验前按以下顺序准备环境：

```bash
source /opt/qcom/aistack/qairt/2.40.0.251030/bin/envsetup.sh
source /local/mnt/workspace/Qualcomm/Hexagon_SDK/6.4.0.1/setup_sdk_env.source
export ANDROID_NDK_PATH=$ANDROID_NDK_ROOT
conda activate pymllm-py311
```

然后再根据任务执行对应构建、部署或验证命令，例如：

```bash
bash scripts/qnn/run_qnn_aot_android_e2e.sh
```

## 使用要求

- 不要把本文档中的服务器绝对路径硬编码进源码默认行为；仅用于本机环境准备、实验脚本或 handoff 说明。
- 若真机实验依赖本文档环境，`handoff` 中的 `Required Env` 必须明确写出已使用 `docs/agent/LOCAL_ENV.md`。
- 若环境变量缺失、路径不存在或设备不可达，任务状态应标记为 `Blocked` 或在 `Risk / Limitation` 中明确说明。
