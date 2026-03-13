#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qnn_aot_e2e_$(date +%Y%m%d_%H%M%S).log"

DEVICE_DIR="/data/local/tmp/mllm"
AOT_BUILD_DIR="build-qnn-aot"
ANDROID_BUILD_DIR="build-android-arm64-v8a-qnn"
RUNNER_BIN="mllm-qwen3-aot-runner"
AOT_COMPILER_BIN="mllm-qwen3-aot-sha-c"
MODEL_CONFIG="examples/qwen3_qnn_aot/config_1.7B.json"
AOT_CONFIG="examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json"
PROMPT_TEXT="你好，请用一句话介绍 mllm。"
GEN_LEN=32
CONTEXT_BIN=""
MODEL_MLLM=""
COMPILE_CONTEXT=0
SKIP_BUILD=0
ENABLE_PERF=0

info() { echo "[INFO] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[WARN] $*" | tee -a "$LOG_FILE" >&2; }
error() { echo "[ERROR] $*" | tee -a "$LOG_FILE" >&2; }

die() {
  error "$*"
  exit 1
}

run() {
  info "RUN: $*"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

usage() {
  cat <<'USAGE'
Usage:
  run_qnn_aot_android_e2e.sh [options]

Options:
  --context-bin <path>        Existing AOT context binary (.bin). Required unless --compile-context is set.
  --compile-context           Build x86 AOT tool and generate context binary from --model-mllm.
  --model-mllm <path>         .mllm model path for AOT compile (required with --compile-context).
  --model-config <path>       Model config JSON (default: examples/qwen3_qnn_aot/config_1.7B.json).
  --aot-config <path>         AOT config JSON (default: examples/qwen3_qnn_aot/qnn_aot_cfg_1.7B.json).
  --tokenizer <path>          Tokenizer file on host (required).
  --prompt <text>             Prompt fed to runner (default provided).
  --gen-len <n>              Decode token length passed to runner (default: 32).
  --perf                     Enable runner-side performance summary output.
  --device-dir <path>         Device deploy path (default: /data/local/tmp/mllm).
  --skip-build                Skip build steps and only deploy/run.
  -h, --help                  Show this help.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context-bin)
      CONTEXT_BIN="$2"
      shift 2
      ;;
    --compile-context)
      COMPILE_CONTEXT=1
      shift
      ;;
    --model-mllm)
      MODEL_MLLM="$2"
      shift 2
      ;;
    --model-config)
      MODEL_CONFIG="$2"
      shift 2
      ;;
    --aot-config)
      AOT_CONFIG="$2"
      shift 2
      ;;
    --tokenizer)
      TOKENIZER_PATH="$2"
      shift 2
      ;;
    --prompt)
      PROMPT_TEXT="$2"
      shift 2
      ;;
    --gen-len)
      GEN_LEN="$2"
      shift 2
      ;;
    --perf)
      ENABLE_PERF=1
      shift
      ;;
    --device-dir)
      DEVICE_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

TOKENIZER_PATH="${TOKENIZER_PATH:-}"

require_cmd adb
require_cmd python
# require_cmd rg

cd "$PROJECT_ROOT"

QAIRT_SDK_ROOT="${QAIRT_SDK_ROOT:-${QNN_SDK_ROOT:-}}"
[[ -n "$QAIRT_SDK_ROOT" ]] || die "QAIRT_SDK_ROOT is not set (or QNN_SDK_ROOT fallback)."
[[ -d "$QAIRT_SDK_ROOT" ]] || die "QAIRT_SDK_ROOT path does not exist: $QAIRT_SDK_ROOT"
[[ -n "$TOKENIZER_PATH" ]] || die "--tokenizer is required"
[[ -f "$TOKENIZER_PATH" ]] || die "Tokenizer file not found: $TOKENIZER_PATH"
[[ -f "$MODEL_CONFIG" ]] || die "Model config not found: $MODEL_CONFIG"
[[ -f "$AOT_CONFIG" ]] || die "AOT config not found: $AOT_CONFIG"

if [[ "$COMPILE_CONTEXT" -eq 1 ]]; then
  [[ -n "$MODEL_MLLM" ]] || die "--model-mllm is required with --compile-context"
  [[ -f "$MODEL_MLLM" ]] || die "Model .mllm not found: $MODEL_MLLM"
else
  [[ -n "$CONTEXT_BIN" ]] || die "--context-bin is required when --compile-context is not set"
  [[ -f "$CONTEXT_BIN" ]] || die "Context binary not found: $CONTEXT_BIN"
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  export ANDROID_NDK_PATH="${ANDROID_NDK_PATH:-}"
  [[ -n "$ANDROID_NDK_PATH" ]] || die "ANDROID_NDK_PATH is required for build"

  info "Build Android QNN runtime"
  run python task.py tasks/build_android_qnn.yaml

  if [[ "$COMPILE_CONTEXT" -eq 1 ]]; then
    info "Build x86 QNN AOT compiler"
    run python task.py tasks/build_x86_qnn_aot.yaml
  fi
else
  warn "Skip build enabled; using existing build outputs"
fi

if [[ "$COMPILE_CONTEXT" -eq 1 ]]; then
  local_compiler="$PROJECT_ROOT/$AOT_BUILD_DIR/bin/$AOT_COMPILER_BIN"
  [[ -x "$local_compiler" ]] || die "AOT compiler not found: $local_compiler"
  run "$local_compiler" \
    -m "$MODEL_MLLM" \
    -c "$MODEL_CONFIG" \
    --aot_config "$AOT_CONFIG" \
    --qnn_env_path "$QAIRT_SDK_ROOT/lib/x86_64-linux-clang/"

  CONTEXT_BIN="$PROJECT_ROOT/qwen3-1.7B-lpbq-sha.bin"
  [[ -f "$CONTEXT_BIN" ]] || die "Expected context binary not generated: $CONTEXT_BIN"
fi

[[ -x "$PROJECT_ROOT/$ANDROID_BUILD_DIR/bin/$RUNNER_BIN" ]] || die "Runner not found: $ANDROID_BUILD_DIR/bin/$RUNNER_BIN"

OP_CPU="$PROJECT_ROOT/mllm/backends/qnn/custom-op-package/LLaMAPackage/build/aarch64-android/libQnnLLaMAPackage.so"
OP_HTP="$PROJECT_ROOT/mllm/backends/qnn/custom-op-package/LLaMAPackage/build/hexagon-v75/libQnnLLaMAPackage.so"
[[ -f "$OP_CPU" ]] || die "OpPackage CPU lib not found: $OP_CPU"
[[ -f "$OP_HTP" ]] || die "OpPackage HTP lib not found: $OP_HTP"

LIBS=(
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtp.so"
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpV75Stub.so"
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpPrepare.so"
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpProfilingReader.so"
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnHtpOptraceProfilingReader.so"
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnSystem.so"
  "$QAIRT_SDK_ROOT/lib/hexagon-v75/unsigned/libQnnHtpV75Skel.so"
)
for lib in "${LIBS[@]}"; do
  [[ -f "$lib" ]] || die "Required QNN lib missing: $lib"
done

info "Prepare device directory: $DEVICE_DIR"
run adb shell "mkdir -p '$DEVICE_DIR'"

info "Push model/config/tokenizer"
run adb push "$CONTEXT_BIN" "$DEVICE_DIR/"
run adb push "$MODEL_CONFIG" "$DEVICE_DIR/"
run adb push "$TOKENIZER_PATH" "$DEVICE_DIR/qwen3-tokenizer.json"

info "Push QNN runtime libraries"
for lib in "${LIBS[@]}"; do
  run adb push "$lib" "$DEVICE_DIR/"
done

info "Push custom op packages"
run adb push "$OP_CPU" "$DEVICE_DIR/libQnnLLaMAPackage_CPU.so"
run adb push "$OP_HTP" "$DEVICE_DIR/libQnnLLaMAPackage_HTP.so"

info "Push mllm runtime libraries and runner"
run adb push "$PROJECT_ROOT/$ANDROID_BUILD_DIR/bin"/*.so "$DEVICE_DIR/"
run adb push "$PROJECT_ROOT/$ANDROID_BUILD_DIR/bin/$RUNNER_BIN" "$DEVICE_DIR/"

PROMPT_TMP="$PROJECT_ROOT/.qnn_aot_prompt.txt"
printf '%s\n' "$PROMPT_TEXT" > "$PROMPT_TMP"
run adb push "$PROMPT_TMP" "$DEVICE_DIR/.prompt.txt"
rm -f "$PROMPT_TMP"

info "Run AOT runner on device"
RUNNER_ARGS="-m $(basename "$CONTEXT_BIN") -t qwen3-tokenizer.json -c $(basename "$MODEL_CONFIG") --ar_len 32 --gen_len $GEN_LEN"
if [[ "$ENABLE_PERF" -eq 1 ]]; then
  RUNNER_ARGS="$RUNNER_ARGS --perf"
fi
ADB_RUN_CMD="cd '$DEVICE_DIR' && export LD_LIBRARY_PATH='$DEVICE_DIR' && cat .prompt.txt | ./$RUNNER_BIN $RUNNER_ARGS"

set +e
adb shell "$ADB_RUN_CMD" 2>&1 | tee -a "$LOG_FILE"
RC=${PIPESTATUS[0]}
set -e

[[ $RC -eq 0 ]] || die "AOT runner failed, see log: $LOG_FILE"

info "AOT E2E finished successfully. Log: $LOG_FILE"
