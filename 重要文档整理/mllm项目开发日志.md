# MLLM Qnn AOT 支持：在 NPU 上实现全图执行

> 原文：https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/  
> 翻译整理：AI Assistant

---

**GitHub 仓库**: https://github.com/UbiquitousLearning/mllm  
**官方网站**: https://ubiquitouslearning.github.io/mllm/index.html

---

## 1.1 引言

由于高通 NPU 的静态图架构和全整数计算要求，在 Qualcomm NPU 上部署大型语言模型（LLM）一直是业界的挑战。为了促进更便捷的端侧部署，我们在 MLLM 框架中实现了对 Qualcomm Qnn 框架的支持。现在，用户可以在 X86 机器上使用 MLLM 的 Qnn AOT 模式编译 LLM，随后使用 MLLM Qnn AOT 运行时在高通 NPU 边缘设备上高效运行。通过 MLLM 团队的精心设计，该框架通过统一的中间表示（IR）以轻量级方式支持模型量化、AOT 编译和实际执行的整个工作流程。在我们的优化下，Qwen3 1.7B 模型[1]在 Qualcomm SM8650 上使用 W4A16KV8 量化配置（chunk=32, pad=1024）运行时，在 640 个预填充 token 和 128 个解码 token 的场景下，预填充性能达到 758.28 tokens/s，解码性能达到 25.84 tokens/s。我们计划未来使用图选择方法进一步加速预填充和解码速度。

边缘设备对功耗和散热高度敏感，而 LLM 推理本身是一个对延迟要求极高的任务。尽管当前的 Arm CPU 通常配备了 SVE 和 SME 等加速单元，但其性能仍难以完全满足 LLM 推理的计算需求。此外，在边缘设备中，CPU 通常需要处理其他低延迟任务；将计算密集型的 LLM 任务卸载到 CPU 既不现实也不合理[2]。由于功耗、散热和对其他应用影响的考虑，CPU 在实际部署中通常被限制为单线程执行 LLM。同样，虽然边缘设备通常配备不错的 GPU，通过 OpenCL 在 GPU 上执行模型是一个可行的方向，但 GPU 也负责实时 UI 渲染。将其资源分配给 LLM 计算会显著降低用户体验。因此，将所有 LLM 任务（如预填充、解码和 ViT）统一在低功耗 NPU 上执行尤为重要。

在 NPU 上进行推理（以下简称"NPU"均指 Qualcomm 的 NPU）面临以下困难：

- **解码速度慢**：预填充阶段通常很快，但解码阶段相对较慢。这主要是因为较小的计算负载无法充分利用 NPU 的计算单元，使得 LLM 推理受限于内存带宽。

- **全整数计算中的严重精度损失**：NPU 上的所有算子都期望输入和输出使用 Per-Tensor Int 量化以获得最大性能。然而，全整数 Per-Tensor 量化会导致 LLM 的性能显著下降[3]。由于 NPU 内部定点计算的特性，SiLU、RMSNorm 和 RoPE 等算子需要整数输入和输出。具体来说，RoPE 需要分解为一系列逐元素算子，每个算子都需要整数输入和输出。我们有一些与 NPU 友好量化相关的最新工作，敬请期待。

- **在 NPU 静态图上实现 LLM 动态形状的困难**：Qnn 计算图是离线构建的，但 LLM 的自回归推理在注意力机制中涉及动态形状，需要大量填充，这会产生性能开销。

在 MLLM Qnn AOT 的实现过程中，我们遇到了许多技术挑战，详细内容在附录中阐述。整个适配 Qnn AOT 模式的过程充满困难——团队对 Qnn 的文档和实现、量化算法的准确性以及 MLLM 中 AOT 编译堆栈的实现缺乏足够的信任，导致了"猜疑链"。

![图1：谁是卧底？是 Qnn、量化算法，还是 MLLM Qnn AOT？](https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/figure1.png)

根本原因在于 Qnn 软件栈的封闭性及其不完整或错误的文档。Qnn 内部计算图的黑盒性质使得调试极其困难，常常让我们怀疑问题是否出在 Qnn 自身的实现中。我们还发现了 Qnn RMSNorm 算子的描述与行为之间的不一致，以及量化方法描述的不一致。这些问题在附录中单独列出。

MLLM Qnn AOT 工作流程主要由三部分组成：
1. 使用 QDQ[4] 实现建模文件——这需要 Hugging Face Transformers 风格的 Python 建模文件和 MLLM 中的 C++ 建模文件。这两种建模文件的构建方法非常相似，AI 可以有效地处理它们。
2. 将量化模型导出为 MLLM 格式并编译模型的特定 mllm-aot-compiler。
3. 使用 mllm-aot-compiler 编译模型并使用 mllm-aot-runner 运行。

![图2：MLLM Qnn AOT 工作流程](https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/figure2.png)

在这次 MLLM Qnn AOT 实现中，AI 发挥了巨大作用，成为工作流程不可或缺的一部分。我们在建模层面暴露了许多 QDQ（量化、反量化）细节，而不是像 ExecuTorch 那样将其隐藏在编译器的注释阶段。核心哲学是：如果 AI 能做，为什么要向编译器隐藏？在前端暴露足够的细节使人类和 AI 都更容易阅读。一旦我们提供了实现良好的 Qwen3 建模脚本，AI 就可以轻松地为其他模型（如 Llama 或 Qwen2.5）生成建模文件。

最后，我们要感谢参与 MLLM Qnn AOT 开发的学生们。我们还要特别感谢 ExecuTorch 社区的 Qualcomm 后端实现。我们从 ExecuTorch 中获得了重要启发，其社区成员非常友好，对我们遇到的问题提供了回应和帮助。

> 虽然高通的 NPU 目前处于顶级水平，但其弱软件生态系统限制了开源开发者在其芯片上进行进一步工作。在被高通的 Qnn 折磨之后，我必须借用 Torvalds 的话来总结：XXXX 你，高通！

在本文中，我将首先解释为什么 NPU 期望输入和输出都是整数类型。然后，按照 MLLM Qnn AOT 工作流程，依次介绍量化算法配置、QDQ 建模文件编写、MLLM IR、Qnn AOT 生成和 Qnn AOT 运行时。

---

## 1.2 为什么需要整数输入和输出？

在移动 AI 开发中（特别是使用 SNPE 或 QNN SDK 时），开发者经常会遇到一个刚性要求：模型必须量化，且 NPU 强烈偏好 Int8/Uint8 格式的输入和输出。鉴于现代移动 CPU 和 GPU 具有如此强大的浮点性能，为什么 Hexagon NPU 坚持"返璞归真"使用定点计算？为什么连输入和输出都被锁定为整数？这可能是由于两个原因：
1. 卷积网络的历史惯性
2. NPU 追求极致能效（TOPS/Watt）的设计目标

让我们以一个基本算子 Per-Tensor Uint8 逐元素乘法为例，解构底层的定点逻辑。

我们想要对两个张量 $A$ 和 $B$ 进行逐元素乘法得到 $C$：

$$C = A \odot B$$

然而，在 NPU 内部，我们没有真正的浮点值（$A_{real}, B_{real}$），只有量化后的整数（$A_q, B_q$）。根据 Per-Tensor 量化公式（所有元素共享一个 Scale 和 Zero-point）：

$$A_{real} = S_A \cdot (A_q - Z_A)$$

其中：
- $A_{real}$：真实浮点值
- $S_A$：缩放因子（通常是 float32）
- $A_q$：量化整数（int/uint8）
- $Z_A$：零点（int/uint8）

将公式代入乘法运算：

$$C_{real} = S_A(A_q - Z_A) \cdot S_B(B_q - Z_B) = S_C(C_q - Z_C)$$

我们的目标是找到 NPU 需要输出的整数 $C_q$。重新排列项得到核心计算公式：

$$C_q = \frac{S_A \cdot S_B}{S_C} \cdot (A_q - Z_A)(B_q - Z_B) + Z_C$$

注意标记为 $\frac{S_A \cdot S_B}{S_C}$ 的项：

$$M = \frac{S_A \cdot S_B}{S_C}$$

$S_A, S_B, S_C$ 都是浮点数，所以计算出的 $M$ 也是浮点数（例如 $0.00392157$）。如果 NPU 直接计算这个公式，它将需要一个内置的浮点乘法器来处理 $M$，这违背了全定点计算的目的。

因此，NPU 执行**定点重缩放（Fixed-point Rescaling）**。

NPU 将浮点 $M$ 近似为"一个整数乘数 + 右移操作"：

$$M \approx \frac{\text{Multiplier}}{2^{\text{Shift}}}$$

其中 Multiplier 是一个大整数（例如 int32），Shift 是位移量。因此，整个计算过程变成纯整数运算：

1. **输入准备**：NPU 读取 Int8 $A_q$ 和 $B_q$（这就是输入必须是整数的原因，否则第一步就会失败）。
2. **整数减法**：$(A_q - Z_A)$。
3. **整数乘法**：$(A_q - Z_A)(B_q - Z_B)$（结果可能是 int16 或 int32）。
4. **定点重缩放（关键步骤）**：$\text{Multiplier} \cdot \text{Product} \gg \text{Shift}$。这里用整数乘法和移位代替浮点乘法。
5. **添加零点**：$+ Z_C$。
6. **饱和**：将结果限制在 $[0, 255]$ 范围内并输出 $C_q$。

你可能认为 $M = \frac{\text{Multiplier}}{2^{\text{Shift}}}$ 只是另一种写法，但实际上它是一种有损变换，不是数学等价。

数学上，浮点 $M$ 的小数位（例如 $0.00392157$）理论上可以无限延伸。然而，在硬件中，"Multiplier" 通常被限制为 32 位整数（Int32）。

$$\text{Multiplier} = \text{round}(M \cdot 2^{\text{Shift}})$$

这里的 round 操作强制丢弃 $M \cdot 2^{\text{Shift}}$ 结果的小数部分。这引入了不可避免的量化误差。

假设真实比例 $M = 0.1$。由于硬件要求 Multiplier 为整数，让我们尝试用不同的 Shift 值表示：

**尝试 1（Shift=8）**：
$$\text{Multiplier} = \text{round}(0.1 \cdot 2^8) = \text{round}(25.6) = 26$$

四舍五入后，Multiplier = 26。还原回去：$\frac{26}{256} = 0.1015625$。误差约为 1.5%。

**尝试 2（Shift=31，32 位整数的极限）**：
$$\text{Multiplier} = \text{round}(0.1 \cdot 2^{31}) = \text{round}(214748364.8) = 214748365$$

四舍五入后，Multiplier = 214748365。还原回去：$\frac{214748365}{2^{31}} = 0.10000000046566129$。误差极小，但仍然存在。

这意味着普通 FakeQuant 的结果仍然无法完全模拟 Qnn 的计算精度误差！算子越多，损失越大！

---

## 1.3 量化算法

在 MLLM 中，我们实现的默认量化配置是 W4A16KV8，详细说明见下表：

**表1：MLLM 默认量化配置 W4A16KV8 说明**

| 张量类型 | 量化配置 | 精度 |
|---------|---------|------|
| Linear 权重 | per-block, block size(16/32), symmetric | int4 |
| RMSNorm 权重 | per-tensor, asymmetric | uint16 |
| RoPE 嵌入权重 | per-tensor, asymmetric | uint16 |
| Attention Sink 权重 | per-tensor, asymmetric | uint16 |
| 激活值 | per-tensor, asymmetric | uint16 |
| KV Cache | per-tensor, symmetric | uint8 |

### 1.3.1 LPBQ

LPBQ 代表低功耗块量化（Low Power Block Quantization）。它是高通为边缘硬件（特别是 Hexagon NPU/DSP）设计的细粒度量化方案。

传统的量化粒度通常有两种：
- **Per-Tensor**：整个层共享一个 Scale 因子；最快但精度最差。
- **Per-Channel**：每个输出通道有自己的 Scale 因子；精度更好，是 CNN 的标准。

LPBQ 引入了"块"的概念。它将张量分成更小的块，并为每个块独立计算量化参数。

以 Linear 为例，对于 Linear 算子，权重通常表示为 $[O, I]$（输出通道，输入通道）或 $[I, O]$ 矩阵。在 DSP/NPU 的低层实现中，权重通常使用 HWIO 格式来优化向量化加载。

对于 Linear 层：
- H（高度）= 1
- W（宽度）= 1
- I（输入通道）：规约维度（求和维度）
- O（输出通道）：独立计算维度

LPBQ 在 I（输入通道）维度上执行标准的逐块量化，产生 fp32 Scales 和 int32 Zero Points。然后，在 O（输出通道）维度上对所有块的 Scales 进行二级量化。量化后，每个块的 Scale 为 uint4，而 O（输出通道）上的 Scale 保持 fp32 精度。

### 1.3.2 特殊 Observer 约束

在量化过程中，Observer 的作用是收集张量的数值分布（Min/Max 或直方图），并用它来计算量化参数 Scale ($S$) 和 Zero Point ($Z$)。然而，并非所有 Observer 都能"自由"确定这些参数。为了确保数值稳定性或满足硬件约束，我们必须在以下情况下施加特殊限制：

**1. Epsilon 约束以防止除零错误**

Scale 的计算公式通常是 $S = \frac{\text{Max} - \text{Min}}{2^n - 1}$。当观察到的数值变化极小时（例如 $\text{Max} - \text{Min} < 10^{-7}$），分母可能接近零，导致计算的 Scale 爆炸或变为 NaN。

为了数值稳定性，我们必须将 $\text{Max} - \text{Min}$ 的最小值限制为一个 $\epsilon$。对于不同的量化位宽，这个阈值通常设置为：
- INT8：$\epsilon = 1.0 / (2^{11})$
- INT16：$\epsilon = 1.0 / (2^{19})$

这确保即使在平坦区域，Scale 也保持在合理的浮点范围内。

**2. Sigmoid/Tanh 等算子的固定 ZP**

对于具有固定输出范围的激活函数，如 Sigmoid 或 Tanh（Sigmoid 输出始终在 $(0, 1)$ 范围内）。

量化输出通常需要固定的 Zero Point。例如，在非对称量化（uint8）中，可能强制：
$$Z = 0$$

或者根据硬件实现固定为另一个特定整数值，而不是随数据的动态分布变化。

**3. Concat 算子的 Observer 共享（共享 Scale 和 ZP）**

Concat 操作涉及将多个张量的数据移动到单个连续的物理内存块中。

如果输入到 Concat 的多个张量具有不同的 Scales 和 ZPs，它们不能直接在物理值上连接（例如，张量 A 中的值 5 代表实数 0.5，而张量 B 中的值 5 代表实数 2.0，连接时会导致物理歧义）。

为了避免在 Concat 之前插入额外的 Requantize（重新对齐）操作的计算开销，通常强制要求所有输入张量和输出张量共享同一个 Observer，即：
$$S_1 = S_2 = ... = S_n = S_{out}, \quad Z_1 = Z_2 = ... = Z_n = Z_{out}$$

### 1.3.3 SpinQuant

![图3：SpinQuant (Liu et al., 2024)](https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/figure3.png)

SpinQuant 通过引入正交旋转矩阵，有效减少了权重和激活层中异常值的影响，且无需训练。这种方法已在 ExecuTorch 的 Qualcomm 后端中实现，并已成为事实上的行业标准。然而，当前的 MLLM AOT 框架尚不支持旋转变换量化，这将是我们未来工作的重点。

---

## 1.4 QDQ 建模

鉴于 NPU 算子需要整数输入和输出才能达到峰值性能，我们需要在每个算子前后进行 QDQ。这引出了一个问题：如何快速插入正确的 QDQ 算子？ExecuTorch 使用某些 pass 为每个算子标注量化设置，并根据这些设置插入 FakeQuant 节点或 Observers。

然而，实现一个完整复杂的模式匹配系统非常耗时。因此，MLLM 选择了一条不同的路径：直接在建模文件中显式声明 QDQ 节点，并显式声明每个算子输入输出使用的类型。

让我们先看看如何在 Python 中插入 QDQ 节点[5]。pymllm 提供了一系列 QDQ 类来协助。QLinearLPBQ 默认为 W4A16 精度：

```python
from pymllm.backends.qualcomm.transformers.core.qlinear import (
    QLinearLPBQ,
)
from pymllm.backends.qualcomm.transformers.core.qdq import (
    ActivationQDQ,
    FixedActivationQDQ,
)

class Qwen3MLP(nn.Module):
    def __init__(self, config):
        super().__init__()
        self.config = config
        self.hidden_size = config.hidden_size
        self.intermediate_size = config.intermediate_size
        self.gate_proj = QLinearLPBQ(
            self.hidden_size, self.intermediate_size, bias=False, block_size=16
        )
        self.up_proj = QLinearLPBQ(
            self.hidden_size, self.intermediate_size, bias=False, block_size=16
        )
        self.down_proj = QLinearLPBQ(
            self.intermediate_size, self.hidden_size, bias=False, block_size=16
        )
        # QDQ
        self.up_proj_input_qdq = ActivationQDQ(bits=16)
        self.up_proj_output_qdq = ActivationQDQ(bits=16)
        self.gate_proj_output_qdq = ActivationQDQ(bits=16)
        self.act_output_qdq = ActivationQDQ(bits=16)
        self.down_proj_input_qdq = ActivationQDQ(bits=16)
        # For sigmoid output: scale = 1 / (q_max - q_min + 1), zp = 0
        # For 16-bit: q_min = 0, q_max = 65535
        sigmoid_scale = 1.0 / (65535 - 0 + 1)  # 1 / 65536
        self.sigmoid_output_qdq = FixedActivationQDQ(
            scale=sigmoid_scale, zero_point=0, bits=16
        )

    def forward(self, x):
        x = self.up_proj_input_qdq(x)
        up_result = self.up_proj_output_qdq(self.up_proj(x))
        gate_result = self.gate_proj_output_qdq(self.gate_proj(x))
        # SiLU
        gate_result = self.act_output_qdq(
            gate_result * self.sigmoid_output_qdq(F.sigmoid(gate_result))
        )
        o = self.down_proj_input_qdq(gate_result * up_result)
        o = self.down_proj(o)
        return o
```

现在让我们看看标准建模文件（不带 QDQ）在 MLLM 中是如何编写的。在 MLLM 中，我们使用 C++ 实现的建模文件来表示图。不要惊慌，我们已经广泛包装了 C++ API，提供了类似 Torch 的体验。例如，一个常见的 MLP 层看起来像这样：

```cpp
class Qwen3MLP final : public nn::Module {
  nn::Linear gate_proj_;
  nn::Linear up_proj_;
  nn::Linear down_proj_;
  nn::SiLU silu_;

 public:
  Qwen3MLP() = default;
  Qwen3MLP(const std::string& name, const Qwen3Config& cfg) : nn::Module(name) {
    gate_proj_ = reg<nn::Linear>("gate_proj", cfg.hidden_size, cfg.intermediate_size, false, cfg.linear_impl_type);
    silu_ = reg<nn::SiLU>("act");
    up_proj_ = reg<nn::Linear>("up_proj", cfg.hidden_size, cfg.intermediate_size, false, cfg.linear_impl_type);
    down_proj_ = reg<nn::Linear>("down_proj", cfg.intermediate_size, cfg.hidden_size, false, cfg.linear_impl_type);
  }

  std::vector<Tensor> forward(const std::vector<Tensor>& inputs, const std::vector<AnyValue>& args) override {
    auto x = gate_proj_(inputs[0]);
    x = silu_(x);
    auto y = up_proj_(inputs[0]);
    x = x * y;
    x = down_proj_(x);
    return {x};
  }
};
```

用户可以使用这些简单的 API 构建自己的 LLM 结构。

添加 QDQ 后，MLP 层实现如下[6]。在这个例子中，我们将 Linear 替换为 Conv2D 以加速推理。ptq::QDQ 的第三个参数是 Python 建模文件中 FakeQuant 模块的实例化名称：

```cpp
class Qwen3MLP final : public nn::Module {
  nn::Conv2D gate_proj_;
  nn::Conv2D up_proj_;
  nn::Conv2D down_proj_;
  nn::SiLU silu_;
  int hidden_size_;
  int intermediate_size_;

 public:
  Qwen3MLP() = default;
  Qwen3MLP(const std::string& name, const Qwen3Config& cfg) : nn::Module(name) {
    gate_proj_ = reg<nn::Conv2D>("gate_proj", cfg.hidden_size, cfg.intermediate_size, CONV2D_PROPERTY);
    silu_ = reg<nn::SiLU>("act");
    up_proj_ = reg<nn::Conv2D>("up_proj", cfg.hidden_size, cfg.intermediate_size, CONV2D_PROPERTY);
    down_proj_ = reg<nn::Conv2D>("down_proj", cfg.intermediate_size, cfg.hidden_size, CONV2D_PROPERTY);
    hidden_size_ = cfg.hidden_size;
    intermediate_size_ = cfg.intermediate_size;
  }

  std::vector<Tensor> forward(const std::vector<Tensor>& inputs, const std::vector<AnyValue>& args) override {
    auto x = inputs[0];
    x = ptq::QDQ(this, x, "up_proj_input_qdq");
    x = x.view({1, 1, -1, hidden_size_}, true);
    auto up_result = ptq::QDQ(this, up_proj_(x), "up_proj_output_qdq").view({1, -1, intermediate_size_}, true);
    auto gate_result = ptq::QDQ(this, gate_proj_(x), "gate_proj_output_qdq").view({1, -1, intermediate_size_}, true);
    // SiLU
    gate_result = ptq::QDQ(this, (gate_result * ptq::QDQ(this, nn::functional::sigmoid(gate_result), "sigmoid_output_qdq")),
                           "act_output_qdq");
    auto o = ptq::QDQ(this, gate_result * up_result, "down_proj_input_qdq");
    o = o.view({1, 1, -1, intermediate_size_}, true);
    o = down_proj_(o).view({1, -1, hidden_size_}, true);
    return {o};
  }
};
```

---

## 1.5 MLLM IR

MLLM 的 IR 是 MLLM 中建模文件的忠实表示。MLLM IR 是一种静态图、非 SSA（静态单赋值）IR。我们选择不使用 SSA，因为从工程角度来看，计算图 IR 更简单且实现更快。此外，由于计算图由相互连接的节点组成，所有内存分配都表示为张量，SSA 的必要性较小。对于 MLP，MLLM 生成以下 IR[7]。这个例子来自 Qwen2 VL 模型：

```mlir
graph.SubGraphOp @model.layers.6.mlp <CPU> {
    (%1454:tensor<[1, 192, 1536], Float32, CPU>) -> (%1459:tensor<[1, 192, 1536], Float32, CPU>) {
        linalg.CPU.LinearOp(%1454:tensor<[1, 192, 1536], Float32, CPU>) -> (%1455:tensor<[1, 192, 8960], Float32, CPU>)
        linalg.CPU.SiLUOp(%1455:tensor<[1, 192, 8960], Float32, CPU>) -> (%1456:tensor<[1, 192, 8960], Float32, CPU>)
        linalg.CPU.LinearOp(%1454:tensor<[1, 192, 1536], Float32, CPU>) -> (%1457:tensor<[1, 192, 8960], Float32, CPU>)
        linalg.CPU.MulOp(%1456:tensor<[1, 192, 8960], Float32, CPU>, %1457:tensor<[1, 192, 8960], Float32, CPU>) -> (%1458:tensor<[1, 192, 8960], Float32, CPU>)
        linalg.CPU.LinearOp(%1458:tensor<[1, 192, 8960], Float32, CPU>) -> (%1459:tensor<[1, 192, 1536], Float32, CPU>)
        cf.ReturnOp (%1459:tensor<[1, 192, 1536], Float32, CPU>) -> ()
    }
}
```

上面的 IR 是通过追踪获得的最简单情况。为了确保量化设置和模型结构符合 Qnn 限制，MLLM Qnn AOT 模式实现了一系列 pass 来协助 IR 转换。这些 pass 如下（表中的顺序是实际执行顺序）：

**表2：MLLM Qnn AOT Pass 说明**

| Pass 名称 | 功能 | 约束 |
|----------|------|------|
| MarkQnnGraphPass | 根据提供的配置文件标记要在 NPU 上执行的 Graph Ops 和一些 Linalg Ops | |
| OpNamingPass | 在追踪期间为匿名算子（例如来自 nn.functional 的）分配唯一名称 | |
| MergeLLMHeadIntoMainGraphPass | 将 LM Head 算子移入模型图，因为它通常独立于其他 Graph Ops | 仅适用于 LLM |
| LLMQuantRecipePass | 根据前端量化类型推断每个算子的 QDQ 是否可以重用（量化部分详细说明） | |
| PTQPass | 通过 Quant Recipe 将 Scales 和 Zero Points 从参数映射到每个激活和权重。如果存在常量值则进行量化 | |
| SplitLLMGraphPass | 如果 LLM 超过 4GB，将图分割到不同的上下文。同时将所有子图扁平化为单个大图 | 目前仅支持单图；未来工作将改进此功能 |
| MarkTensorIOPass | 将输入和输出标记为 IO | |
| LLM2QnnLoweringPass | 遍历 IR 并使用 Qnn 的离线图构建 API 构建图 | |

---

## 1.6 Qnn AOT 生成

我们扩展了原始的 Qnn 后端[8]。MLLM Qnn 后端的第一个版本在移动设备上准备 Qnn 图，并包装了一个可在 X86 上使用的编译环境。用户可以通过在编译期间为 target_machine 指定硬件参数来为不同设备编译 Qnn 图。

```json
{
    "target_machine": {
        "htp_arch": "V75",
        "htp_chipset": "SM8650",
        "htp_try_best_performance": "HtpBurst",
        "htp_security_pd_session": "HtpSignedPd",
        "htp_vtcm_capability_in_mb": 8
    }
}
```

如上面的 JSON 所示，在 X86 上编译 Qnn 图时，必须向 MLLM 的 AOTEnv 提供 HTP 芯片组和架构等硬件相关信息。

---

## 1.7 全 NPU 执行

在 NPU 上执行 LLM 的预填充和解码阶段是一个挑战。当前 MLLM AOT 解决方案是编译两个独立的计算图：一个 chunk 大小为 32，另一个 chunk 大小为 1。这两个图分别用于预填充和解码阶段。

### 1.7.1 KV Cache 管理

我们学习并实现了 ExecuTorch 中使用的 KV Cache 管理方法。

![图4：KV Cache 管理，官方 ExecuTorch 分析](https://chenghuawang.github.io/News/2026-01-29-mllm-qnn-aot-support-en/figure4.png)

所有 KV Caches 都是固定长度的，Key 形状为 [B, H, D, S]，Value 形状为 [B, H, S, D]。对于上下文长度：

每次注意力计算时，新计算的 chunk 直接追加到 Key 和 Value 的末尾，形成长度为"context_length"的 Key 和 Value。因此，因果掩码（Causal Mask）也需要调整，如下所示[9]。引用 ExecuTorch Python 注释：

**1. 完全注意力（Full Attention）**

```
Step = 0
0| 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0
1| 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0
2| 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0
3| 0 0 0 0 0 0 0 0 0 0 1 1 1 1 0
4| 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1

Step = 1
0| 1 1 1 1 1 0 0 0 0 0 1 0 0 0 0
1| 1 1 1 1 1 0 0 0 0 0 1 1 0 0 0
2| 1 1 1 1 1 0 0 0 0 0 1 1 1 0 0
3| 1 1 1 1 1 0 0 0 0 0 1 1 1 1 0
4| 1 1 1 1 1 0 0 0 0 0 1 1 1 1 1

Step = 2
0| 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0
1| 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0
2| 1 1 1 1 1 1 1 1 1 1 1 1 1 0 0
3| 1 1 1 1 1 1 1 1 1 1 1 1 1 1 0
4| 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
```

**2. 滑动窗口注意力（Sliding Window Attention）**

```
Step = 0
0| 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0
1| 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0
2| 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0
3| 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0
4| 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1

Step = 1
0| 0 0 0 1 1 0 0 0 0 0 1 0 0 0 0
1| 0 0 0 0 1 0 0 0 0 0 1 1 0 0 0
2| 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0
3| 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0
4| 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1

Step = 2
0| 0 0 0 0 0 0 0 0 1 1 1 0 0 0 0
1| 0 0 0 0 0 0 0 0 0 1 1 1 0 0 0
2| 0 0 0 0 0 0 0 0 0 0 1 1 1 0 0
3| 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0
4| 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1
```

### 1.7.2 多图选择

由于 NPU 使用静态计算图架构，计算过程必须事先完整定义。以注意力机制为例，每次计算必须填充到最大长度（例如 1024），这导致大量冗余计算和时间开销增加。为了解决这个问题，可以采用折中方案：预先准备多个不同形状的 Qnn 图（即不同输入长度的图），执行时动态选择最匹配当前输入长度的图（最小化计算浪费）。这在性能和灵活性之间取得了平衡。

---

## 1.8 用于 LLM 的 Qnn 模型运行时

Qnn 模型运行时的实现相对简单，主要涉及通过 Qnn Graph Execute API 执行图。然而，需要注意和改进的一点是，从预填充阶段切换到解码阶段需要重新排序所有 KV Caches，这涉及大量数据复制。

重新排序是必要的，因为为 Key 和 Value 计算的小 chunk 被追加到 Past Key 和 Past Value 的末尾。然而，预填充阶段的 Key 占用 chunk_size 空间，而解码阶段的 Key 只需要 chunk_size = 1。由于 Key 格式为 [B, H, D, S]，解码阶段所需的 Past Key 无法直接通过指针偏移访问，因此需要在从预填充切换到解码时进行重新排序。

---

## 1.9 性能

我们在 SM8650 设备上进行了实验。

**表3：SM8650 上的 LLM 性能，w4a16kv8**

A: 预填充 256 tokens，解码 128 tokens  
B: 预填充 512 tokens，解码 256 tokens  
C: 预填充 640 tokens，解码 128 tokens

| 模型 | 预填充 (token/s) | 解码 (token/s) |
|------|-----------------|---------------|
| Qwen2.5 3B, A | 512.75 | 18.29 |
| Qwen2.5 3B, B | 545.62 | 18.11 |
| Qwen3 1.7B, C | 758.28 | 25.84 |

---

## 1.10 总结

MLLM Qnn AOT 框架通过统一的中间表示、显式 QDQ 建模和创新的双图执行策略，成功解决了在 Qualcomm NPU 上高效部署 LLM 的关键挑战，实现了高性能的端侧推理。该工作流程集成了量化、编译和运行时，为开发者提供了便捷的部署路径。未来的工作将专注于支持更先进的量化方法（如 SpinQuant）并进一步优化多图选择策略。

---

## 1.11 附录

### 1.11.1 Quantize/Dequantize、Cast 和 Convert

高通提供了一个 Convert Op 来协助在量化类型之间转换，无需 Quantize 和 Dequantize 的组合。Cast Op 不考虑张量是否具有量化类型；它是一种强制类型转换。

### 1.11.2 QNN 中的 Zero Point 应为负数

尽管高通文档中的许多示例显示正偏移，但高通的量化方法实际上应遵循以下公式：

$$A_{real} = S \cdot (A_q + Z)$$

### 1.11.3 短深度卷积上的 HMX 启用

谨慎使用 `QNN_HTP_GRAPH_CONFIG_OPTION_SHORT_DEPTH_CONV_ON_HMX_OFF` 标志。

```cpp
p_custom_config = (QnnHtpGraph_CustomConfig_t*)malloc(sizeof(QnnHtpGraph_CustomConfig_t));
p_custom_config->option = QNN_HTP_GRAPH_CONFIG_OPTION_SHORT_DEPTH_CONV_ON_HMX_OFF;
p_custom_config->shortDepthConvOnHmxOff = true;
htp_graph_configs.push_back(static_cast<QnnGraph_CustomConfig_t>(p_custom_config));
```

将优化级别设置为 3 可能会提供一些性能提升：

```cpp
p_custom_config = (QnnHtpGraph_CustomConfig_t*)malloc(sizeof(QnnHtpGraph_CustomConfig_t));
p_custom_config->option = QNN_HTP_GRAPH_CONFIG_OPTION_OPTIMIZATION;
p_custom_config->optimizationOption.type = QNN_HTP_GRAPH_OPTIMIZATION_TYPE_FINALIZE_OPTIMIZATION_FLAG;
p_custom_config->optimizationOption.floatValue = 3;
htp_graph_configs.push_back(static_cast<QnnGraph_CustomConfig_t>(p_custom_config));
```

### 1.11.4 LPBQ 打包

LPBQ 量化方法要求用户提供 int8 数组来表示 int4 权重。然后高通打包此数组。然而，高通的打包算法实现如下：

```
1byte = val1 | (val2 << 4)
```

在 MLLM 中，我们对 int8 数组执行与 0x0F 的按位与以获得干净的高四位。

Python 代码：
```python
weight_int4 = quantized_weight.to(torch.int8)
mask = torch.full(
    weight_int4.size(), 0x0F, dtype=torch.int8, device=weight_int4.device
)
weight_int4 = torch.bitwise_and(mask, weight_int4)
```

而不是以下方法：

```
1byte = (val1 & 0x0F) | ((val2 & 0x0F) << 4)
```

---

## 补充说明

- [1] 使用 W4A16KV8 量化配置，chunk=32，pad=1024
- [2] 由于功耗、散热和对其他应用影响的考虑，CPU 在实际部署中通常被限制为单线程执行 LLM
- [3] 由于 NPU 内部定点计算的特性，SiLU、RMSNorm 和 RoPE 等算子需要整数输入和输出。具体来说，RoPE 需要分解为一系列逐元素算子，每个算子都需要整数输入和输出。我们有一些与 NPU 友好量化相关的最新工作，敬请期待。
- [4] This requires both Python modeling files in the Hugging Face Transformers style and C++ modeling files in MLLM. The model construction methods for these two are quite similar, and AI can handle them effectively.
- [5] pymllm 提供了一系列 QDQ 类来协助。QLinearLPBQ 默认为 W4A16 精度
- [6] 在这个例子中，我们将 Linear 替换为 Conv2D 以加速推理。ptq::QDQ 的第三个参数是 Python 建模文件中 FakeQuant 模块的实例化名称
- [7] 这个例子来自 Qwen2 VL 模型
- [8] MLLM Qnn 后端的第一个版本在移动设备上准备 Qnn 图，并包装了一个可在 X86 上使用的编译环境。用户可以通过在编译期间为 target_machine 指定硬件参数来为不同设备编译 Qnn 图
- [9] 引用 ExecuTorch Python 注释

---

**引用文献**

Liu, Z., Zhao, C., Fedorov, I., Soran, B., Choudhary, D., Krishnamoorthi, R., Chandra, V., Tian, Y., & Blankevoort, T. (2024). Spinquant: Llm quantization with learned rotations. Arxiv Preprint Arxiv:2405.16406.
