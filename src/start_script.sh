#!/usr/bin/env bash
set -euo pipefail

mkdir -p /workspace /workspace/logs
runtime_dir="${POD_RUNTIME_DIR:-/workspace/pod-runtime}"
runtime_repo="${POD_RUNTIME_REPO:-https://github.com/markwelshboy/pod-runtime.git}"
runtime_ref="${POD_RUNTIME_REF:-main}"

if [[ -d "${runtime_dir}/.git" ]]; then
  echo "[bootstrap] Updating pod-runtime (${runtime_ref})..."
  git -C "${runtime_dir}" fetch --depth=1 origin "${runtime_ref}"
  git -C "${runtime_dir}" checkout -B "${runtime_ref}" FETCH_HEAD
else
  echo "[bootstrap] Cloning pod-runtime (${runtime_ref})..."
  rm -rf "${runtime_dir}"
  git clone --depth=1 --branch "${runtime_ref}" "${runtime_repo}" "${runtime_dir}"
fi

export POD_RUNTIME_DIR="${runtime_dir}"
exec "${POD_RUNTIME_DIR}/start.minimax.sh"
