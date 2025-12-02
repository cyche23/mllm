#include "Backend.hpp"
#include "QNNBackend.hpp"
#include "QNNMemoryManager.hpp"
#include "memory/SystemMemoryManager.hpp"

namespace mllm {

class QNNBackendRegister : public BackendCreator {
public:
    Backend* create(BackendConfig config) {
        shared_ptr<MemoryManager> mm = nullptr;
        mm = std::make_shared<QNNMemoryManager>();
        return new QNNBackend(mm);
        // 有了QNNBackendRegister的实例后，通过调用create方法即可创建QNNBackend实例（进一步封装的过程在Backend.cpp中，具体创建QNNBackend实例在Module.hpp 174-179）
    };
};

void registerQNNBackendCreator() {
    InsertBackendCreatorMap(MLLM_QNN, std::make_shared<QNNBackendRegister>());// make_shared:创建智能指针及QNNBackendRegister的对象实例
}

} // namespace mllm