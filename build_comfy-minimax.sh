#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-markwelshboy/comfyui-minimax}"
TAG="${TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
BUILDER="${BUILDX_BUILDER:-buildkit-scratch}"
PUSH=true
LOAD=false
NO_CACHE=false
PRUNE=false
PRUNE_HARD=false
EXTRA_BUILD_ARGS=()

usage() {
  cat <<'USAGE'
Usage: ./build_comfy-minimax.sh [options]

  --image REPO/NAME       Default: markwelshboy/comfyui-minimax
  --tag TAG               Default: latest
  --builder NAME          Buildx builder; default: buildkit-scratch
  --platform PLATFORM     Default: linux/amd64
  --load                  Load into local Docker instead of pushing
  --no-push               Build/cache only; do not push or load
  --no-cache              Disable BuildKit cache
  --prune                 Prune stopped containers and dangling Docker images
  --prune-hard            Aggressively prune selected Buildx builder cache
  --build-arg KEY=VALUE   Repeatable Docker build argument
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="${2:?}"; shift 2 ;;
    --tag) TAG="${2:?}"; shift 2 ;;
    --builder) BUILDER="${2:?}"; shift 2 ;;
    --platform) PLATFORM="${2:?}"; shift 2 ;;
    --load) PUSH=false; LOAD=true; shift ;;
    --no-push) PUSH=false; shift ;;
    --no-cache) NO_CACHE=true; shift ;;
    --prune) PRUNE=true; shift ;;
    --prune-hard) PRUNE_HARD=true; shift ;;
    --build-arg) EXTRA_BUILD_ARGS+=(--build-arg "${2:?}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v docker >/dev/null || die "docker not found"
docker info >/dev/null 2>&1 || die "Docker is not accessible as the current user"
docker buildx version >/dev/null 2>&1 || die "docker buildx not available"
docker buildx inspect "${BUILDER}" >/dev/null 2>&1 || die "Buildx builder '${BUILDER}' not found or unavailable"
[[ -f Dockerfile ]] || die "Dockerfile not found"

if $LOAD && [[ "${PLATFORM}" == *,* ]]; then
  die "--load supports a single platform only"
fi

if $PRUNE_HARD; then
  docker buildx prune --builder "${BUILDER}" --all --force || true
elif $PRUNE; then
  docker container prune -f || true
  docker image prune -f || true
fi

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
IMAGE_VERSION="${IMAGE_VERSION:-${TAG}}"

args=(
  --builder "${BUILDER}"
  --target final
  --platform "${PLATFORM}"
  --tag "${IMAGE}:${TAG}"
  --build-arg "BUILD_DATE=${BUILD_DATE}"
  --build-arg "VCS_REF=${VCS_REF}"
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}"
)

$NO_CACHE && args+=(--no-cache)
if $PUSH; then
  args+=(--push)
elif $LOAD; then
  args+=(--load)
fi
args+=("${EXTRA_BUILD_ARGS[@]}" .)

cat <<SUMMARY
== MiniMax image build ==
Image      : ${IMAGE}:${TAG}
Builder    : ${BUILDER}
Platform   : ${PLATFORM}
Push       : ${PUSH}
Load       : ${LOAD}
No-cache   : ${NO_CACHE}
VCS ref    : ${VCS_REF}
Build date : ${BUILD_DATE}
SUMMARY

echo
echo "== Storage before =="
docker system df || true
docker buildx du --builder "${BUILDER}" || true
df -h /var /srv/buildkit 2>/dev/null || true

docker buildx build "${args[@]}"

echo
if $PUSH; then
  echo "Pushed: ${IMAGE}:${TAG}"
elif $LOAD; then
  echo "Built and loaded locally: ${IMAGE}:${TAG}"
else
  echo "Built successfully; result was not pushed or loaded and remains in BuildKit cache."
fi

echo
echo "== Storage after =="
docker system df || true
docker buildx du --builder "${BUILDER}" || true
df -h /var /srv/buildkit 2>/dev/null || true
