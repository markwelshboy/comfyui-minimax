# syntax=docker/dockerfile:1.7

ARG CUDA_BASE_IMAGE=nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04
FROM ${CUDA_BASE_IMAGE} AS final

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG COMFYUI_REF=v0.30.1
ARG SAGE_WHEEL_URL=https://raw.githubusercontent.com/Hearmeman24/comfyui-minimax/master/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="comfyui-minimax" \
      org.opencontainers.image.description="Headless ComfyUI MiniMax-H3 runtime for Vast.ai and RunPod" \
      org.opencontainers.image.source="https://github.com/markwelshboy/comfyui-minimax" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_INPUT=1 \
    PIP_PREFER_BINARY=1 \
    HF_XET_HIGH_PERFORMANCE=1 \
    CUDA_VARIANT=cu130 \
    VENV=/opt/venv \
    COMFY_APP=/opt/ComfyUI \
    MINIMAX_PROFILE_DIR=/opt/comfyui-minimax

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3.12-dev python3-pip \
      git git-lfs curl ca-certificates jq \
      build-essential gcc g++ cmake ninja-build pkg-config \
      ffmpeg aria2 rsync tmux unzip wget vim less nano \
      libgl1 libglib2.0-0 libgoogle-perftools4 \
      openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /var/run/sshd /workspace /opt/sage "${MINIMAX_PROFILE_DIR}" \
    && git lfs install --system \
    && python3.12 -m venv "${VENV}"

ENV PATH="${VENV}/bin:${PATH}"

COPY pip.conf /etc/pip.conf
COPY constraints.txt /opt/constraints.txt
ENV PIP_CONSTRAINT=/opt/constraints.txt \
    PIP_BUILD_CONSTRAINT=/opt/constraints.txt

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade "pip<25.2" "setuptools>=66.1,<82" "wheel>=0.38" \
    && pip install --index-url "${TORCH_INDEX_URL}" \
         torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0 \
    && python -c "import torch; assert torch.version.cuda and torch.version.cuda.startswith('13'), torch.version.cuda; print(torch.__version__, torch.version.cuda)"

RUN --mount=type=cache,target=/root/.cache/pip \
    git clone --depth=1 --branch "${COMFYUI_REF}" \
      https://github.com/comfyanonymous/ComfyUI.git "${COMFY_APP}" \
    && pip install -r "${COMFY_APP}/requirements.txt" \
    && test -f "${COMFY_APP}/comfy_extras/nodes_minimax_h3.py" \
    && python -c "from pathlib import Path; assert Path('${COMFY_APP}/comfy_extras/nodes_minimax_h3.py').is_file()" \
    && pip install \
         cupy-cuda13x \
         huggingface_hub \
         hf_transfer \
         onnxruntime-gpu \
         opencv-python==4.12.0.88

RUN pip freeze | grep -E '^(torch|torchvision|torchaudio|torchsde|comfy-aimdo|comfy-kitchen)==' \
      > /opt/image-stack-constraints.txt \
    && cat /opt/image-stack-constraints.txt

RUN curl -fL --retry 5 --retry-delay 3 \
      -o /opt/sage/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
      "${SAGE_WHEEL_URL}" \
    && pip install --no-deps /opt/sage/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
    && python -c "import sageattention; print('sageattention import OK')"

COPY manifests "${MINIMAX_PROFILE_DIR}/manifests"
COPY src "${MINIMAX_PROFILE_DIR}/src"
RUN chmod +x "${MINIMAX_PROFILE_DIR}/src/"*.sh

WORKDIR /workspace
EXPOSE 22 8188
ENTRYPOINT ["/opt/comfyui-minimax/src/start_script.sh"]
