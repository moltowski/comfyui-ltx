#!/usr/bin/env bash
set -euo pipefail

NETWORK_VOLUME="${NETWORK_VOLUME:-/workspace}"
COMFY="${NETWORK_VOLUME}/ComfyUI"
PID_FILE="${NETWORK_VOLUME}/comfyui.pid"

log() {
  echo "[$(date -Iseconds)] $*"
}

if [ "${STOP_COMFY_FOR_UPDATE:-true}" = "true" ]; then
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" || true)"
    if [ -n "$pid" ]; then
      log "Stopping running ComfyUI pid $pid"
      kill "$pid" 2>/dev/null || true
      sleep 4
    fi
  fi
  pkill -f "$COMFY/main.py" 2>/dev/null || true
fi

export FAST_BOOT=false
export UPDATE_ON_BOOT=true
export INSTALL_REQUIREMENTS=true
export RUNTIME_FIXES_ON_BOOT=true
export MAINTENANCE_ONLY=true

/start.sh

log "Update complete. Restart the pod, or run /start.sh to launch ComfyUI again."
