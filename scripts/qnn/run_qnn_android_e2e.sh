#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qnn_android_e2e_$(date +%Y%m%d_%H%M%S).log"

DEVICE_DIR="/data/local/tmp/mllm"
DEVICE_MODEL_DIR="/data/local/tmp/zhanghao/models"
ANDROID_BUILD_DIR="build-android-arm64-v8a-qnn"
RUNNER_BIN="mllm-qwen-npu"
CONFIG_LOCAL="mllm/models/qwen_npu/config_1.8B_w8a16_qnn.json"
SKIP_BUILD=0

NPU_MODEL=""
CPU_MODEL=""
TOKENIZER_JSON=""
QWEN_MERGES=""

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
  run_qnn_android_e2e.sh [options]

Required options:
  --npu-model <path>          QNN prefill model (.mllm)
  --cpu-model <path>          CPU decode model (.mllm)
  --tokenizer-json <path>     tokenizer.json
  --qwen-merges <path>        qwen_merges.txt

Optional options:
  --device-dir <path>         Device runtime dir (default: /data/local/tmp/mllm)
  --device-model-dir <path>   Device model dir for qwen_npu sample (default: /data/local/tmp/zhanghao/models)
  --skip-build                Skip build and directly deploy/run
  -h, --help                  Show this help

Notes:
  - This script targets non-AOT qnn_android flow using examples/qwen_npu.
  - qwen_npu sample currently uses fixed model paths on device, so models are pushed to --device-model-dir with fixed file names.
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --npu-model)
      NPU_MODEL="$2"
      shift 2
      ;;
    --cpu-model)
      CPU_MODEL="$2"
      shift 2
      ;;
    --tokenizer-json)
      TOKENIZER_JSON="$2"
      shift 2
      ;;
    --qwen-merges)
      QWEN_MERGES="$2"
      shift 2
      ;;
    --device-dir)
      DEVICE_DIR="$2"
      shift 2
      ;;
    --device-model-dir)
      DEVICE_MODEL_DIR="$2"
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

require_cmd adb
require_cmd python
require_cmd rg

cd "$PROJECT_ROOT"

[[ -f "$CONFIG_LOCAL" ]] || die "Config file not found: $CONFIG_LOCAL"
[[ -n "$NPU_MODEL" ]] || die "--npu-model is required"
[[ -n "$CPU_MODEL" ]] || die "--cpu-model is required"
[[ -n "$TOKENIZER_JSON" ]] || die "--tokenizer-json is required"
[[ -n "$QWEN_MERGES" ]] || die "--qwen-merges is required"
[[ -f "$NPU_MODEL" ]] || die "NPU model not found: $NPU_MODEL"
[[ -f "$CPU_MODEL" ]] || die "CPU model not found: $CPU_MODEL"
[[ -f "$TOKENIZER_JSON" ]] || die "Tokenizer json not found: $TOKENIZER_JSON"
[[ -f "$QWEN_MERGES" ]] || die "Qwen merges not found: $QWEN_MERGES"

QAIRT_SDK_ROOT="${QAIRT_SDK_ROOT:-${QNN_SDK_ROOT:-}}"
[[ -n "$QAIRT_SDK_ROOT" ]] || die "QAIRT_SDK_ROOT is not set (or QNN_SDK_ROOT fallback)."
[[ -d "$QAIRT_SDK_ROOT" ]] || die "QAIRT_SDK_ROOT path does not exist: $QAIRT_SDK_ROOT"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  export ANDROID_NDK_PATH="${ANDROID_NDK_PATH:-}"
  [[ -n "$ANDROID_NDK_PATH" ]] || die "ANDROID_NDK_PATH is required for build"

  info "Build qnn_android (non-AOT)"
  run python task.py tasks/build_android_qnn.yaml
else
  warn "Skip build enabled; using existing build outputs"
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
  "$QAIRT_SDK_ROOT/lib/aarch64-android/libQnnSystem.so"
  "$QAIRT_SDK_ROOT/lib/hexagon-v75/unsigned/libQnnHtpV75Skel.so"
)
for lib in "${LIBS[@]}"; do
  [[ -f "$lib" ]] || die "Required QNN lib missing: $lib"
done

info "Prepare device directories"
run adb shell "mkdir -p '$DEVICE_DIR' '$DEVICE_MODEL_DIR'"

info "Push runtime libraries and qnn runner"
run adb push "$PROJECT_ROOT/$ANDROID_BUILD_DIR/bin"/*.so "$DEVICE_DIR/"
run adb push "$PROJECT_ROOT/$ANDROID_BUILD_DIR/bin/$RUNNER_BIN" "$DEVICE_DIR/"

info "Push QNN SDK libs"
for lib in "${LIBS[@]}"; do
  run adb push "$lib" "$DEVICE_DIR/"
done

info "Push custom op packages"
run adb push "$OP_CPU" "$DEVICE_DIR/libQnnLLaMAPackage_CPU.so"
run adb push "$OP_HTP" "$DEVICE_DIR/libQnnLLaMAPackage_HTP.so"

info "Push qwen_npu config/tokenizer"
run adb push "$PROJECT_ROOT/$CONFIG_LOCAL" "$DEVICE_DIR/config_1.8B_w8a16_qnn.json"
run adb push "$TOKENIZER_JSON" "$DEVICE_DIR/tokenizer.json"
run adb push "$QWEN_MERGES" "$DEVICE_DIR/qwen_merges.txt"

info "Push model files to sample-fixed path"
run adb push "$NPU_MODEL" "$DEVICE_MODEL_DIR/qwen1.5-1.8b-chat-rot-qnn.mllm"
run adb push "$CPU_MODEL" "$DEVICE_MODEL_DIR/qwen1.5-1.8b-chat-rot_q4_0.mllm"

info "Run non-AOT qnn_android sample"
ADB_RUN_CMD="cd '$DEVICE_DIR' && export LD_LIBRARY_PATH='$DEVICE_DIR' && chmod +x '$RUNNER_BIN' && ./'$RUNNER_BIN'"

set +e
adb shell "$ADB_RUN_CMD" 2>&1 | tee -a "$LOG_FILE"
RC=${PIPESTATUS[0]}
set -e

[[ $RC -eq 0 ]] || die "qnn_android runner failed, see log: $LOG_FILE"

if rg -q "Decode completed:" "$LOG_FILE"; then
  info "Detected completion marker: Decode completed"
else
  warn "Run finished but did not detect 'Decode completed:' marker. Please inspect log manually."
fi

info "qnn_android E2E finished. Log: $LOG_FILE"
