#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-markwelshboy/comfyui-minimax}"
TAG="${TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
PUSH=true
LOAD=false
NO_CACHE=false
EXTRA_BUILD_ARGS=()

usage() {
  cat <<'USAGE'
Usage: ./build_comfy-minimax.sh [options]

  --image REPO/NAME       Default: markwelshboy/comfyui-minimax
  --tag TAG               Default: latest
  --platform PLATFORM     Default: linux/amd64
  --load                  Load locally instead of pushing
  --no-push               Build and load locally
  --no-cache              Disable BuildKit cache
  --build-arg KEY=VALUE   Repeatable Docker build argument
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="${2:?}"; shift 2 ;;
    --tag) TAG="${2:?}"; shift 2 ;;
    --platform) PLATFORM="${2:?}"; shift 2 ;;
    --load|--no-push) PUSH=false; LOAD=true; shift ;;
    --no-cache) NO_CACHE=true; shift ;;
    --build-arg) EXTRA_BUILD_ARGS+=(--build-arg "${2:?}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v docker >/dev/null || die "docker not found"
sudo docker buildx version >/dev/null 2>&1 || die "docker buildx not available"

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
IMAGE_VERSION="${IMAGE_VERSION:-${TAG}}"

args=(
  buildx build
  --target final
  --platform "${PLATFORM}"
  --tag "${IMAGE}:${TAG}"
  --build-arg "BUILD_DATE=${BUILD_DATE}"
  --build-arg "VCS_REF=${VCS_REF}"
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}"
)
${NO_CACHE} && args+=(--no-cache)
${PUSH} && args+=(--push)
${LOAD} && args+=(--load)
args+=("${EXTRA_BUILD_ARGS[@]}" .)

printf 'Building %s:%s for %s\n' "${IMAGE}" "${TAG}" "${PLATFORM}"
sudo docker "${args[@]}"
