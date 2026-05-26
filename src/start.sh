#!/usr/bin/env bash
set -euo pipefail

PY="${PYTHON_BIN:-/opt/venv/bin/python3}"
PIP="$PY -m pip"
NETWORK_VOLUME="${NETWORK_VOLUME:-/workspace}"
COMFY="$NETWORK_VOLUME/ComfyUI"
CUSTOM_NODES="$COMFY/custom_nodes"
COMFYUI_REF="${COMFYUI_REF:-v0.22.2}"
UPDATE_ON_BOOT="${UPDATE_ON_BOOT:-true}"
INSTALL_REQUIREMENTS="${INSTALL_REQUIREMENTS:-true}"
VALIDATE_LTX_NODES="${VALIDATE_LTX_NODES:-true}"
ENABLE_MANAGER="${ENABLE_MANAGER:-false}"
USE_SAGE_ATTENTION="${USE_SAGE_ATTENTION:-true}"
COMFYUI_EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
LOG_FILE="$NETWORK_VOLUME/comfyui.log"
PID_FILE="$NETWORK_VOLUME/comfyui.pid"
NODE_MANIFEST="${NODE_MANIFEST:-/custom_nodes.tsv}"

mkdir -p "$NETWORK_VOLUME"

log() {
  echo "[$(date -Iseconds)] $*"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

run_pip_install() {
  if is_true "$INSTALL_REQUIREMENTS"; then
    log "pip install $*"
    $PIP install "$@"
  fi
}

install_requirements_if_present() {
  local dir="$1"
  if [ -f "$dir/requirements.txt" ]; then
    run_pip_install -r "$dir/requirements.txt"
  fi
  if [ -f "$dir/install.py" ]; then
    log "Running install.py for $dir"
    "$PY" "$dir/install.py"
  fi
}

checkout_ref() {
  local dir="$1"
  local ref="$2"
  git -C "$dir" fetch origin --tags --prune
  if git -C "$dir" rev-parse --verify --quiet "origin/$ref" >/dev/null; then
    git -C "$dir" switch "$ref" 2>/dev/null || git -C "$dir" switch -c "$ref" "origin/$ref"
    git -C "$dir" pull --ff-only || true
  else
    git -C "$dir" switch --detach "$ref"
  fi
}

ensure_comfyui() {
  if [ ! -d "$COMFY/.git" ]; then
    if [ -d "$COMFY" ] && [ "$(find "$COMFY" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
      log "Existing $COMFY is not a git checkout; leaving it untouched."
      return 1
    fi
    log "Cloning ComfyUI into $COMFY"
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
  fi

  if is_true "$UPDATE_ON_BOOT"; then
    log "Checking out ComfyUI ref $COMFYUI_REF"
    checkout_ref "$COMFY" "$COMFYUI_REF"
  fi

  install_requirements_if_present "$COMFY"
}

ensure_custom_node() {
  local folder="$1"
  local url="$2"
  local ref="$3"
  local required="$4"
  local dir="$CUSTOM_NODES/$folder"

  if [ ! -d "$dir/.git" ]; then
    if [ -d "$dir" ]; then
      log "$folder exists but is not git-backed; installing requirements only."
      install_requirements_if_present "$dir"
      return 0
    fi
    log "Cloning $folder"
    git clone "$url" "$dir" || {
      if [ "$required" = "true" ]; then
        log "Required node clone failed: $folder"
        return 1
      fi
      log "Optional node clone failed: $folder"
      return 0
    }
  fi

  if is_true "$UPDATE_ON_BOOT"; then
    log "Updating $folder to $ref"
    checkout_ref "$dir" "$ref" || {
      if [ "$required" = "true" ]; then
        log "Required node update failed: $folder"
        return 1
      fi
      log "Optional node update failed: $folder"
    }
  fi

  install_requirements_if_present "$dir"
}

ensure_custom_nodes() {
  mkdir -p "$CUSTOM_NODES"
  while IFS=$'\t' read -r folder url ref required; do
    case "${folder:-}" in
      ""|\#*) continue ;;
    esac
    ensure_custom_node "$folder" "$url" "$ref" "$required"
  done < "$NODE_MANIFEST"
}

install_runtime_fixes() {
  log "Installing LTX runtime dependency fixes"
  run_pip_install sageattention reportlab rotary-embedding-torch || true

  "$PY" - <<'PY'
mods = ["comfy_aimdo.vram_buffer", "rotary_embedding_torch"]
for mod in mods:
    __import__(mod)
    print(f"{mod}: OK")
PY
}

sage_attention_available() {
  "$PY" - <<'PY' >/dev/null 2>&1
import sageattention
PY
}

clean_non_nodes() {
  log "Cleaning known non-node folders from custom_nodes"
  rm -rf "$CUSTOM_NODES/.ipynb_checkpoints"
}

start_jupyter() {
  log "Starting JupyterLab on port $JUPYTER_PORT"
  jupyter-lab \
    --ip=0.0.0.0 \
    --port="$JUPYTER_PORT" \
    --allow-root \
    --no-browser \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --ServerApp.allow_origin='*' \
    --ServerApp.allow_credentials=True \
    --notebook-dir="$NETWORK_VOLUME" &
}

stop_old_comfyui() {
  if [ -f "$PID_FILE" ]; then
    old_pid="$(cat "$PID_FILE" || true)"
    if [ -n "$old_pid" ]; then
      kill "$old_pid" 2>/dev/null || true
    fi
  fi
  sleep 4
}

start_comfyui() {
  local args=(main.py --listen 0.0.0.0 --port "$COMFYUI_PORT")
  if is_true "$USE_SAGE_ATTENTION"; then
    if sage_attention_available; then
      args+=(--use-sage-attention)
    else
      log "SageAttention import failed; starting without --use-sage-attention"
    fi
  fi
  if is_true "$ENABLE_MANAGER"; then
    args+=(--enable-manager)
  fi
  if [ -n "$COMFYUI_EXTRA_ARGS" ]; then
    # shellcheck disable=SC2206
    args+=($COMFYUI_EXTRA_ARGS)
  fi

  log "Starting ComfyUI on port $COMFYUI_PORT"
  cd "$COMFY"
  nohup "$PY" -u "${args[@]}" > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
}

wait_for_comfyui() {
  local url="http://127.0.0.1:$COMFYUI_PORT"
  local waited=0
  local max_wait="${COMFYUI_START_TIMEOUT:-90}"

  until curl --silent --fail "$url" --output /dev/null; do
    if [ "$waited" -ge "$max_wait" ]; then
      log "ComfyUI did not respond within ${max_wait}s. Logs: $LOG_FILE"
      tail -80 "$LOG_FILE" || true
      return 1
    fi
    log "ComfyUI starting... logs: $LOG_FILE"
    sleep 3
    waited=$((waited + 3))
  done

  log "ComfyUI is up"
}

main() {
  log "ComfyUI LTX template bootstrap"
  log "Network volume: $NETWORK_VOLUME"
  log "ComfyUI ref: $COMFYUI_REF"

  start_jupyter
  ensure_comfyui
  ensure_custom_nodes
  install_runtime_fixes
  clean_non_nodes
  stop_old_comfyui
  start_comfyui
  wait_for_comfyui

  if is_true "$VALIDATE_LTX_NODES"; then
    COMFYUI_URL="http://127.0.0.1:$COMFYUI_PORT" /validate_ltx.sh || {
      log "LTX node validation failed. Check $LOG_FILE"
      tail -120 "$LOG_FILE" || true
      return 1
    }
  fi

  log "Ready"
  exec sleep infinity
}

main "$@"
