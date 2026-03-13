// Copyright (c) MLLM Team.
// Licensed under the MIT License.

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

namespace {

constexpr const char* kTaskId = "T001";
constexpr const char* kDefaultScenario = "direct-kv-scaffold";
constexpr const char* kDefaultBackend = "host-sim";

struct ScenarioSpec {
  std::string name;
  std::string description;
  size_t default_payload_bytes;
};

struct BackendSpec {
  std::string name;
  std::string description;
};

struct BenchmarkConfig {
  std::string scenario;
  std::string backend;
  size_t payload_bytes;
  int iterations;
  size_t touch_stride;
};

struct BenchmarkResult {
  std::string stage;
  double latency_ms;
  uint64_t checksum;
  uint64_t bytes_copied;
};

struct CliOptions {
  bool show_help = false;
  bool list_only = false;
  bool scenario_explicit = false;
  bool backend_explicit = false;
  bool payload_bytes_explicit = false;
  std::string scenario = kDefaultScenario;
  std::string backend = kDefaultBackend;
  uint64_t payload_bytes = 1024 * 1024;
  int iterations = 1;
  uint64_t touch_stride = 64;
};

const std::unordered_map<std::string, ScenarioSpec>& scenarioRegistry() {
  static const std::unordered_map<std::string, ScenarioSpec> registry = {
      {kDefaultScenario,
       ScenarioSpec{
           .name = kDefaultScenario,
           .description = "Host-side scaffold for a direct KV restore baseline.",
           .default_payload_bytes = 1024 * 1024,
       }},
  };
  return registry;
}

const std::unordered_map<std::string, BackendSpec>& backendRegistry() {
  static const std::unordered_map<std::string, BackendSpec> registry = {
      {kDefaultBackend,
       BackendSpec{
           .name = kDefaultBackend,
           .description = "CPU-host scaffold backend with no QNN dependency.",
       }},
  };
  return registry;
}

[[nodiscard]] std::string makeRunId() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  return std::to_string(std::chrono::duration_cast<std::chrono::microseconds>(now).count());
}

[[nodiscard]] uint64_t touchPayload(const std::vector<uint8_t>& payload, size_t touch_stride) {
  const size_t stride = std::max<size_t>(touch_stride, 1);
  uint64_t checksum = 1469598103934665603ULL;
  for (size_t i = 0; i < payload.size(); i += stride) {
    checksum ^= payload[i];
    checksum *= 1099511628211ULL;
  }
  if (!payload.empty() && ((payload.size() - 1) % stride != 0)) {
    checksum ^= payload.back();
    checksum *= 1099511628211ULL;
  }
  return checksum;
}

BenchmarkResult runDirectKvScaffold(const BenchmarkConfig& config) {
  std::vector<uint8_t> source(config.payload_bytes);
  std::vector<uint8_t> restored(config.payload_bytes, 0);
  for (size_t i = 0; i < source.size(); ++i) {
    source[i] = static_cast<uint8_t>((i * 131U + 17U) & 0xFFU);
  }

  uint64_t checksum = 0;
  const auto start = std::chrono::steady_clock::now();
  for (int iteration = 0; iteration < config.iterations; ++iteration) {
    std::memcpy(restored.data(), source.data(), restored.size());
    checksum = (checksum * 1099511628211ULL) ^ touchPayload(restored, config.touch_stride) ^ static_cast<uint64_t>(iteration + 1);
  }
  const auto end = std::chrono::steady_clock::now();

  return BenchmarkResult{
      .stage = "restore_scaffold_total",
      .latency_ms =
          std::chrono::duration<double, std::milli>(end - start).count(),
      .checksum = checksum,
      .bytes_copied = static_cast<uint64_t>(config.payload_bytes) * static_cast<uint64_t>(config.iterations),
  };
}

[[nodiscard]] bool isSupportedScenario(const std::string& scenario_name) {
  return scenarioRegistry().find(scenario_name) != scenarioRegistry().end();
}

[[nodiscard]] bool isSupportedBackend(const std::string& backend_name) {
  return backendRegistry().find(backend_name) != backendRegistry().end();
}

void printList() {
  nlohmann::json output;
  output["task_id"] = kTaskId;
  output["supported_scenarios"] = nlohmann::json::array();
  for (const auto& [_, scenario] : scenarioRegistry()) {
    output["supported_scenarios"].push_back(
        {{"name", scenario.name},
         {"description", scenario.description},
         {"default_payload_bytes", scenario.default_payload_bytes}});
  }
  output["supported_backends"] = nlohmann::json::array();
  for (const auto& [_, backend] : backendRegistry()) {
    output["supported_backends"].push_back(
        {{"name", backend.name},
         {"description", backend.description}});
  }
  std::cout << output.dump() << '\n';
}

void printHelp() {
  std::cout
      << "Usage:\n"
      << "  mllm-restore-benchmark --list\n"
      << "  mllm-restore-benchmark --scenario <name> --backend <name> [--payload-bytes <n>] [--iterations <n>] [--touch-stride <n>]\n\n"
      << "Options:\n"
      << "  -h, --help          Show help message\n"
      << "  --list              List supported scenarios and backends\n"
      << "  --scenario          Restore benchmark scenario to run\n"
      << "  --backend           Restore benchmark backend to run\n"
      << "  --payload-bytes     Synthetic payload size in bytes\n"
      << "  --iterations        Number of restore iterations to execute\n"
      << "  --touch-stride      Stride used when touching restored bytes\n";
}

bool parseUInt64(const std::string& raw, uint64_t& out) {
  if (raw.empty()) {
    return false;
  }
  size_t parsed_chars = 0;
  unsigned long long parsed = 0;
  try {
    parsed = std::stoull(raw, &parsed_chars, 10);
  } catch (const std::exception&) {
    return false;
  }
  if (parsed_chars != raw.size()) {
    return false;
  }
  out = static_cast<uint64_t>(parsed);
  return true;
}

bool parseInt(const std::string& raw, int& out) {
  if (raw.empty()) {
    return false;
  }
  size_t parsed_chars = 0;
  long parsed = 0;
  try {
    parsed = std::stol(raw, &parsed_chars, 10);
  } catch (const std::exception&) {
    return false;
  }
  if (parsed_chars != raw.size()) {
    return false;
  }
  if (parsed < std::numeric_limits<int>::min() || parsed > std::numeric_limits<int>::max()) {
    return false;
  }
  out = static_cast<int>(parsed);
  return true;
}

bool parseArgs(int argc, char** argv, CliOptions& options, std::string& error_message) {
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "-h" || arg == "--help") {
      options.show_help = true;
      continue;
    }
    if (arg == "--list") {
      options.list_only = true;
      continue;
    }
    auto require_value = [&](const char* flag_name) -> const char* {
      if (i + 1 >= argc) {
        error_message = std::string("Missing value for ") + flag_name;
        return nullptr;
      }
      return argv[++i];
    };
    if (arg == "--scenario") {
      const char* value = require_value("--scenario");
      if (!value) {
        return false;
      }
      options.scenario = value;
      options.scenario_explicit = true;
      continue;
    }
    if (arg == "--backend") {
      const char* value = require_value("--backend");
      if (!value) {
        return false;
      }
      options.backend = value;
      options.backend_explicit = true;
      continue;
    }
    if (arg == "--payload-bytes") {
      const char* value = require_value("--payload-bytes");
      if (!value) {
        return false;
      }
      if (!parseUInt64(value, options.payload_bytes)) {
        error_message = "Invalid integer value for --payload-bytes";
        return false;
      }
      options.payload_bytes_explicit = true;
      continue;
    }
    if (arg == "--iterations") {
      const char* value = require_value("--iterations");
      if (!value) {
        return false;
      }
      if (!parseInt(value, options.iterations)) {
        error_message = "Invalid integer value for --iterations";
        return false;
      }
      continue;
    }
    if (arg == "--touch-stride") {
      const char* value = require_value("--touch-stride");
      if (!value) {
        return false;
      }
      if (!parseUInt64(value, options.touch_stride)) {
        error_message = "Invalid integer value for --touch-stride";
        return false;
      }
      continue;
    }

    error_message = "Unknown option: " + arg;
    return false;
  }
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  CliOptions options;
  std::string error_message;
  if (!parseArgs(argc, argv, options, error_message)) {
    printHelp();
    std::cerr << error_message << '\n';
    return 1;
  }

  if (options.show_help) {
    printHelp();
    return 0;
  }

  if (options.list_only) {
    printList();
    return 0;
  }

  if (!options.scenario_explicit || !options.backend_explicit) {
    printHelp();
    std::cerr << "Both --scenario and --backend must be set explicitly.\n";
    return 1;
  }

  if (options.iterations <= 0) {
    std::cerr << "--iterations must be greater than 0.\n";
    return 1;
  }

  if (options.payload_bytes == 0) {
    std::cerr << "--payload-bytes must be greater than 0.\n";
    return 1;
  }

  if (options.touch_stride == 0) {
    std::cerr << "--touch-stride must be greater than 0.\n";
    return 1;
  }

  if (!isSupportedScenario(options.scenario)) {
    std::cerr << "Unsupported scenario: " << options.scenario << '\n';
    return 1;
  }

  if (!isSupportedBackend(options.backend)) {
    std::cerr << "Unsupported backend: " << options.backend << '\n';
    return 1;
  }

  if (options.scenario != kDefaultScenario || options.backend != kDefaultBackend) {
    std::cerr << "Unsupported scenario/backend pair: " << options.scenario << " + " << options.backend << '\n';
    return 1;
  }

  const auto& scenario_spec = scenarioRegistry().at(options.scenario);
  BenchmarkConfig config{
      .scenario = options.scenario,
      .backend = options.backend,
      .payload_bytes = static_cast<size_t>(options.payload_bytes),
      .iterations = options.iterations,
      .touch_stride = static_cast<size_t>(options.touch_stride),
  };

  if (!options.payload_bytes_explicit) {
    config.payload_bytes = scenario_spec.default_payload_bytes;
  }

  const BenchmarkResult result = runDirectKvScaffold(config);

  nlohmann::json output{
      {"task_id", kTaskId},
      {"run_id", makeRunId()},
      {"scenario", config.scenario},
      {"backend", config.backend},
      {"stage", result.stage},
      {"latency_ms", result.latency_ms},
      {"payload_bytes", config.payload_bytes},
      {"iterations", config.iterations},
      {"touch_stride", config.touch_stride},
      {"bytes_copied", result.bytes_copied},
      {"checksum", result.checksum},
      {"result", "ok"},
  };
  std::cout << output.dump() << '\n';
  return 0;
}
