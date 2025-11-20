#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/acworkma/nextjs-sample:latest}"

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
pass() { echo "[PASS] $*"; }

if ! command -v docker >/dev/null 2>&1; then
  err "Docker CLI not found"; exit 1; fi

log "Building image $IMAGE"
docker build -t "$IMAGE" .
log "Pushing image $IMAGE"
docker push "$IMAGE"
pass "Image build & push complete"
