#!/usr/bin/env bash
set -euo pipefail

PY="${PYTHON_BIN:-/opt/venv/bin/python3}"
PIP="$PY -m pip"
export PIP_DEFAULT_TIMEOUT="${PIP_DEFAULT_TIMEOUT:-60}"
export GIT_TERMINAL_PROMPT=0
NETWORK_VOLUME="${NETWORK_VOLUME:-/workspace}"
COMFY="$NETWORK_VOLUME/ComfyUI"
CUSTOM_NODES="$COMFY/custom_nodes"
COMFYUI_REF="${COMFYUI_REF:-v0.22.2}"
UPDATE_ON_BOOT="${UPDATE_ON_BOOT:-false}"
INSTALL_REQUIREMENTS="${INSTALL_REQUIREMENTS:-auto}"
RUNTIME_FIXES_ON_BOOT="${RUNTIME_FIXES_ON_BOOT:-auto}"
VALIDATE_LTX_NODES="${VALIDATE_LTX_NODES:-true}"
STRICT_LTX_VALIDATION="${STRICT_LTX_VALIDATION:-false}"
ENABLE_MANAGER="${ENABLE_MANAGER:-true}"
ENABLE_MANAGER_LEGACY_UI="${ENABLE_MANAGER_LEGACY_UI:-true}"
USE_SAGE_ATTENTION="${USE_SAGE_ATTENTION:-true}"
COMFYUI_EXTRA_ARGS="${COMFYUI_EXTRA_ARGS:-}"
MAINTENANCE_ONLY="${MAINTENANCE_ONLY:-false}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
COMFYUI_PORT="${COMFYUI_PORT:-8188}"
LOG_FILE="$NETWORK_VOLUME/comfyui.log"
PID_FILE="$NETWORK_VOLUME/comfyui.pid"
NODE_MANIFEST="${NODE_MANIFEST:-/custom_nodes.tsv}"
BOOTSTRAPPED_COMFYUI=false

# venv persistence: keep installed pip packages on the network volume so that
# custom-node dependencies survive pod restarts (the baked /opt/venv lives on the
# ephemeral overlay filesystem and is wiped every time the pod is recreated).
PERSIST_VENV="${PERSIST_VENV:-true}"
VENV_PERSIST_DIR="${VENV_PERSIST_DIR:-$NETWORK_VOLUME/venv}"
BAKED_VENV="${BAKED_VENV:-/opt/venv}"
VENV_STAMP_SRC="${VENV_STAMP_SRC:-/opt/venv.stamp}"
REBUILD_VENV="${REBUILD_VENV:-false}"
HEAL_NODE_DEPS="${HEAL_NODE_DEPS:-true}"
VENV_BOOTSTRAPPED=false

mkdir -p "$NETWORK_VOLUME"

log() {
  echo "[$(date -Iseconds)] $*"
}

retry() {
  local attempts="${RETRY_ATTEMPTS:-5}"
  local delay="${RETRY_DELAY:-8}"
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    log "Command failed, retrying in ${delay}s ($n/$attempts): $*"
    sleep "$delay"
    n=$((n + 1))
  done
}

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

run_git() {
  retry run_with_timeout "${GIT_TIMEOUT:-180}" \
    git \
    -c "http.lowSpeedLimit=${GIT_HTTP_LOW_SPEED_LIMIT:-1000}" \
    -c "http.lowSpeedTime=${GIT_HTTP_LOW_SPEED_TIME:-30}" \
    "$@"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

run_pip_install() {
  log "pip install $*"
  retry $PIP install "$@"
}

should_install_requirements() {
  local force="${1:-false}"
  case "$INSTALL_REQUIREMENTS" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    false|FALSE|0|no|NO|n|N) return 1 ;;
    auto|AUTO|"")
      is_true "$force" || is_true "$UPDATE_ON_BOOT" || is_true "$BOOTSTRAPPED_COMFYUI"
      ;;
    *)
      log "Unknown INSTALL_REQUIREMENTS=$INSTALL_REQUIREMENTS; treating as auto."
      is_true "$force" || is_true "$UPDATE_ON_BOOT" || is_true "$BOOTSTRAPPED_COMFYUI"
      ;;
  esac
}

comfy_core_dependencies_available() {
  "$PY" - <<'PY' >/dev/null 2>&1
mods = ["alembic", "sqlalchemy", "comfy_aimdo", "blake3"]
for mod in mods:
    __import__(mod)
PY
}

ltx_runtime_dependencies_available() {
  "$PY" - <<'PY' >/dev/null 2>&1
mods = [
    "rotary_embedding_torch",
    "reportlab",
    "wget",
    "skimage",
    "ollama",
    "mediapipe",
    "color_matcher",
    "matplotlib",
    "mss",
    "cv2",
    "comfyui_manager",
    "git",
    "pywt",
    "soundfile",
]
for mod in mods:
    __import__(mod)
from kornia.geometry.transform.pyramid import pad  # noqa: F401
PY
}

should_run_runtime_fixes() {
  case "$RUNTIME_FIXES_ON_BOOT" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    false|FALSE|0|no|NO|n|N) return 1 ;;
    auto|AUTO|"")
      is_true "$UPDATE_ON_BOOT" || is_true "$BOOTSTRAPPED_COMFYUI" || is_true "$INSTALL_REQUIREMENTS" || ! ltx_runtime_dependencies_available
      ;;
    *)
      log "Unknown RUNTIME_FIXES_ON_BOOT=$RUNTIME_FIXES_ON_BOOT; treating as auto."
      is_true "$UPDATE_ON_BOOT" || is_true "$BOOTSTRAPPED_COMFYUI" || is_true "$INSTALL_REQUIREMENTS" || ! ltx_runtime_dependencies_available
      ;;
  esac
}

install_requirements_if_present() {
  local dir="$1"
  local force="${2:-false}"
  if ! should_install_requirements "$force"; then
    if [ "$dir" = "$COMFY" ] && ! comfy_core_dependencies_available; then
      log "ComfyUI core dependencies missing; installing requirements for $dir"
    else
      log "Skipping requirements for $dir"
      return 0
    fi
  fi
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
  run_git -C "$dir" fetch origin --tags --prune
  if git -C "$dir" rev-parse --verify --quiet "origin/$ref" >/dev/null; then
    git -C "$dir" switch "$ref" 2>/dev/null || git -C "$dir" switch -c "$ref" "origin/$ref"
    run_git -C "$dir" pull --ff-only || true
  else
    git -C "$dir" switch --detach "$ref"
  fi
}

ensure_comfyui() {
  local cloned=false
  if [ ! -d "$COMFY/.git" ]; then
    if [ -d "$COMFY" ] && [ "$(find "$COMFY" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
      log "Existing $COMFY is not a git checkout; leaving it untouched."
      return 1
    fi
    log "Cloning ComfyUI into $COMFY"
    run_git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
    cloned=true
    BOOTSTRAPPED_COMFYUI=true
  fi

  if is_true "$UPDATE_ON_BOOT" || is_true "$cloned"; then
    log "Checking out ComfyUI ref $COMFYUI_REF"
    checkout_ref "$COMFY" "$COMFYUI_REF"
  fi

  install_requirements_if_present "$COMFY" "$cloned"
}

ensure_custom_node() {
  local folder="$1"
  local url="$2"
  local ref="$3"
  local required="$4"
  local dir="$CUSTOM_NODES/$folder"
  local cloned=false

  if [ ! -d "$dir/.git" ]; then
    if [ -d "$dir" ]; then
      log "$folder exists but is not git-backed."
      install_requirements_if_present "$dir" false
      return 0
    fi
    log "Cloning $folder"
    run_git clone "$url" "$dir" || {
      if [ "$required" = "true" ]; then
        log "Required node clone failed: $folder"
        return 1
      fi
      log "Optional node clone failed: $folder"
      return 0
    }
    cloned=true
  fi

  if is_true "$UPDATE_ON_BOOT" || is_true "$cloned"; then
    log "Updating $folder to $ref"
    checkout_ref "$dir" "$ref" || {
      log "Node update failed for $folder; continuing with existing checkout."
    }
  fi

  install_requirements_if_present "$dir" "$cloned"
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
  if ! should_run_runtime_fixes; then
    log "Skipping LTX runtime dependency fixes"
    return 0
  fi

  log "Installing LTX runtime dependency fixes"
  run_pip_install sageattention reportlab rotary-embedding-torch "kornia==0.7.3" || true
  run_pip_install wget scikit-image ollama || true
  run_pip_install mediapipe || true
  run_pip_install color-matcher matplotlib mss opencv-python-headless || true
  run_pip_install PyWavelets soundfile ultralytics langdetect redis wand || true
  run_pip_install --pre comfyui-manager GitPython || true

  "$PY" - <<'PY'
mods = ["comfy_aimdo.vram_buffer", "rotary_embedding_torch", "kornia", "comfyui_manager", "git", "pywt", "soundfile"]
for mod in mods:
    try:
        __import__(mod)
        print(f"{mod}: OK")
    except Exception as exc:
        print(f"{mod}: unavailable ({exc})")
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
    if is_true "$ENABLE_MANAGER_LEGACY_UI"; then
      args+=(--enable-manager-legacy-ui)
    fi
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
  local max_wait="${COMFYUI_START_TIMEOUT:-600}"

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

persist_venv() {
  if ! is_true "$PERSIST_VENV"; then
    log "venv persistence disabled (PERSIST_VENV=$PERSIST_VENV)"
    return 0
  fi

  # On a fresh pod the baked venv is a real directory. If it is already a symlink
  # we have nothing to do (e.g. persist_venv ran twice in the same boot).
  if [ -L "$BAKED_VENV" ]; then
    log "venv already symlinked to $(readlink -f "$BAKED_VENV")"
    return 0
  fi

  local stamp_dst="$VENV_PERSIST_DIR/.image_stamp"
  local want_copy=false
  if [ ! -x "$VENV_PERSIST_DIR/bin/python3" ]; then
    log "No persisted venv at $VENV_PERSIST_DIR; copying baked venv (first boot, slow over network storage)"
    want_copy=true
  elif is_true "$REBUILD_VENV"; then
    log "REBUILD_VENV=true; refreshing persisted venv from image"
    want_copy=true
  elif [ -f "$VENV_STAMP_SRC" ] && [ -f "$stamp_dst" ] && ! cmp -s "$VENV_STAMP_SRC" "$stamp_dst"; then
    log "Image venv stamp changed ($(cat "$stamp_dst") -> $(cat "$VENV_STAMP_SRC")); refreshing persisted venv"
    want_copy=true
  fi

  if is_true "$want_copy"; then
    rm -rf "$VENV_PERSIST_DIR.partial"
    log "Copying $BAKED_VENV -> $VENV_PERSIST_DIR (this can take several minutes the first time)"
    cp -a "$BAKED_VENV" "$VENV_PERSIST_DIR.partial"
    if [ -f "$VENV_STAMP_SRC" ]; then
      cp -f "$VENV_STAMP_SRC" "$VENV_PERSIST_DIR.partial/.image_stamp"
    fi
    rm -rf "$VENV_PERSIST_DIR"
    mv "$VENV_PERSIST_DIR.partial" "$VENV_PERSIST_DIR"
    VENV_BOOTSTRAPPED=true
    log "Persisted venv ready at $VENV_PERSIST_DIR"
  else
    log "Reusing persisted venv at $VENV_PERSIST_DIR"
  fi

  # Replace the ephemeral baked venv with a symlink to the persisted one so that
  # every hard-coded /opt/venv path (shebangs, pip, jupyter, ComfyUI Manager)
  # resolves to the network volume and pip installs persist across restarts.
  rm -rf "$BAKED_VENV"
  ln -s "$VENV_PERSIST_DIR" "$BAKED_VENV"
  log "Symlinked $BAKED_VENV -> $VENV_PERSIST_DIR; pip installs now persist across restarts"
}

heal_node_deps() {
  # One-time only: when the venv was just bootstrapped from the image it lacks the
  # Python deps of nodes the user installed on storage (outside custom_nodes.tsv).
  # Install every present node's requirements.txt once; afterwards they persist in
  # the storage venv, so this never runs again on subsequent boots.
  if ! is_true "$HEAL_NODE_DEPS"; then
    log "Node dependency heal disabled (HEAL_NODE_DEPS=$HEAL_NODE_DEPS)"
    return 0
  fi
  if ! is_true "$VENV_BOOTSTRAPPED"; then
    log "venv already populated; skipping one-time node dependency heal"
    return 0
  fi
  if [ ! -d "$CUSTOM_NODES" ]; then
    return 0
  fi

  # Pin the critical stack so node requirements can't downgrade/break torch & numpy.
  local constraints="/tmp/heal-constraints.txt"
  "$PY" -m pip freeze 2>/dev/null \
    | grep -iE '^(torch|torchvision|torchaudio|numpy)==' > "$constraints" || true

  log "Freshly bootstrapped venv: healing node dependencies (one-time pass over all custom_nodes)"
  local dir name req
  for dir in "$CUSTOM_NODES"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    req="${dir%/}/requirements.txt"
    if [ -f "$req" ]; then
      log "Heal deps: $name"
      $PIP install -c "$constraints" -r "$req" \
        || log "Heal deps failed for $name (continuing)"
    fi
  done
  log "One-time node dependency heal complete"
}

main() {
  log "ComfyUI LTX template bootstrap"
  log "Network volume: $NETWORK_VOLUME"
  log "ComfyUI ref: $COMFYUI_REF"
  log "Update on boot: $UPDATE_ON_BOOT"
  log "Install requirements: $INSTALL_REQUIREMENTS"
  log "Persist venv: $PERSIST_VENV ($VENV_PERSIST_DIR)"

  persist_venv
  ensure_comfyui
  ensure_custom_nodes
  install_runtime_fixes
  heal_node_deps
  clean_non_nodes

  if is_true "$MAINTENANCE_ONLY"; then
    log "Maintenance complete"
    exit 0
  fi

  start_jupyter
  stop_old_comfyui
  start_comfyui
  wait_for_comfyui

  if is_true "$VALIDATE_LTX_NODES"; then
    COMFYUI_URL="http://127.0.0.1:$COMFYUI_PORT" /validate_ltx.sh || {
      log "LTX node validation failed. Check $LOG_FILE"
      tail -120 "$LOG_FILE" || true
      if is_true "$STRICT_LTX_VALIDATION"; then
        return 1
      fi
      log "Continuing because STRICT_LTX_VALIDATION is false."
    }
  fi

  log "Ready"
  exec sleep infinity
}

main "$@"
