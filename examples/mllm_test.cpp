// Simple QNN operator test for HTP using mllm QNN backend
// Builds a tiny graph with one LLaMAMul node and executes it on QNN

#include "Module.hpp"
#include "Tensor.hpp"
#include "QNNBackend.hpp"
#include "Types.hpp"
#include <iostream>
#include <memory>
#include <vector>
#include<unistd.h>

using namespace mllm;

int main() {
#ifdef USE_QNN
    // Initialize QNN backend
    Module::initBackend(MLLM_QNN);
    auto qnnBackend = static_cast<QNNBackend *>(Backend::global_backends[MLLM_QNN].get());

    // Create two input tensors (batch=1, head=1, seq=1, dim=4)
    auto in0 = std::make_shared<Tensor>(qnnBackend);
    auto in1 = std::make_shared<Tensor>(qnnBackend);
    auto out = std::make_shared<Tensor>(qnnBackend);

    in0->setName("input0");
    in1->setName("input1");
    out->setName("out0");

    // in0->reshape(1, 1, 1, 32);
    // in1->reshape(1, 1, 1, 32);
    // out->reshape(1, 1, 1, 32);
    in0->reshape(1, 1, 1024, 1024);
    in1->reshape(1, 1, 1024, 1024);
    out->reshape(1, 1, 1024, 1024);

    in0->setDtype(MLLM_TYPE_F32);
    in1->setDtype(MLLM_TYPE_F32);
    out->setDtype(MLLM_TYPE_F32);

    in0->alloc();
    in1->alloc();
    out->alloc();

    // Fill inputs with simple values
    float *p0 = in0->hostPtr<float>();
    float *p1 = in1->hostPtr<float>();
    for (int i = 0; i < 32; ++i) {
        p0[i] = 1.0f + i; // [1,2,3,4]
        p1[i] = 2.0f + i; // [2,3,4,5]
    }

    // Prepare vectors for backend setup
    std::vector<std::shared_ptr<Tensor>> inputs{in0, in1};
    std::vector<std::shared_ptr<Tensor>> outputs{out};
    std::string graphName = "test_qnn_mul_graph";
    auto outputName = out->name();

    // onSetUpStart will create a QNN model and add input tensors
    qnnBackend->onSetUpStart(inputs, outputs, graphName);

    // Prepare QNN output tensor description (similar to QNNMul op)
    uint32_t dimensionsOutput[4];
    dimensionsOutput[0] = static_cast<uint32_t>(out->batch());
    dimensionsOutput[1] = static_cast<uint32_t>(out->sequence());
    dimensionsOutput[2] = static_cast<uint32_t>(out->head());
    dimensionsOutput[3] = static_cast<uint32_t>(out->dimension());

    // Tell backend where to write outputs
    qnnBackend->pushOutputBuffers(out->hostPtr<uint8_t>());

    Qnn_Tensor_t outputTensor = {QNN_TENSOR_VERSION_1,
                                 {.v1 = {.id = 0,
                                         .name = outputName.c_str(),
                                         .type = QNN_TENSOR_TYPE_APP_READ,
                                         .dataFormat = QNN_TENSOR_DATA_FORMAT_FLAT_BUFFER,
                                         .dataType = QNN_DATATYPE_FLOAT_32,
                                         .quantizeParams = {QNN_DEFINITION_UNDEFINED,
                                                            QNN_QUANTIZATION_ENCODING_UNDEFINED,
                                                            {.scaleOffsetEncoding = {.scale = 0.0f, .offset = 0}}},
                                         .rank = 4,
                                         // .dimensions = {dimensionsOutput[0], dimensionsOutput[1], dimensionsOutput[2], dimensionsOutput[3]},
                                         .dimensions = dimensionsOutput,
                                         .memType = QNN_TENSORMEMTYPE_RAW,
                                         .clientBuf = {.data = nullptr, .dataSize = 0}}}};

    // Add LLaMAMul node (package name must match op package built into HTP binary)
    qnnBackend->graphAddNode("testmul", "LLaMAMul", {in0->name(), in1->name()}, std::vector<Qnn_Tensor_t>{outputTensor}, std::vector<Qnn_Param_t>{}, "LLaMAPackage");
    // qnnBackend->graphAddNode("testmul", "MatMul", {in0->name(), in1->name()}, std::vector<Qnn_Tensor_t>{outputTensor}, std::vector<Qnn_Param_t>{}, "qti.aisw");

    // Finalize graph and register outputs
    qnnBackend->onSetUpEnd(inputs, outputs, graphName);
    
        std::cout << "Finalize Graph Finish "<<std::endl;

    // Diagnostic: print out tensor info before execute
    std::cout << "[DIAG] out host ptr: " << static_cast<void *>(out->hostPtr<float>()) << std::endl;
    std::cout << "[DIAG] out count: " << out->count() << ", size(bytes): " << out->size() << std::endl;
    if (out->hostPtr<float>() == nullptr) {
        std::cerr << "[DIAG] ERROR: out host pointer is NULL before execute" << std::endl;
    }

    // Execute the graph
    qnnBackend->onExecuteStart(inputs, outputs, graphName);
    
     std::cout << "Execute Graph Finish "<<std::endl;

     qnnBackend->onExecuteEnd(outputs, graphName);

    // Diagnostic after execute: check pointer and sample bytes
    std::cout << "[DIAG] after execute out host ptr: " << static_cast<void *>(out->hostPtr<float>()) << std::endl;
    std::cout << "[DIAG] after execute out count: " << out->count() << ", size(bytes): " << out->size() << std::endl;
    if (out->hostPtr<float>() == nullptr) {
        std::cerr << "[DIAG] ERROR: out host pointer is NULL after execute" << std::endl;
    }

    out->to(MLLM_CPU);

    // Read and print results
    // Errors occur:Aborted
    float *outp = out->hostPtr<float>();
    std::cout << "Result: ";
    for (int i = 0; i < 16; ++i) {
        std::cout << outp[i] << ' ';
    }
    std::cout<<std::endl;


#else
    std::cerr << "QNN support not enabled. Build with -D QNN=ON and proper QNN/Hexagon SDK." << std::endl;
#endif
    return 0;
}