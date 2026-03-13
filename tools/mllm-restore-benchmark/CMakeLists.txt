add_executable(mllm-restore-benchmark main.cpp)
target_include_directories(
  mllm-restore-benchmark
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../..
    ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/json)

enable_testing()

add_test(
  NAME mllm-restore-benchmark-smoke
  COMMAND mllm-restore-benchmark --list)
set_tests_properties(
  mllm-restore-benchmark-smoke
  PROPERTIES PASS_REGULAR_EXPRESSION "\"supported_scenarios\"")

add_test(
  NAME mllm-restore-benchmark-functional
  COMMAND mllm-restore-benchmark
          --scenario
          direct-kv-scaffold
          --backend
          host-sim
          --payload-bytes
          4096
          --iterations
          2
          --touch-stride
          64)
set_tests_properties(
  mllm-restore-benchmark-functional
  PROPERTIES PASS_REGULAR_EXPRESSION "\"result\":\"ok\"")

add_test(
  NAME mllm-restore-benchmark-regression
  COMMAND mllm-restore-benchmark
          --scenario
          direct-kv-scaffold
          --backend
          host-sim
          --payload-bytes
          1024
          --iterations
          1)
set_tests_properties(
  mllm-restore-benchmark-regression
  PROPERTIES PASS_REGULAR_EXPRESSION "\"stage\":\"restore_scaffold_total\"")
