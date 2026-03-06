# QNN 框架持续开发指南

> 版本: 1.1  
> 更新日期: 2026-03-04  
> 适用项目: MLLM v2.x  
> QNN SDK 版本: 2.41.0.251128  
> Hexagon SDK 版本: 5.5.0.1

---

## 目录

- [1. 架构概述](#1-架构概述)
  - [1.1 QNN AOT 执行流程](#11-qnn-aot-执行流程)
  - [1.2 核心组件说明](#12-核心组件说明)
  - [1.3 量化策略](#13-量化策略)
- [2. 环境配置](#2-环境配置)
  - [2.1 系统要求](#21-系统要求)
  - [2.2 QNN SDK 安装](#22-qnn-sdk-安装)
  - [2.3 Hexagon SDK 配置](#23-hexagon-sdk-配置)
  - [2.4 Python 环境配置](#24-python-环境配置)
  - [2.5 环境变量设置](#25-环境变量设置)
- [3. 编译流程](#3-编译流程)
  - [3.1 X86 AOT 编译器构建](#31-x86-aot-编译器构建)
  - [3.2 Android 运行时构建](#32-android-运行时构建)
  - [3.3 编译参数详解](#33-编译参数详解)
  - [3.4 常见问题处理](#34-常见问题处理)
- [4. 模型量化与导出](#4-模型量化与导出)
  - [4.1 量化脚本使用](#41-量化脚本使用)
  - [4.2 模型格式转换](#42-模型格式转换)
  - [4.3 离线编译](#43-离线编译)
- [5. 移动端部署](#5-移动端部署)
  - [5.1 部署路径规范](#51-部署路径规范)
  - [5.2 资源推送脚本](#52-资源推送脚本)
  - [5.3 运行时启动](#53-运行时启动)
- [6. 开发规范](#6-开发规范)
  - [6.1 代码规范](#61-代码规范)
  - [6.2 提交规范](#62-提交规范)
  - [6.3 代码审查流程](#63-代码审查流程)
- [7. 调试方法](#7-调试方法)
  - [7.1 日志调试](#71-日志调试)
  - [7.2 GDB 调试](#72-gdb-调试)
  - [7.3 QNN 分析工具](#73-qnn-分析工具)
- [8. 性能优化](#8-性能优化)
  - [8.1 性能分析方法](#81-性能分析方法)
  - [8.2 量化优化建议](#82-量化优化建议)
  - [8.3 内存优化策略](#83-内存优化策略)
- [9. 版本管理](#9-版本管理)
  - [9.1 版本控制策略](#91-版本控制策略)
  - [9.2 CI/CD 配置](#92-cicd-配置)
  - [9.3 发布流程](#93-发布流程)
- [10. 附录](#10-附录)
  - [10.1 配置文件参考](#101-配置文件参考)
  - [10.2 错误代码对照表](#102-错误代码对照表)
  - [10.3 技术参考文档](#103-技术参考文档)
  - [10.4 相关资源链接](#104-相关资源链接)

---

## 1. 架构概述

### 1.1 QNN AOT 执行流程

QNN AOT (Ahead-of-Time) 是 MLLM 框架针对 Qualcomm Hexagon NPU 的离线编译方案，执行流程分为三个阶段：

```
┌─────────────────────────────────────────────────────────────────┐
│                     QNN AOT 执行流程                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Stage 1    │ -> │   Stage 2    │ -> │   Stage 3    │      │
│  │   Python     │    │    C++       │    │    C++       │      │
│  │  模型量化导出 │    │  离线编译     │    │  设备端执行   │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                 │
│  1. 量化并导出        2. 生成 QNN          3. 加载二进制        │
│     .safetensors         Context Binary      执行推理           │
│         ↓                      ↓                  ↓             │
│  mllm-convertor         QNN 工具链          AOT Runtime         │
│         ↓                      ↓                  ↓             │
│     .mllm 文件       qwen3-1.7B-lpbq-      移动端推理           │
│                                    sha.bin                      │
└─────────────────────────────────────────────────────────────────┘
```

**技术依据**: 该流程基于 Qualcomm AI Engine Direct SDK 的 AOT (Ahead-of-Time) 编译架构设计，参考 [QNN AOT Execution Flow - MLLM Documentation](https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html) [^1]。

### 1.2 核心组件说明

| 组件 | 路径 | 功能描述 |
|------|------|----------|
| `QnnAOTEnv` | `mllm/backends/qnn/aot/` | AOT 编译环境管理 |
| `QnnAOTRuntime` | `mllm/backends/qnn/aot_rt/` | 设备端运行时 |
| `QnnWrappersAPI` | `mllm/backends/qnn/aot/` | QNN API 封装层 |
| `AOTPipeline` | `mllm/backends/qnn/aot/passes/` | 编译优化流水线 |
| `compile.cpp` | `examples/qwen3_qnn_aot/` | 离线编译程序 |
| `aot_run.cpp` | `examples/qwen3_qnn_aot/` | 设备端运行程序 |

**技术依据**: 组件设计参考 PyTorch ExecuTorch 项目的 Hybrid Execution Mode for Qualcomm Backend [^1]。

### 1.3 量化策略

本项目采用 **W4A16 量化方案**：

- **权重 (Weight)**: 4-bit LPBQ (Low-Power Blockwise Quantization)，Block Size = 16
- **激活 (Activation)**: 16-bit 量化
- **KV Cache**: uint8 Per-Tensor 对称量化

```json
{
  "quant_recipe": {
    "linear": {
      "method": "LPBQ",
      "sym": true,
      "precision": "w4a16",
      "block_size": 16
    },
    "kv_cache": {
      "method": "per-tensor",
      "sym": true,
      "precision": "w8a8"
    }
  }
}
```

**技术依据**: LPBQ (Low-Power Blockwise Quantization) 是 Qualcomm 推荐的权重量化方法，可在保持精度的同时显著降低功耗。参考配置见 [qwen3_qnn_aot_cfg_1.7B.json](examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json)。

---

## 2. 环境配置

### 2.1 系统要求

**主机端 (X86 编译环境)**：
- OS: Ubuntu 22.04 LTS (推荐)
- CPU: x86_64 架构，支持 AVX2 指令集
- RAM: ≥ 16GB (推荐 32GB 用于大模型量化)
- GPU: NVIDIA GPU (可选，用于 PyTorch CUDA 加速量化)
- CMake: ≥ 3.22
- Python: ≥ 3.10

**目标设备端 (Android)**：
- OS: Android 12+ (API Level 31+)
- SoC: Qualcomm Snapdragon 8 Gen 2/3 (SM8550/SM8650)
- NPU: Hexagon V73/V75
- RAM: ≥ 8GB

**技术依据**: 
- QNN SDK 2.41.0 系统要求参考 [Qualcomm AI Engine Direct SDK Requirements](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk) [^2]
- Android API Level 要求基于 QNN HTP Backend 的最低支持版本

### 2.2 QNN SDK 安装

#### 2.2.1 下载 QNN SDK

**官方下载渠道**：
- **Qualcomm ChipCode**: https://chipcode.qti.qualcomm.com/ [^3]
- **Qualcomm Developer Network**: https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk [^2]

**推荐版本**: 2.41.0.251128 (与 MLLM v2.x 兼容)

```bash
# 从 Qualcomm ChipCode 下载
# 需要注册 Qualcomm 开发者账号
wget https://softwarecenter.qualcomm.com/api/download/software/qualcomm_neural_processing_sdk/v2.41.0.251128.zip
```

**技术依据**: QNN SDK 版本选择基于 MLLM 项目的兼容性测试，参考 [MLLM QNN AOT Documentation](https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html) [^1]。

#### 2.2.2 解压与配置

```bash
# 创建安装目录
sudo mkdir -p /opt/qcom/aistack/qairt/

# 解压 SDK
sudo unzip v2.41.0.251128.zip -d /opt/qcom/aistack/qairt/

# 创建软链接便于版本管理
sudo ln -sfn /opt/qcom/aistack/qairt/2.41.0.251128 /opt/qcom/aistack/qairt/latest

# 验证目录结构
ls -la /opt/qcom/aistack/qairt/latest/
# 应包含: bin/, include/, lib/, docs/
```

**验证安装**:
```bash
# 检查核心库文件
ls /opt/qcom/aistack/qairt/latest/lib/x86_64-linux-clang/
# 应包含: 
# - libQnnHtp.so          (HTP Backend 主库)
# - libQnnHtpV75Stub.so   (Hexagon V75 Stub)
# - libQnnHtpPrepare.so   (离线编译库)
# - libQnnSystem.so       (系统接口库)
```

**技术依据**: QNN SDK 目录结构参考官方安装文档 [QNN SDK Getting Started Guide](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/getting-started) [^2]。

#### 2.2.3 环境设置脚本

QNN SDK 提供官方环境设置脚本：

```bash
# 方式一: 使用官方 envsetup.sh (推荐)
source /opt/qcom/aistack/qairt/2.41.0.251128/bin/envsetup.sh

# 验证环境变量
echo $QNN_SDK_ROOT  # 应输出: /opt/qcom/aistack/qairt/2.41.0.251128
echo $LD_LIBRARY_PATH  # 应包含 QNN SDK 库路径
```

**技术依据**: `envsetup.sh` 脚本由 QNN SDK 官方提供，自动配置所有必要的环境变量，参考 [QNN SDK Environment Setup](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/tools) [^2]。

### 2.3 Hexagon SDK 配置

#### 2.3.1 下载 Hexagon SDK

**官方下载**: https://developer.qualcomm.com/software/hexagon-dsp-sdk [^4]

**推荐版本**: 5.5.0.1 (与 QNN SDK 2.41.0 兼容)

**版本兼容性矩阵**:

| QNN SDK 版本 | Hexagon SDK 版本 | Hexagon Tools 版本 |
|-------------|------------------|-------------------|
| 2.41.0.251128 | 5.5.0.1 | 8.5.03 |
| 2.40.0.251030 | 5.4.0.3 | 8.4.09 |

**技术依据**: 版本兼容性参考 [Hexagon SDK Release Notes](https://developer.qualcomm.com/software/hexagon-dsp-sdk/tools) [^4]。

#### 2.3.2 配置环境变量

```bash
# 方式一: 使用官方 setup_sdk_env.source
source /opt/qcom/HexagonSDK/5.5.0.1/setup_sdk_env.source

# 方式二: 手动配置
export HEXAGON_SDK_ROOT=/opt/qcom/HexagonSDK/5.5.0.1
export HEXAGON_TOOLS_ROOT=$HEXAGON_SDK_ROOT/tools/HEXAGON_Tools/8.5.03
export PATH=$HEXAGON_TOOLS_ROOT/Tools/bin:$PATH
```

**验证安装**:
```bash
# 检查 hexagon-clang 工具
which hexagon-clang
hexagon-clang --version  # 应显示 8.5.03
```

**技术依据**: Hexagon SDK 环境配置参考 [Hexagon SDK Getting Started Guide](https://developer.qualcomm.com/software/hexagon-dsp-sdk/getting-started) [^4]。

### 2.4 Python 环境配置

#### 2.4.1 创建虚拟环境

**推荐方式**: 使用 Conda (便于管理 CUDA 依赖)

```bash
# 创建 Python 3.11 环境
conda create -n pymllm-py311 python=3.11 -y
conda activate pymllm-py311

# 验证 Python 版本
python --version  # Python 3.11.x
```

**技术依据**: Python 3.11 是 MLLM 项目的推荐版本，参考 [pyproject.toml](pyproject.toml) 中的 `requires-python = ">=3.10"`。

#### 2.4.2 安装基础依赖

```bash
cd /root/codes/mllm-v2

# 安装基础依赖
pip install -r requirements.txt

# 安装 QNN AOT 专用依赖
pip install -r requirements-qnn-aot.txt
```

**依赖说明**:

| 依赖文件 | 用途 | 关键包 |
|---------|------|--------|
| `requirements.txt` | 基础构建依赖 | cmake-format, pyyaml, safetensors |
| `requirements-qnn-aot.txt` | 量化脚本依赖 | transformers==4.57.3, modelscope==1.33.0, datasets==2.21.0 |

**技术依据**: 依赖版本锁定参考 [requirements-qnn-aot.txt](requirements-qnn-aot.txt) 和 [pyproject.toml](pyproject.toml)。

#### 2.4.3 安装 pymllm 包

**方式一: 标准安装 (推荐用于生产环境)**

```bash
# 构建并安装 wheel 包
bash ./scripts/install_pymllm.sh

# 验证安装
python -c "import pymllm; print(pymllm.__version__)"
```

**方式二: 开发模式安装 (推荐用于开发)**

```bash
# 可编辑安装
pip install -e .

# 链接构建目录以便 TVM FFI 加载库
ln -sfn $(pwd)/build-qnn-aot/bin/ pymllm/lib

# 验证 FFI 链接
python -c "from pymllm.ffi import _ffi_api; print('FFI OK')"
```

**技术依据**: pymllm 安装方法参考 [MLLM QNN AOT Documentation - Model Quantization](https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html) [^1]。

### 2.5 环境变量设置

#### 2.5.1 完整环境变量配置

添加到 `~/.bashrc` 或 `~/.zshrc`：

```bash
# ============================================
# QNN SDK 环境配置
# ============================================
export QNN_SDK_ROOT=/opt/qcom/aistack/qairt/2.41.0.251128
export QNN_SDK_LIB=$QNN_SDK_ROOT/lib/x86_64-linux-clang
export PATH=$QNN_SDK_ROOT/bin/x86_64-linux-clang:$PATH

# 运行时库路径
export LD_LIBRARY_PATH=$QNN_SDK_LIB:$LD_LIBRARY_PATH

# ============================================
# Hexagon SDK 环境配置
# ============================================
export HEXAGON_SDK_ROOT=/opt/qcom/HexagonSDK/5.5.0.1
export HEXAGON_TOOLS_ROOT=$HEXAGON_SDK_ROOT/tools/HEXAGON_Tools/8.5.03
export PATH=$HEXAGON_TOOLS_ROOT/Tools/bin:$PATH

# ============================================
# Android NDK 配置
# ============================================
export ANDROID_NDK_PATH=/opt/android-ndk-r27d
export PATH=$ANDROID_NDK_PATH:$PATH

# ============================================
# MLLM 项目配置
# ============================================
export MLLM_ROOT=/root/codes/mllm-v2
export PYTHONPATH=$MLLM_ROOT:$PYTHONPATH
```

#### 2.5.2 环境验证脚本

创建 `verify_env.sh`：

```bash
#!/bin/bash
# verify_env.sh - 环境配置验证脚本

echo "=== QNN 环境验证 ==="

# 检查 QNN SDK
echo -n "QNN SDK: "
if [ -d "$QNN_SDK_ROOT" ]; then
    echo "✓ OK ($QNN_SDK_ROOT)"
else
    echo "✗ Not found"
fi

# 检查 Hexagon SDK
echo -n "Hexagon SDK: "
if [ -d "$HEXAGON_SDK_ROOT" ]; then
    echo "✓ OK ($HEXAGON_SDK_ROOT)"
else
    echo "✗ Not found"
fi

# 检查 Android NDK
echo -n "Android NDK: "
if [ -d "$ANDROID_NDK_PATH" ]; then
    echo "✓ OK ($ANDROID_NDK_PATH)"
else
    echo "✗ Not found"
fi

# 检查关键工具
echo -n "hexagon-clang: "
if command -v hexagon-clang &> /dev/null; then
    echo "✓ OK ($(hexagon-clang --version | head -1))"
else
    echo "✗ Not found"
fi

# 检查 Python 包
echo -n "pymllm: "
python -c "import pymllm; print('✓ OK')" 2>/dev/null || echo "✗ Not installed"

echo "=== 验证完成 ==="
```

**使用方法**:
```bash
chmod +x verify_env.sh
source ~/.bashrc && ./verify_env.sh
```

**技术依据**: 环境变量配置参考 QNN SDK 和 Hexagon SDK 官方文档 [^2][^4]。

---

## 3. 编译流程

### 3.1 X86 AOT 编译器构建

#### 3.1.1 编译命令

```bash
cd /root/codes/mllm-v2

# 执行编译任务
python task.py tasks/build_x86_qnn_aot.yaml

# 验证输出
ls -la build-qnn-aot/bin/
# 应包含:
# - mllm-qwen3-aot-sha-c  (Qwen3 AOT 编译器)
# - libmllm.so            (MLLM 核心库)
```

#### 3.1.2 编译配置详解

**配置文件**: `tasks/build_x86_qnn_aot.yaml`

```yaml
Tasks:
  - CMakeConfigTask:
      cmake_cfg_path: "build-qnn-aot"
      cmake_build_type: "RelWithDebInfo"  # 带调试信息的发布版
      cmake_extra_args:
        # Highway 库配置 (矩阵运算加速)
        - "-DHWY_ENABLE_TESTS=OFF"
        - "-DHWY_ENABLE_EXAMPLES=OFF"
        - "-DHWY_ENABLE_CONTRIB=OFF"
        
        # CPU 编译选项
        - '-DMLLM_CPU_BACKEND_COMPILE_OPTIONS="-march=native"'
        
        # 多线程配置
        - "-DMLLM_KERNEL_USE_THREADS=ON"
        - "-DMLLM_KERNEL_THREADS_VENDOR_OPENMP=ON"
        - "-DMLLM_KERNEL_USE_THREADS_VENDOR_MLLM=OFF"
        
        # QNN AOT 核心选项
        - "-DMLLM_QUALCOMM_QNN_AOT_ON_X86_ENABLE=ON"

  - CMakeBuildTask:
      cmake_cfg_path: "build-qnn-aot"
```

**关键参数说明**:

| 参数 | 值 | 说明 |
|------|-----|------|
| `MLLM_QUALCOMM_QNN_AOT_ON_X86_ENABLE` | ON | 启用 QNN AOT 编译功能 |
| `MLLM_KERNEL_USE_THREADS` | ON | 启用多线程加速 |
| `MLLM_KERNEL_THREADS_VENDOR_OPENMP` | ON | 使用 OpenMP 作为线程后端 |
| `CMAKE_BUILD_TYPE` | RelWithDebInfo | 带调试信息的优化版本 |

**技术依据**: 
- CMake 配置参考 [CMake Documentation](https://cmake.org/documentation/) [^5]
- OpenMP 多线程配置参考 [OpenMP Specification](https://www.openmp.org/specifications/) [^6]

### 3.2 Android 运行时构建

#### 3.2.1 编译命令

```bash
cd /root/codes/mllm-v2

# 执行编译任务
python task.py tasks/build_android_qnn.yaml

# 验证输出
ls -la build-android-arm64-v8a-qnn/bin/
# 应包含:
# - mllm-qwen3-aot-run  (设备端运行程序)
# - libmllm.so          (ARM64 动态库)
```

#### 3.2.2 编译配置详解

**配置文件**: `tasks/build_android_qnn.yaml`

```yaml
Tasks:
  - HexagonMakeTask:
      mllm_qnn_package_place: "mllm/backends/qnn/custom-op-package/LLaMAPackage"
      targets:
        - "htp_aarch64"  # Hexagon HTP 后端 (ARM64)
        - "htp_v75"      # Hexagon V75 特定优化

  - CMakeConfigTask:
      cmake_cfg_path: "build-android-arm64-v8a-qnn"
      cmake_build_type: "Release"
      cmake_toolchain_file: "$ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake"
      cmake_extra_args:
        # 交叉编译配置
        - "-DMLLM_CROSS_COMPILE=ON"
        - "-DMLLM_BUILD_ARM_BACKEND=ON"
        - "-DMLLM_BUILD_QNN_BACKEND=ON"
        
        # Android 平台配置
        - "-DANDROID_PLATFORM=android-28"
        - "-DANDROID_ABI=arm64-v8a"
        
        # ARM64 编译优化选项
        - '-DMLLM_CPU_BACKEND_COMPILE_OPTIONS="-march=armv8.2-a+fp16+fp16fml+dotprod+i8mm;-ffast-math;-Wno-nan-infinity-disabled"'
        
        # 安装路径
        - "-DCMAKE_INSTALL_PREFIX=/root/mllm-install-android-arm64-v8a-qnn"
        
        # 多线程配置
        - "-DMLLM_KERNEL_USE_THREADS=ON"
        - "-DMLLM_KERNEL_THREADS_VENDOR_OPENMP=ON"

  - CMakeBuildTask:
      cmake_cfg_path: "build-android-arm64-v8a-qnn"

  - CMakeInstallTask:
      cmake_cfg_path: "build-android-arm64-v8a-qnn"
```

**关键参数说明**:

| 参数 | 值 | 说明 |
|------|-----|------|
| `CMAKE_TOOLCHAIN_FILE` | android.toolchain.cmake | Android NDK 官方工具链 |
| `ANDROID_ABI` | arm64-v8a | ARM64 架构 |
| `ANDROID_PLATFORM` | android-28 | Android 9.0 (API 28+) |
| `MLLM_CROSS_COMPILE` | ON | 启用交叉编译模式 |

**ARM64 编译选项详解**:

| 选项 | 说明 |
|------|------|
| `-march=armv8.2-a` | ARMv8.2-A 架构 |
| `+fp16` | 半精度浮点支持 |
| `+fp16fml` | 半精度浮点乘加指令 |
| `+dotprod` | 点积指令 (INT8 加速) |
| `+i8mm` | INT8 矩阵乘法指令 |
| `-ffast-math` | 快速数学运算 (牺牲精度换性能) |

**技术依据**: 
- Android NDK CMake 工具链参考 [Android NDK CMake Guide](https://developer.android.com/ndk/guides/cmake) [^7]
- ARM64 编译选项参考 [ARM Compiler Reference Guide](https://developer.arm.com/documentation/101754/latest) [^8]

### 3.3 编译参数详解

#### 3.3.1 MLLM 特定选项

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MLLM_QUALCOMM_QNN_AOT_ON_X86_ENABLE` | BOOL | OFF | 启用 X86 AOT 编译功能 |
| `MLLM_BUILD_QNN_BACKEND` | BOOL | OFF | 构建 QNN 后端支持 |
| `MLLM_BUILD_ARM_BACKEND` | BOOL | OFF | 构建 ARM CPU 后端 |
| `MLLM_CROSS_COMPILE` | BOOL | OFF | 启用交叉编译模式 |
| `MLLM_KERNEL_USE_THREADS` | BOOL | ON | 启用多线程加速 |
| `MLLM_KERNEL_THREADS_VENDOR_OPENMP` | BOOL | ON | 使用 OpenMP |
| `MLLM_KERNEL_USE_THREADS_VENDOR_MLLM` | BOOL | OFF | 使用 MLLM 自研线程池 |

#### 3.3.2 CMake 标准选项

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `CMAKE_BUILD_TYPE` | RelWithDebInfo | 带调试信息的优化版本 |
| `CMAKE_INSTALL_PREFIX` | /path/to/install | 安装目录 |
| `CMAKE_CXX_STANDARD` | 17 | C++ 标准版本 |

### 3.4 常见问题处理

#### 3.4.1 问题: 找不到 QNN 库

**错误信息**:
```
error: cannot find -lQnnHtp
error: QnnHtp.h: No such file or directory
```

**根本原因**: 
- `LD_LIBRARY_PATH` 未包含 QNN SDK 库路径
- `QNN_SDK_ROOT` 环境变量未设置

**解决方案**:
```bash
# 临时设置 (当前终端)
export QNN_SDK_ROOT=/opt/qcom/aistack/qairt/2.41.0.251128
export LD_LIBRARY_PATH=$QNN_SDK_ROOT/lib/x86_64-linux-clang:$LD_LIBRARY_PATH

# 或使用官方脚本
source $QNN_SDK_ROOT/bin/envsetup.sh

# 验证
echo $LD_LIBRARY_PATH
ls $QNN_SDK_ROOT/lib/x86_64-linux-clang/libQnnHtp.so
```

**技术依据**: QNN SDK 环境配置参考 [QNN SDK Getting Started](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/getting-started) [^2]。

#### 3.4.2 问题: Hexagon 工具链未找到

**错误信息**:
```
error: hexagon-clang not found
error: Cannot find Hexagon tools
```

**解决方案**:
```bash
# 设置 Hexagon SDK 环境
export HEXAGON_SDK_ROOT=/opt/qcom/HexagonSDK/5.5.0.1
export PATH=$HEXAGON_SDK_ROOT/tools/HEXAGON_Tools/8.5.03/Tools/bin:$PATH

# 验证
which hexagon-clang
hexagon-clang --version
```

#### 3.4.3 问题: Android NDK 配置错误

**错误信息**:
```
error: CMAKE_SYSTEM_NAME is 'Android' but NDK is not found
error: Could not find Android NDK
```

**解决方案**:
```bash
# 设置 NDK 路径
export ANDROID_NDK_PATH=/opt/android-ndk-r27d

# 验证 NDK 完整性
ls $ANDROID_NDK_PATH/build/cmake/android.toolchain.cmake

# 重新运行编译
python task.py tasks/build_android_qnn.yaml
```

**技术依据**: Android NDK CMake 配置参考 [Android NDK CMake Guide](https://developer.android.com/ndk/guides/cmake) [^7]。

---

## 4. 模型量化与导出

### 4.1 量化脚本使用

#### 4.1.1 执行量化

```bash
cd /root/codes/mllm-v2/pymllm/backends/qualcomm/transformers/qwen3

python train.py \
  --model_path "/root/models/Qwen3-1.7B/origin" \
  --max_length 1024 \
  --num_samples 128 \
  --output_dir "/root/models/Qwen3-1.7B/qnn"
```

#### 4.1.2 参数说明

| 参数 | 默认值 | 说明 | 技术依据 |
|------|--------|------|----------|
| `--model_path` | 必填 | 原始 HuggingFace 模型路径 | [Transformers Docs](https://huggingface.co/docs/transformers/index) [^9] |
| `--max_length` | 2048 | 最大序列长度 | 受限于设备内存和 QNN HTP VTCM |
| `--num_samples` | 128 | 校准样本数量 | PTQ 推荐 128-512 样本 [^10] |
| `--infer_text` | "为什么伟大不能被计划" | 推理验证文本 | 用于验证量化后模型质量 |
| `--output_dir` | 必填 | 输出目录 | - |

#### 4.1.3 量化流程详解

```python
# train.py 核心流程
m = Qwen3Quantizer(args.model_path, mllm_qualcomm_max_length=args.max_length)

# 1. 禁用伪量化 (校准阶段使用浮点)
m.disable_fake_quant()

# 2. PTQ 校准 - 收集激活统计信息
m.calibrate(num_samples=args.num_samples, max_seq_length=args.max_length)

# 3. 启用伪量化 (模拟量化效果)
m.enable_fake_quant()

# 4. 重新计算量化参数
m.recompute_scale_zp()

# 5. 验证 Concat 层量化一致性
m.validate_concat_observer()

# 6. 推理验证
m.infer(args.infer_text)

# 7. 转换权重格式为部署格式
m.convert()

# 8. 保存量化模型
save_model(m.model, model_save_path)
```

**技术依据**: 
- PTQ (Post-Training Quantization) 流程参考 [PyTorch Quantization](https://pytorch.org/docs/stable/quantization.html) [^10]
- 伪量化 (Fake Quantization) 原理参考 [Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference](https://arxiv.org/abs/1712.05877) [^11]

#### 4.1.4 校准数据集

默认使用 **Wikipedia 数据集** (`modelscope/wikitext`)：

```python
# runner.py 中的校准实现
dataset = MsDataset.load(
    "modelscope/wikitext",
    subset_name="wikitext-103-v1",
    split="train",
    trust_remote_code=True,
)
```

**技术依据**: 
- Wikitext 数据集是语言模型量化的标准校准数据集
- ModelScope 数据集加载参考 [ModelScope Documentation](https://modelscope.cn/docs) [^12]

### 4.2 模型格式转换

#### 4.2.1 转换命令

```bash
mllm-convertor \
  --input_path /root/models/Qwen3-1.7B/qnn/model.safetensors \
  --output_path /root/models/Qwen3-1.7B/qnn/qwen3_1.7b.mllm \
  --verbose
```

#### 4.2.2 参数说明

| 参数 | 说明 |
|------|------|
| `--input_path` | 输入的 safetensors 文件路径 |
| `--output_path` | 输出的 mllm 文件路径 |
| `--verbose` | 打印详细日志（调试用） |
| `--pipeline` | (可选) 指定转换流水线 |

**技术依据**: 
- `mllm-convertor` 是 pymllm 包提供的 CLI 工具，定义于 [pyproject.toml](pyproject.toml)
- Safetensors 格式参考 [HuggingFace Safetensors](https://huggingface.co/docs/safetensors/index) [^13]

### 4.3 离线编译

#### 4.3.1 编译命令

```bash
cd /root/codes/mllm-v2

./build-qnn-aot/bin/mllm-qwen3-aot-sha-c \
  -m /root/models/Qwen3-1.7B/qnn/qwen3_1.7b.mllm \
  -c ./examples/qwen3_qnn_aot/config_1.7B.json \
  --aot_config ./examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json \
  --qnn_env_path /opt/qcom/aistack/qairt/2.41.0.251128/lib/x86_64-linux-clang/
```

#### 4.3.2 参数详解

| 参数 | 简写 | 说明 | 默认值 |
|------|------|------|--------|
| `--model_path` | `-m` | MLLM 模型文件路径 | 必填 |
| `--config` | `-c` | 模型配置文件路径 | 必填 |
| `--aot_config` | `-aot_cfg` | AOT 配置文件路径 | 必填 |
| `--qnn_env_path` | `-qnn_env` | QNN SDK 库路径 | `/opt/qcom/aistack/qairt/2.41.0.251128/lib/x86_64-linux-clang/` |
| `--help` | `-h` | 显示帮助信息 | - |

#### 4.3.3 输出文件

- **qwen3-1.7B-lpbq-sha.bin** - QNN Context Binary (部署到设备端)

**技术依据**: 
- QNN Context Binary 是 Qualcomm AI Engine Direct 的标准部署格式
- 参考 [QNN SDK Documentation - Context Binary](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/tools) [^2]

---

## 5. 移动端部署

### 5.1 部署路径规范

#### 5.1.1 统一目标路径

**强制使用**: `/data/local/tmp/mllm/`

**目录结构**:
```
/data/local/tmp/mllm/
├── qwen3-1.7B-lpbq-sha.bin    # QNN Context Binary (模型)
├── libQnnHtp.so               # QNN HTP Backend 库
├── libQnnHtpV75Stub.so        # Hexagon V75 Stub 库
├── libQnnHtpPrepare.so        # QNN Prepare 库
├── libQnnSystem.so            # QNN System 接口库
├── libLLaMAPackage.so         # Custom Op Package (Hexagon)
├── mllm-qwen3-aot-run         # 可执行程序
└── tokenizer.json             # Tokenizer 文件
```

**技术依据**: 
- `/data/local/tmp/` 是 Android 系统的标准临时目录，所有应用均可访问
- 使用子目录 `mllm` 便于管理和清理

### 5.2 资源推送脚本

#### 5.2.1 完整部署脚本

创建 `deploy.sh`：

```bash
#!/bin/bash
# deploy.sh - QNN 模型部署脚本
# 技术依据: Android Debug Bridge (ADB) 文档 https://developer.android.com/studio/command-line/adb

set -e  # 遇到错误立即退出

# ============================================
# 配置区域
# ============================================
DEVICE_PATH="/data/local/tmp/mllm"
QNN_SDK_ROOT="/opt/qcom/aistack/qairt/2.41.0.251128"
MODEL_BIN="qwen3-1.7B-lpbq-sha.bin"
MODEL_PATH="/root/models/Qwen3-1.7B/qnn"
BUILD_PATH="/root/codes/mllm-v2/build-android-arm64-v8a-qnn"
OP_PATH="/root/codes/mllm-v2/mllm/backends/qnn/custom-op-package/LLaMAPackage/build"

# ============================================
# 颜色输出
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================
# 预检查
# ============================================
echo "=== QNN 模型部署脚本 ==="
log_info "目标设备路径: $DEVICE_PATH"

# 检查 ADB 连接
if ! adb devices | grep -q "device$"; then
    log_error "未检测到 Android 设备，请检查 ADB 连接"
    exit 1
fi
log_info "ADB 连接正常"

# 检查本地文件
files_to_check=(
    "$MODEL_PATH/$MODEL_BIN"
    "$QNN_SDK_ROOT/lib/aarch64-android/libQnnHtp.so"
    "$BUILD_PATH/bin/mllm-qwen3-aot-run"
    "$OP_PATH/htp_aarch64/libLLaMAPackage.so"
)

for file in "${files_to_check[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "文件不存在: $file"
        exit 1
    fi
done
log_info "所有本地文件检查通过"

# ============================================
# 部署流程
# ============================================

# 1. 创建设备目录
log_info "[1/6] 创建设备目录..."
adb shell "mkdir -p $DEVICE_PATH"

# 2. 推送模型文件
log_info "[2/6] 推送模型文件..."
adb push "$MODEL_PATH/$MODEL_BIN" "$DEVICE_PATH/"

# 3. 推送 QNN 运行时库
log_info "[3/6] 推送 QNN 运行时库..."
adb push "$QNN_SDK_ROOT/lib/aarch64-android/libQnnHtp.so" "$DEVICE_PATH/"
adb push "$QNN_SDK_ROOT/lib/aarch64-android/libQnnHtpV75Stub.so" "$DEVICE_PATH/"
adb push "$QNN_SDK_ROOT/lib/aarch64-android/libQnnHtpPrepare.so" "$DEVICE_PATH/"
adb push "$QNN_SDK_ROOT/lib/aarch64-android/libQnnSystem.so" "$DEVICE_PATH/"

# 4. 推送 Custom Op Package
log_info "[4/6] 推送 Custom Op Package..."
adb push "$OP_PATH/htp_aarch64/libLLaMAPackage.so" "$DEVICE_PATH/"

# 5. 推送可执行文件
log_info "[5/6] 推送可执行文件..."
adb push "$BUILD_PATH/bin/mllm-qwen3-aot-run" "$DEVICE_PATH/"

# 6. 设置权限
log_info "[6/6] 设置执行权限..."
adb shell "chmod 755 $DEVICE_PATH/mllm-qwen3-aot-run"
adb shell "chmod 644 $DEVICE_PATH/*.so"
adb shell "chmod 644 $DEVICE_PATH/*.bin"

# ============================================
# 验证部署
# ============================================
log_info "验证部署结果..."
adb shell "ls -la $DEVICE_PATH/"

echo ""
echo "=== 部署完成 ==="
log_info "运行命令:"
echo "  adb shell 'cd $DEVICE_PATH && export LD_LIBRARY_PATH=$DEVICE_PATH:\$LD_LIBRARY_PATH && ./mllm-qwen3-aot-run -c config.json'"
```

**使用方法**:
```bash
chmod +x deploy.sh
./deploy.sh
```

**技术依据**: 
- ADB 命令参考 [Android Debug Bridge Documentation](https://developer.android.com/studio/command-line/adb) [^14]
- Android 运行时库路径设置参考 [QNN SDK HTP Backend Guide](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/tools) [^2]

### 5.3 运行时启动

#### 5.3.1 交互式运行

```bash
adb shell

cd /data/local/tmp/mllm
export LD_LIBRARY_PATH=/data/local/tmp/mllm:$LD_LIBRARY_PATH

./mllm-qwen3-aot-run \
  -m qwen3-1.7B-lpbq-sha.bin \
  -t tokenizer.json \
  -c config.json \
  --ar_len 128
```

#### 5.3.2 直接运行

```bash
adb shell "cd /data/local/tmp/mllm && LD_LIBRARY_PATH=/data/local/tmp/mllm ./mllm-qwen3-aot-run -c config.json"
```

#### 5.3.3 运行时参数

| 参数 | 简写 | 说明 | 默认值 | 技术依据 |
|------|------|------|--------|----------|
| `--model` | `-m` | 模型二进制文件路径 | qwen3_qnn.mllm | - |
| `--tokenizer` | `-t` | Tokenizer 文件路径 | tokenizer.json | [Tokenizers Docs](https://huggingface.co/docs/tokenizers/index) [^15] |
| `--config` | `-c` | 模型配置文件路径 | 必填 | - |
| `--ar_len` | - | 自回归长度（分块大小） | 128 | 内存/性能权衡 |

**技术依据**: 
- `LD_LIBRARY_PATH` 设置参考 [Linux Shared Library Guide](https://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html) [^16]
- 运行时参数解析参考 [aot_run.cpp](examples/qwen3_qnn_aot/aot_run.cpp)

---

## 6. 开发规范

### 6.1 代码规范

#### 6.1.1 C++ 代码规范

**命名规范**:

| 类型 | 规范 | 示例 |
|------|------|------|
| 类名 | PascalCase | `QnnAOTEnv`, `Qwen3Quantizer` |
| 函数名 | camelCase | `loadModel()`, `recomputeScaleZp()` |
| 变量名 | snake_case | `model_path`, `num_samples` |
| 宏/常量 | UPPER_SNAKE_CASE | `MLLM_MAIN`, `QNN_AOT_ENABLE` |
| 私有成员 | 后缀下划线 | `model_`, `config_` |
| 模板参数 | PascalCase | `typename TensorType` |

**头文件规范**:
```cpp
// Copyright (c) MLLM Team.
// Licensed under the MIT License.

#pragma once

// 1. 系统头文件
#include <vector>
#include <string>
#include <unordered_map>

// 2. 第三方头文件
#include <fmt/core.h>
#include <torch/torch.h>

// 3. 项目头文件
#include "mllm/mllm.hpp"
#include "mllm/backends/qnn/aot/QnnWrappersAPI.hpp"
```

**技术依据**: 
- 头文件排序参考 [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html#Names_and_Order_of_Includes) [^17]
- 命名规范参考 [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines) [^18]

#### 6.1.2 代码格式化配置

**`.clang-format`**:
```yaml
BasedOnStyle: Google
IndentWidth: 2
ColumnLimit: 120
AllowShortFunctionsOnASingleLine: Empty
BreakBeforeBraces: Attach
PointerAlignment: Left
SortIncludes: true
```

**使用方法**:
```bash
# 格式化单个文件
clang-format -i src/file.cpp

# 格式化整个项目
find . -name "*.cpp" -o -name "*.hpp" | xargs clang-format -i
```

**技术依据**: [Clang-Format Documentation](https://clang.llvm.org/docs/ClangFormat.html) [^19]

### 6.2 提交规范

#### 6.2.1 Commit Message 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

**类型说明**:

| 类型 | 说明 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(qnn): add Qwen3 4B support` |
| `fix` | 修复 Bug | `fix(aot): resolve memory leak in KV cache` |
| `docs` | 文档更新 | `docs: update QNN setup guide` |
| `style` | 代码格式 | `style: fix indentation in compile.cpp` |
| `refactor` | 代码重构 | `refactor(qnn): simplify AOT pipeline` |
| `perf` | 性能优化 | `perf(quant): optimize LPBQ kernel` |
| `test` | 测试相关 | `test: add unit tests for QnnAOTEnv` |
| `chore` | 构建/工具 | `chore: update CMake minimum version` |

**技术依据**: [Conventional Commits Specification](https://www.conventionalcommits.org/) [^20]

### 6.3 代码审查流程

#### 6.3.1 审查检查清单

- [ ] **功能正确性**: 代码是否实现了预期功能
- [ ] **代码规范**: 是否符合命名和格式规范
- [ ] **文档注释**: 是否有足够的注释和文档
- [ ] **单元测试**: 是否包含单元测试且通过
- [ ] **性能影响**: 是否引入了性能问题
- [ ] **内存安全**: 是否存在内存泄漏或越界访问
- [ ] **错误处理**: 错误处理是否完善
- [ ] **兼容性**: 是否破坏了向后兼容性

#### 6.3.2 审查流程

1. **开发者**: 创建 Pull Request，填写描述模板
2. **CI 系统**: 自动运行测试和代码检查
3. **审查者**: 至少 1 名 Reviewer 进行代码审查
4. **开发者**: 解决 Review 意见
5. **维护者**: 合并到目标分支

**技术依据**: [GitHub Pull Request Review Documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests) [^21]

---

## 7. 调试方法

### 7.1 日志调试

#### 7.1.1 日志级别设置

```cpp
#include <mllm/utils/Logger.hpp>

// 设置日志级别
mllm::Logger::setLevel(mllm::LogLevel::DEBUG);

// 输出日志
MLLM_LOG_TRACE("Entering function: {}", __func__);
MLLM_LOG_DEBUG("Tensor shape: [{}, {}, {}, {}]", N, H, W, C);
MLLM_LOG_INFO("Loading model from: {}", model_path);
MLLM_LOG_WARN("Deprecated API usage: {}", api_name);
MLLM_LOG_ERROR("Failed to open file: {}", filename);
MLLM_LOG_FATAL("Critical error, exiting...");
```

**日志级别**:

| 级别 | 值 | 用途 |
|------|-----|------|
| `TRACE` | 0 | 最详细，跟踪执行流程 |
| `DEBUG` | 1 | 调试信息 |
| `INFO` | 2 | 一般信息 (默认) |
| `WARN` | 3 | 警告信息 |
| `ERROR` | 4 | 错误信息 |
| `FATAL` | 5 | 致命错误 |

**技术依据**: 日志级别设计参考 [Log4j Log Levels](https://logging.apache.org/log4j/2.x/manual/customloglevels.html) [^22]

#### 7.1.2 运行时日志控制

```bash
# 设置日志级别环境变量
export MLLM_LOG_LEVEL=DEBUG

# 运行程序
./mllm-qwen3-aot-sha-c -m model.mllm -c config.json
```

### 7.2 GDB 调试

#### 7.2.1 主机端调试

**编译 Debug 版本**:
```bash
cd /root/codes/mllm-v2

# 修改编译配置为 Debug
python task.py tasks/build_x86_qnn_aot.yaml --build-type Debug

# 或使用 CMake 直接配置
cmake -B build-debug -DCMAKE_BUILD_TYPE=Debug -DMLLM_QUALCOMM_QNN_AOT_ON_X86_ENABLE=ON
```

**GDB 调试命令**:
```bash
gdb ./build-debug/bin/mllm-qwen3-aot-sha-c

(gdb) set args -m model.mllm -c config.json --aot_config aot_cfg.json
(gdb) break main                    # 在 main 函数设置断点
(gdb) break QnnAOTEnv::initialize   # 在类方法设置断点
(gdb) run                           # 运行程序
(gdb) next                          # 单步执行 (跳过函数)
(gdb) step                          # 单步执行 (进入函数)
(gdb) continue                      # 继续执行
(gdb) bt                            # 查看调用栈
(gdb) info locals                   # 查看局部变量
(gdb) print variable_name           # 打印变量值
(gdb) display variable_name         # 持续显示变量
(gdb) watch variable_name           # 监视变量变化
(gdb) quit                          # 退出 GDB
```

**技术依据**: [GDB Documentation](https://sourceware.org/gdb/documentation/) [^23]

#### 7.2.2 设备端调试 (GDBServer)

**推送 GDBServer**:
```bash
# 从 NDK 获取 gdbserver
adb push $ANDROID_NDK_PATH/prebuilt/android-arm64/gdbserver/gdbserver /data/local/tmp/
```

**启动 GDBServer**:
```bash
# 在设备上启动 gdbserver
adb shell /data/local/tmp/gdbserver :5039 /data/local/tmp/mllm/mllm-qwen3-aot-run -c config.json

# 端口转发
adb forward tcp:5039 tcp:5039
```

**本地 GDB 连接**:
```bash
# 使用 NDK 提供的 GDB
$ANDROID_NDK_PATH/prebuilt/linux-x86_64/bin/gdb

(gdb) file ./build-android-arm64-v8a-qnn/bin/mllm-qwen3-aot-run
(gdb) target remote :5039
(gdb) break main
(gdb) continue
```

**技术依据**: [Android NDK GDB Guide](https://developer.android.com/ndk/guides/gdb) [^24]

### 7.3 QNN 分析工具

#### 7.3.1 QNN Profiling

**启用 Profiling**:
```bash
# 设置 Profiling 级别
export QNN_PROFILE_LEVEL=detailed  # basic | detailed | invalid

# 运行程序
./mllm-qwen3-aot-sha-c -m model.mllm -c config.json --aot_config aot_cfg.json

# 查看生成的 profile 文件
ls -la *.json
```

**技术依据**: [QNN SDK Profiling Guide](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/tools) [^2]

#### 7.3.2 性能分析工具

**QNN Netron (模型可视化)**:
```bash
# 安装 QNN Netron
pip install qti-aisw-tools-netron

# 可视化模型
python -m qti.aisw.tools.netron model.mllm
```

**Profile Viewer**:
```bash
# 使用 QNN Profile Viewer
python $QNN_SDK_ROOT/bin/x86_64-linux-clang/qnn-profile-viewer.py \
  -i profile.json \
  -o analysis.html
```

**技术依据**: QNN SDK 工具链文档 [^2]

---

## 8. 性能优化

### 8.1 性能分析方法

#### 8.1.1 关键性能指标

| 指标 | 英文全称 | 说明 | 目标值 | 测量方法 |
|------|----------|------|--------|----------|
| TTFT | Time To First Token | 首 token 生成时间 | < 500ms | 时间戳差值 |
| TPOT | Time Per Output Token | 每 token 生成时间 | < 50ms | 平均耗时 |
| Throughput | - | 吞吐量 | > 20 tokens/s | 总 tokens / 总时间 |
| Memory | - | 内存占用 | < 2GB | `dumpsys meminfo` |

**技术依据**: LLM 性能指标参考 [MLPerf Inference Benchmark](https://mlcommons.org/benchmarks/inference/) [^25]

#### 8.1.2 基准测试脚本

```bash
#!/bin/bash
# benchmark.sh - 性能基准测试

MODEL="qwen3-1.7B-lpbq-sha.bin"
CONFIG="config.json"
AR_LENS=(64 128 256)
PROMPTS=(
    "你好"
    "请介绍一下机器学习"
    "写一篇关于人工智能的短文"
)

echo "=== QNN AOT 性能基准测试 ==="
echo "模型: $MODEL"
echo ""

for ar_len in "${AR_LENS[@]}"; do
    echo "--- AR_LEN=$ar_len ---"
    
    for prompt in "${PROMPTS[@]}"; do
        echo "Prompt: $prompt"
        
        # 运行测试并记录时间
        adb shell "cd /data/local/tmp/mllm && LD_LIBRARY_PATH=. ./mllm-qwen3-aot-run \
            -m $MODEL -c $CONFIG --ar_len $ar_len" \
            2>&1 | tee -a "benchmark_ar${ar_len}.log"
    done
    echo ""
done

echo "=== 测试完成 ==="
echo "日志文件:"
ls -la benchmark_ar*.log
```

### 8.2 量化优化建议

#### 8.2.1 校准样本优化

**样本选择原则**:
1. **领域匹配**: 使用与目标场景相似的数据
2. **样本数量**: 128-512 样本 (平衡精度与校准时间)
3. **长度分布**: 覆盖典型输入长度分布

**推荐配置**:
```python
# train.py 参数优化
--num_samples 256      # 增加样本数量提高精度
--max_length 2048      # 根据实际使用场景调整
```

**技术依据**: PTQ 校准理论参考 [Post-Training Quantization Calibration](https://arxiv.org/abs/2002.00104) [^26]

#### 8.2.2 量化配置调优

**Block Size 选择**:

| Block Size | 精度 | 速度 | 内存 | 推荐场景 |
|------------|------|------|------|----------|
| 8 | 高 | 慢 | 高 | 高精度要求 |
| 16 | 中 | 中 | 中 | **默认推荐** |
| 32 | 低 | 快 | 低 | 资源受限 |

**配置示例**:
```json
{
  "quant_recipe": {
    "linear": {
      "block_size": 16,    // 尝试 8, 16, 32
      "sym": true          // 对称量化通常效果更好
    },
    "kv_cache": {
      "precision": "w8a8"  // 可尝试 w4a16 进一步压缩
    }
  }
}
```

**技术依据**: LPBQ 量化方法参考 [Qualcomm AI Research](https://www.qualcomm.com/research/artificial-intelligence) [^27]

### 8.3 内存优化策略

#### 8.3.1 KV Cache 量化

```cpp
// 使用 uint8 量化 KV Cache (节省 75% 内存)
auto past_key = mllm::Tensor::empty(
    {1, num_kv_heads, head_dim, cache_len},
    mllm::kUInt8PerTensorSym  // 8-bit 对称量化
);

// 对比: float32 (4 bytes) vs uint8 (1 byte)
// 内存节省: (4-1)/4 = 75%
```

**技术依据**: KV Cache 量化参考 [vLLM PagedAttention](https://arxiv.org/abs/2309.06180) [^28]

#### 8.3.2 分块推理 (Chunked Generation)

**AR_LEN 参数调优**:

| AR_LEN | 峰值内存 | 调用开销 | 推荐场景 |
|--------|----------|----------|----------|
| 64 | 低 | 高 | 长文本生成 |
| 128 | 中 | 中 | **默认推荐** |
| 256 | 高 | 低 | 短文本快速响应 |

**配置方法**:
```bash
# 运行时指定
./mllm-qwen3-aot-run -c config.json --ar_len 64
```

#### 8.3.3 内存监控

```bash
# 实时监控内存
adb shell dumpsys meminfo | grep mllm

# 使用 top 监控
adb shell top -p $(adb shell pidof mllm-qwen3-aot-run)

# 详细内存分析
adb shell cat /proc/$(adb shell pidof mllm-qwen3-aot-run)/status
```

**技术依据**: Android 内存分析参考 [Android Memory Management](https://developer.android.com/topic/performance/memory) [^29]

---

## 9. 版本管理

### 9.1 版本控制策略

#### 9.1.1 分支模型

```
main (稳定版本，受保护)
  ├── develop (开发分支)
  │     ├── feature/qnn-aot-qwen3
  │     ├── feature/quantization-optimization
  │     └── bugfix/memory-leak
  ├── release/v2.1.0
  └── hotfix/v2.0.1
```

**分支策略说明**:

| 分支 | 用途 | 保护级别 |
|------|------|----------|
| `main` | 稳定发布版本 | 受保护，需 PR 合并 |
| `develop` | 日常开发 | 受保护，需 PR 合并 |
| `feature/*` | 功能开发 | 无保护，开发完成后删除 |
| `release/*` | 发布准备 | 受保护，仅接受 bugfix |
| `hotfix/*` | 紧急修复 | 受保护，需快速审核 |

**技术依据**: [Git Flow Workflow](https://nvie.com/posts/a-successful-git-branching-model/) [^30]

#### 9.1.2 版本号规则

**语义化版本** (Semantic Versioning): `MAJOR.MINOR.PATCH`

| 部分 | 变更条件 | 示例 |
|------|----------|------|
| MAJOR | 不兼容的 API 变更 | 1.x.x → 2.0.0 |
| MINOR | 向下兼容的功能添加 | x.1.x → x.2.0 |
| PATCH | 向下兼容的问题修复 | x.x.1 → x.x.2 |

**技术依据**: [Semantic Versioning Specification](https://semver.org/) [^31]

### 9.2 CI/CD 配置

#### 9.2.1 GitHub Actions 配置

`.github/workflows/qnn-ci.yml`:

```yaml
name: QNN CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  QNN_SDK_VERSION: "2.41.0.251128"
  HEXAGON_SDK_VERSION: "5.5.0.1"

jobs:
  # X86 AOT 编译测试
  build-x86:
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Cache QNN SDK
        uses: actions/cache@v3
        with:
          path: /opt/qcom/aistack/qairt
          key: qnn-sdk-${{ env.QNN_SDK_VERSION }}
      
      - name: Download QNN SDK
        run: |
          if [ ! -d "/opt/qcom/aistack/qairt/${{ env.QNN_SDK_VERSION }}" ]; then
            wget -q $QNN_SDK_URL -O qnn.zip
            sudo unzip qnn.zip -d /opt/qcom/aistack/qairt/
          fi
      
      - name: Setup Environment
        run: |
          source /opt/qcom/aistack/qairt/${{ env.QNN_SDK_VERSION }}/bin/envsetup.sh
          echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> $GITHUB_ENV
      
      - name: Install Dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-qnn-aot.txt
      
      - name: Build X86 AOT
        run: |
          python task.py tasks/build_x86_qnn_aot.yaml
      
      - name: Run Tests
        run: |
          ./build-qnn-aot/bin/mllm-test --gtest_filter=QNN*

  # Android 交叉编译测试
  build-android:
    runs-on: ubuntu-22.04
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Setup Android NDK
        uses: android-actions/setup-android@v2
        with:
          ndk-version: r27d
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install Dependencies
        run: |
          pip install -r requirements.txt
      
      - name: Build Android
        run: |
          export ANDROID_NDK_PATH=$ANDROID_HOME/ndk/r27d
          python task.py tasks/build_android_qnn.yaml
      
      - name: Upload Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: android-build
          path: build-android-arm64-v8a-qnn/bin/
```

**技术依据**: [GitHub Actions Documentation](https://docs.github.com/en/actions) [^32]

### 9.3 发布流程

#### 9.3.1 发布检查清单

- [ ] **版本号更新**: `pyproject.toml` 和 `CMakeLists.txt` 中的版本号
- [ ] **CHANGELOG 更新**: 记录所有变更
- [ ] **测试通过**: 所有 CI 测试通过
- [ ] **文档更新**: API 文档和用户指南已更新
- [ ] **性能基准**: 性能测试无退化
- [ ] **兼容性测试**: 向后兼容性验证
- [ ] **安全审计**: 无已知安全漏洞

#### 9.3.2 发布步骤

1. **创建发布分支**:
   ```bash
   git checkout develop
   git pull origin develop
   git checkout -b release/v2.1.0
   ```

2. **版本号更新**:
   ```bash
   # 更新 pyproject.toml
   sed -i 's/version = "2.0.2"/version = "2.1.0"/' pyproject.toml
   
   # 更新 CMakeLists.txt
   sed -i 's/project(mllm VERSION 2.0.2)/project(mllm VERSION 2.1.0)/' CMakeLists.txt
   ```

3. **更新 CHANGELOG**:
   ```markdown
   ## [2.1.0] - 2026-03-04
   
   ### Added
   - 新增 Qwen3 4B 模型支持
   - 支持动态 batch size
   
   ### Changed
   - 优化 KV Cache 内存使用
   
   ### Fixed
   - 修复 ConcatObserver 量化不一致问题
   ```

4. **合并与打标签**:
   ```bash
   git add .
   git commit -m "chore(release): bump version to 2.1.0"
   git checkout main
   git merge release/v2.1.0
   git tag -a v2.1.0 -m "Release version 2.1.0"
   git push origin main --tags
   ```

5. **创建 GitHub Release**:
   - 上传编译好的二进制文件
   - 填写发布说明
   - 标记为预发布或正式版

**技术依据**: [GitHub Releases Documentation](https://docs.github.com/en/repositories/releasing-projects-on-github) [^33]

---

## 10. 附录

### 10.1 配置文件参考

#### 10.1.1 模型配置 (`config_1.7B.json`)

```json
{
  "architectures": ["Qwen3ForCausalLM"],
  "hidden_size": 2048,
  "num_hidden_layers": 28,
  "num_attention_heads": 16,
  "num_key_value_heads": 8,
  "head_dim": 128,
  "intermediate_size": 6144,
  "vocab_size": 151936,
  "max_position_embeddings": 40960,
  "rms_norm_eps": 1e-06,
  "rope_theta": 1000000,
  "tie_word_embeddings": true,
  "linear_impl_type": "QNN_LPBQ_w4a16o16_G16"
}
```

**配置项说明**:

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `hidden_size` | 2048 | 隐藏层维度 |
| `num_hidden_layers` | 28 | Transformer 层数 |
| `num_attention_heads` | 16 | 注意力头数 |
| `num_key_value_heads` | 8 | KV 头数 (GQA) |
| `head_dim` | 128 | 每个头的维度 |
| `linear_impl_type` | QNN_LPBQ_w4a16o16_G16 | 线性层实现类型 |

**技术依据**: Qwen3 配置参考 [Qwen3 Model Card](https://github.com/QwenLM/Qwen3) [^34]

#### 10.1.2 AOT 配置 (`qnn_aot_cfg_1.7B.json`)

```json
{
  "target_machine": {
    "htp_arch": "V75",
    "htp_chipset": "SM8650",
    "htp_try_best_performance": "HtpBurst",
    "htp_security_pd_session": "HtpUnsignedPd",
    "htp_vtcm_capability_in_mb": 8
  },
  "graph_on_qnn": ["model"],
  "op_on_qnn": ["lm_head"],
  "split_graph": 1,
  "quant_recipe": {
    "llm_recipe": true,
    "layers": 28,
    "builtin_llm_pass": {
      "model": "qwen3",
      "lm_head": {
        "fallback": {
          "method": "LPBQ",
          "sym": true,
          "precision": "w4a16",
          "block_size": 16
        }
      },
      "linear": {
        "fallback": {
          "method": "LPBQ",
          "sym": true,
          "precision": "w4a16",
          "block_size": 16
        }
      },
      "kv_cache": {
        "key": {
          "method": "per-tensor",
          "sym": true,
          "precision": "w8a8"
        },
        "value": {
          "method": "per-tensor",
          "sym": true,
          "precision": "w8a8"
        }
      }
    }
  }
}
```

**配置项说明**:

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `htp_arch` | V75 | Hexagon 架构版本 |
| `htp_chipset` | SM8650 | 目标芯片平台 |
| `htp_security_pd_session` | HtpUnsignedPd | 安全 PD 会话类型 |
| `htp_vtcm_capability_in_mb` | 8 | VTCM 大小 (MB) |
| `graph_on_qnn` | ["model"] | 在 QNN 上执行的图 |
| `op_on_qnn` | ["lm_head"] | 在 QNN 上执行的算子 |

**技术依据**: QNN HTP 配置参考 [QNN SDK HTP Backend Guide](https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk/tools) [^2]

### 10.2 错误代码对照表

| 错误代码 | 说明 | 可能原因 | 解决方案 |
|----------|------|----------|----------|
| `kCoreError` | 核心错误 | 参数错误、配置错误 | 检查输入参数和配置文件 |
| `kModelLoadError` | 模型加载失败 | 文件不存在、格式错误 | 验证模型文件路径和格式 |
| `kQuantizationError` | 量化错误 | 校准数据问题、配置错误 | 检查量化配置和校准数据 |
| `kCompilationError` | 编译错误 | SDK 版本不匹配、资源不足 | 检查 QNN SDK 版本和环境 |
| `kRuntimeError` | 运行时错误 | 内存不足、库缺失 | 检查设备资源和库依赖 |
| `kUnsupportedOpError` | 不支持的算子 | 算子未实现、版本不支持 | 更新 QNN SDK 或使用替代算子 |

#### 常见错误详解

**错误**: `Unsupported config option 2`
- **原因**: QNN SDK 版本不支持 `HtpSignedPd`
- **解决**: 将 `qnn_aot_cfg.json` 中的 `HtpSignedPd` 改为 `HtpUnsignedPd`

**错误**: `Failed to load libQnnHtp.so`
- **原因**: 动态库路径未正确设置
- **解决**: 
  ```bash
  export LD_LIBRARY_PATH=/opt/qcom/aistack/qairt/2.41.0.251128/lib/x86_64-linux-clang:$LD_LIBRARY_PATH
  ```

**错误**: `QnnHtp_prepare failed`
- **原因**: 模型与目标设备不兼容
- **解决**: 检查 `htp_arch` 和 `htp_chipset` 配置是否匹配目标设备

### 10.3 技术参考文档

#### 10.3.1 官方文档引用

| 文档 | 链接 | 说明 |
|------|------|------|
| MLLM QNN AOT 文档 | https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html | MLLM QNN AOT 执行流程 [^1] |
| QNN SDK 官方文档 | https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk | Qualcomm AI Engine Direct [^2] |
| Hexagon SDK 文档 | https://developer.qualcomm.com/software/hexagon-dsp-sdk | Hexagon DSP SDK [^4] |
| Android NDK 文档 | https://developer.android.com/ndk/guides | Android NDK 指南 [^7] |
| CMake 文档 | https://cmake.org/documentation/ | CMake 官方文档 [^5] |
| OpenMP 规范 | https://www.openmp.org/specifications/ | OpenMP API 规范 [^6] |

#### 10.3.2 学术论文引用

| 论文 | 链接 | 说明 |
|------|------|------|
| Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference | https://arxiv.org/abs/1712.05877 | 量化感知训练 [^11] |
| vLLM: Easy, Fast, and Cheap LLM Serving with PagedAttention | https://arxiv.org/abs/2309.06180 | PagedAttention [^28] |
| Post-Training Quantization Calibration | https://arxiv.org/abs/2002.00104 | PTQ 校准 [^26] |

### 10.4 相关资源链接

#### 10.4.1 模型资源

| 资源 | 链接 |
|------|------|
| Qwen3 官方仓库 | https://github.com/QwenLM/Qwen3 [^34] |
| MLLM ModelScope | https://www.modelscope.cn/organization/mllmTeam |
| MLLM HuggingFace | https://huggingface.co/mllmTeam |

#### 10.4.2 社区支持

| 平台 | 链接 |
|------|------|
| GitHub Issues | https://github.com/UbiquitousLearning/mllm/issues |
| MLLM 技术报告 | https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/ |
| MLLM 官方文档 | https://ubiquitouslearning.github.io/mllm/ |

---

## 参考文献

[^1]: MLLM Documentation - QNN AOT Execution Flow. https://ubiquitouslearning.github.io/mllm/qnn_backend/aot_execute.html

[^2]: Qualcomm AI Engine Direct SDK. https://developer.qualcomm.com/software/qualcomm-neural-processing-sdk

[^3]: Qualcomm ChipCode. https://chipcode.qti.qualcomm.com/

[^4]: Qualcomm Hexagon DSP SDK. https://developer.qualcomm.com/software/hexagon-dsp-sdk

[^5]: CMake Documentation. https://cmake.org/documentation/

[^6]: OpenMP Specifications. https://www.openmp.org/specifications/

[^7]: Android NDK Guides. https://developer.android.com/ndk/guides

[^8]: ARM Compiler Reference Guide. https://developer.arm.com/documentation/101754/latest

[^9]: HuggingFace Transformers Documentation. https://huggingface.co/docs/transformers/index

[^10]: PyTorch Quantization. https://pytorch.org/docs/stable/quantization.html

[^11]: Jacob et al., "Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference", CVPR 2018.

[^12]: ModelScope Documentation. https://modelscope.cn/docs

[^13]: HuggingFace Safetensors. https://huggingface.co/docs/safetensors/index

[^14]: Android Debug Bridge. https://developer.android.com/studio/command-line/adb

[^15]: HuggingFace Tokenizers. https://huggingface.co/docs/tokenizers/index

[^16]: Program Library HOWTO. https://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html

[^17]: Google C++ Style Guide. https://google.github.io/styleguide/cppguide.html

[^18]: C++ Core Guidelines. https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines

[^19]: Clang-Format Documentation. https://clang.llvm.org/docs/ClangFormat.html

[^20]: Conventional Commits. https://www.conventionalcommits.org/

[^21]: GitHub Pull Request Reviews. https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests

[^22]: Log4j Log Levels. https://logging.apache.org/log4j/2.x/manual/customloglevels.html

[^23]: GDB Documentation. https://sourceware.org/gdb/documentation/

[^24]: Android NDK GDB Guide. https://developer.android.com/ndk/guides/gdb

[^25]: MLPerf Inference Benchmark. https://mlcommons.org/benchmarks/inference/

[^26]: Post-Training Quantization Calibration. https://arxiv.org/abs/2002.00104

[^27]: Qualcomm AI Research. https://www.qualcomm.com/research/artificial-intelligence

[^28]: Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention", SOSP 2023.

[^29]: Android Memory Management. https://developer.android.com/topic/performance/memory

[^30]: A Successful Git Branching Model. https://nvie.com/posts/a-successful-git-branching-model/

[^31]: Semantic Versioning. https://semver.org/

[^32]: GitHub Actions. https://docs.github.com/en/actions

[^33]: GitHub Releases. https://docs.github.com/en/repositories/releasing-projects-on-github

[^34]: Qwen3 Model Card. https://github.com/QwenLM/Qwen3

---

## 文档更新记录

| 版本 | 日期 | 更新内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2026-03-04 | 初始版本 | MLLM Team |
| 1.1 | 2026-03-04 | 添加技术依据和权威引用 | MLLM Team |

---

*本文档由 MLLM 团队维护，如有问题请提交 Issue 或联系开发团队。*
