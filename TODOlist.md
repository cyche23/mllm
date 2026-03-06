1. 参考debelopment_guide.md编写.sh脚本文件，用于在对mllm项目进行移动端实际部署开发时一次性调用，可以一次性完成端到端代码测试，提升开发便利性；此外，查找相关文档资料，将一般的qnn_android的编译部署流程总结后写进debelopment_guide.md，并同样编写.sh脚本文件用于端到端测试。
2. 尝试对mllm代码进行性能、内存、带宽占用等测试，重点参考https://ubiquitouslearning.github.io/mllm/、QNN2.40官方文档/opt/qcom/aistack/qairt/2.40.0.251030/docs，关注debug logging以及其他可供profilling、benchmark的接口和参数，熟悉代码特性。
3. 借助mllm接口，编写一系列简单的测试demo，对移动端NPU的带宽等进行测试；以及参考官方文档，尝试对NPU的DMA、VTCM等组件进行编程。并结合mllm的推理架构，尝试针对移动端NPU找出可以深入研究优化的方向。
4. 微观改进方向：对大模型的部分推理模块进行拆解，例如attention、mlp模块，尝试算子优化；宏观改进方向：在mllm基础上设计多模型并发的scheduler，尝试进行xpu调度，提升场景部署效率。                               