#!/usr/bin/env bash
set -euo pipefail

umask 0022
mkdir -p /workspace /workspace/logs
PROFILE_DIR=/opt/comfyui-minimax
source "${PROFILE_DIR}/src/.env.minimax"
source "${POD_RUNTIME_DIR}/helpers.sh"

STARTUP_LOG="${COMFY_LOGS}/startup-minimax.log"
exec > >(tee -a "${STARTUP_LOG}") 2>&1

echo "=== MiniMax-H3 bootstrap: $(date -Is) ==="
echo "Application: ${COMFY_APP}"
echo "State: ${COMFY_STATE}"

case "${MINIMAX_QUANT}" in
  fp8|int8|nvfp4) ;;
  *) echo "ERROR: MINIMAX_QUANT must be fp8, int8, or nvfp4; got '${MINIMAX_QUANT}'." >&2; exit 2 ;;
esac

gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || true)"
compute_cap="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 || true)"
echo "GPU: ${gpu_name:-unknown}; compute capability: ${compute_cap:-unknown}"
echo "MiniMax quant: ${MINIMAX_QUANT}"
if [[ "${MINIMAX_QUANT}" == nvfp4 && ! "${compute_cap}" =~ ^12\. ]]; then
  echo "WARNING: nvfp4 is intended for Blackwell; FP8 is safer on compute capability '${compute_cap:-unknown}'."
fi

export download_minimax_h3_common=false
export download_minimax_h3_fp8=false
export download_minimax_h3_int8=false
export download_minimax_h3_nvfp4=false
if [[ "${DOWNLOAD_MINIMAX_MODELS}" == true ]]; then
  export download_minimax_h3_common=true
  case "${MINIMAX_QUANT}" in
    fp8) export download_minimax_h3_fp8=true ;;
    int8) export download_minimax_h3_int8=true ;;
    nvfp4) export download_minimax_h3_nvfp4=true ;;
  esac
fi

mkdir -p /root/.secrets
chmod 700 /root/.secrets
{
  printf 'export POD_RUNTIME_DIR=%q\n' "${POD_RUNTIME_DIR}"
  printf 'export COMFY_APP=%q\n' "${COMFY_APP}"
  printf 'export COMFY_STATE=%q\n' "${COMFY_STATE}"
  printf 'export COMFY_HOME=%q\n' "${COMFY_HOME}"
  printf 'export MINIMAX_QUANT=%q\n' "${MINIMAX_QUANT}"
  env | awk -F= '/^(HF_TOKEN|HUGGINGFACE_HUB_TOKEN|GIT_DEPLOY_KEY_|SSH_|TELEGRAM_)/ {print}' \
    | while IFS='=' read -r key value; do printf 'export %s=%q\n' "${key}" "${value}"; done
} > /root/.secrets/env.current
chmod 600 /root/.secrets/env.current

install_system_hff
install_root_shell_dotfiles || true
ensure_comfy_dirs
link_comfy_state_into_app
setup_ssh || true
git_auth_bootstrap || true
hf_transfer_tune
hf_transfer_install
hf_transfer_verify

model_download_started=false
if [[ "${ENABLE_MODEL_MANIFEST_DOWNLOAD}" == true && "${DOWNLOAD_MINIMAX_MODELS}" == true ]]; then
  echo "[models] Starting manifest download: ${MODEL_MANIFEST_URL}"
  hf_download_from_manifest
  model_download_started=true
else
  echo "[models] Model provisioning disabled."
fi

if [[ "${INSTALL_CUSTOM_NODES}" == true ]]; then
  node_manifest="${CUSTOM_NODES_MANIFEST_URL_OVERRIDE:-${CUSTOM_NODES_MANIFEST_URL}}"
  echo "[nodes] Installing set '${CUSTOM_NODE_SETS}' from ${node_manifest}"
  install_custom_nodes "${node_manifest}"
  snapshot_custom_nodes_state "after-minimax-install" || true
  pip uninstall -y onnxruntime onnxruntime-gpu >/dev/null 2>&1 || true
  pip install --constraint /opt/constraints.txt onnxruntime-gpu
fi

if [[ "${ENABLE_MY_WORKFLOWS_DOWNLOAD}" == true ]]; then
  echo "[workflows] Syncing ${GIT_MYWORKFLOWS_REPO_ID}"
  init_repo --git "${GIT_MYWORKFLOWS_REPO_ID}" "${GIT_MYWORKFLOWS_REPO_LOCAL}"
  mkdir -p "${WORKFLOW_DIR}/MyWorkflows"
  find "${WORKFLOW_DIR}/MyWorkflows" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  find "${GIT_MYWORKFLOWS_REPO_LOCAL}" -mindepth 1 -maxdepth 1 ! -name .git \
    -exec ln -sfn {} "${WORKFLOW_DIR}/MyWorkflows/" \;
fi

source "${PROFILE_DIR}/src/prepare_sage.sh"

if [[ "${model_download_started}" == true ]]; then
  echo "[models] Waiting for selected MiniMax-H3 weights..."
  hf_download_wait
  echo "[models] Selected weights are ready."
fi

python - <<'PY'
import onnxruntime as ort
import torch
import comfy_aimdo
import comfy_kitchen
assert torch.version.cuda and torch.version.cuda.startswith("13"), torch.version.cuda
assert torch.cuda.is_available(), "CUDA unavailable"
print("torch:", torch.__version__, "CUDA:", torch.version.cuda)
print("GPU:", torch.cuda.get_device_name(0))
print("onnxruntime providers:", ort.get_available_providers())
assert "CUDAExecutionProvider" in ort.get_available_providers()
print("comfy_aimdo:", getattr(comfy_aimdo, "__version__", "installed"))
print("comfy_kitchen:", getattr(comfy_kitchen, "__version__", "installed"))
PY

snapshot_custom_nodes_state --summary "before-minimax-launch" || true
confirm_stack_health_or_stop || true
if [[ -f "${COMFY_LOGS}/stack_broken" ]]; then
  echo "ERROR: stack health check failed; see ${COMFY_LOGS}/stack_health_report.txt" >&2
  tail -f /dev/null
fi

cd "${COMFY_APP}"
if "${POD_RUNTIME_DIR}/run_comfy_mux.sh" start; then
  echo "MiniMax-H3 ComfyUI is available on port 8188."
else
  echo "ERROR: ComfyUI failed to become healthy; see ${COMFY_LOGS}/comfyui-8188.log" >&2
  exit 1
fi

disk_watch_start --path / --log "${COMFY_LOGS}/disk_watch.log" || true
pod_nag --interval 3600 || true

echo "=== MiniMax-H3 bootstrap complete: $(date -Is) ==="
sleep infinity
