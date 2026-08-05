#!/usr/bin/env bash
set -euo pipefail

wheel="$(find /opt/sage -maxdepth 1 -name 'sageattention-*.whl' -print -quit 2>/dev/null || true)"
if [[ -z "${wheel}" ]]; then
  echo "[sage] No baked SageAttention wheel found; running without SageAttention."
  export ENABLE_SAGE=false
  return 0 2>/dev/null || exit 0
fi

if ! python -c 'import sageattention' >/dev/null 2>&1; then
  echo "[sage] Installing baked wheel: ${wheel}"
  pip install --no-deps "${wheel}"
fi

if python - <<'PY'
import torch
from sageattention import sageattn
if not torch.cuda.is_available():
    raise SystemExit("CUDA is unavailable")
q = torch.randn(1, 8, 128, 64, dtype=torch.float16, device="cuda")
sageattn(q, q.clone(), q.clone())
torch.cuda.synchronize()
print(torch.cuda.get_device_name(0))
PY
then
  echo "[sage] CUDA kernel probe passed."
  export ENABLE_SAGE=true
else
  echo "[sage] CUDA kernel probe failed; running without --use-sage-attention." >&2
  export ENABLE_SAGE=false
fi
