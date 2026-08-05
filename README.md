# comfyui-minimax

Headless CUDA 13 ComfyUI image for MiniMax-H3 video-and-audio generation on Vast.ai and RunPod.

This repository deliberately reuses the operational harness from `markwelshboy/pod-runtime` while owning its MiniMax-specific image, manifests, quant selection, SageAttention validation, and startup order. It does not inherit the CUDA, Torch, Python, ComfyUI, model, or workflow assumptions from `comfyui-inference-headless-to-desktop`.

## Image stack

- CUDA 13.0.3 / Ubuntu 24.04
- Python 3.12
- PyTorch 2.11.0, torchvision 0.26.0, torchaudio 2.11.0 from cu130
- ComfyUI v0.30.1
- `comfy-aimdo==0.4.11`
- `comfy-kitchen==0.2.26`
- Hearmeman's prebuilt SageAttention 2.2.0 cp312/cu130 wheel
- One headless ComfyUI process on port 8188
- SSH server included and configured by `pod-runtime`

There are no browser, desktop, Jupyter, or CivitAI components.

## Storage layout

Image-owned application code remains at `/opt/ComfyUI`. Runtime and persistent state lives at `/workspace/ComfyUI`:

```text
/workspace/ComfyUI/
├── cache/
├── custom_nodes/
├── input/
├── models/
├── output/
└── user/
```

`pod-runtime` links those state directories into `/opt/ComfyUI`. The same layout works when `/workspace` is a network volume or ordinary container storage. No `extra_model_paths.yaml` is needed.

## Quant selection

`MINIMAX_QUANT` accepts:

| Value | Transformer | Text encoder | Intended hardware |
|---|---|---|---|
| `fp8` | FP8 | INT8 | Default; Ada, Hopper, or Blackwell |
| `int8` | INT8 | INT8 | Compatibility fallback |
| `nvfp4` | FP8 | NVFP4 | Blackwell, especially RTX PRO 6000 |

The default is `fp8`.

For Blackwell:

```bash
MINIMAX_QUANT=nvfp4
```

Only the common VAEs and the selected quant section are downloaded. `nvfp4` deliberately uses the FP8 transformer and the NVFP4 text encoder because those are the available upstream open-weight files.

Set `DOWNLOAD_MINIMAX_MODELS=false` to boot without automatically provisioning weights.

## Workflows

No workflows from the upstream image are bundled. At pod startup, `markwelshboy/comfyui-templates` is synchronized into:

```text
/workspace/ComfyUI/user/default/workflows/MyWorkflows
```

Set `ENABLE_MY_WORKFLOWS_DOWNLOAD=false` to skip that sync.

## Custom nodes

The repository-local invocation manifest installs the curated upstream toolkit at runtime:

- KJNodes
- rgthree
- VideoHelperSuite
- Essentials
- Easy-Use
- Frame Interpolation
- UltimateSDUpscale
- Impact Pack
- RMBG
- segment-anything-2
- ComfyUI-Manager

After node installation, startup removes both ONNX Runtime packages and reinstalls `onnxruntime-gpu` so CPU-only node requirements cannot shadow the CUDA provider.

## SageAttention

The Docker build fetches and installs the same prebuilt cu130/cp312 wheel used by `Hearmeman24/comfyui-minimax`. Startup runs a real CUDA kernel call. `run_comfy_mux` receives `ENABLE_SAGE=true` only when that probe succeeds. There is no source-build fallback.

The wheel therefore needs kernels for the GPU architectures used by this image, principally Ada `sm_89` and Blackwell `sm_120`.

## Build

```bash
./build_comfy-minimax.sh --tag latest
```

Build locally rather than pushing:

```bash
./build_comfy-minimax.sh --load --tag test
```

Override a build argument, for example the Sage wheel source:

```bash
./build_comfy-minimax.sh \
  --build-arg SAGE_WHEEL_URL=https://example.invalid/sageattention.whl
```

## Runtime variables

| Variable | Default | Purpose |
|---|---:|---|
| `MINIMAX_QUANT` | `fp8` | `fp8`, `int8`, or `nvfp4` model selection |
| `DOWNLOAD_MINIMAX_MODELS` | `true` | Provision the selected manifest sections |
| `INSTALL_CUSTOM_NODES` | `true` | Install/update the `minimax` manifest set |
| `ENABLE_MY_WORKFLOWS_DOWNLOAD` | `true` | Sync `comfyui-templates` |
| `POD_RUNTIME_REF` | `main` | Pod-runtime branch or tag to clone |
| `START_TIMEOUT` | `180` | Seconds for port 8188 health startup |

Hugging Face, SSH, Telegram, and deploy-key variables retain their `pod-runtime` meanings.
