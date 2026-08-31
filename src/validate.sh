#!/usr/bin/env bash
set -euo pipefail

# Family-agnostic boot validation for the prod runtime.
#
# The image is a generic ComfyUI runtime; which model families a given pod can
# serve depends entirely on what its network volume carries. So boot validation
# only checks that the server is up and its node graph loaded -- it does NOT
# assume any particular family's nodes are present. Per-family checks belong in
# the deploy smoke-test (submit one workflow of each family via /prompt).
#
# To assert specific node classes on a given pod (e.g. a smoke-test), pass them
# space-separated in VALIDATE_NODE_CLASSES, e.g.:
#   VALIDATE_NODE_CLASSES="MiniMaxH3ImageToVideo VHS_VideoCombine" /validate.sh

URL="${COMFYUI_URL:-http://127.0.0.1:8188}"

# 1. Server reachable.
curl -fsS "$URL/system_stats" >/tmp/comfy_system_stats.json
echo "system_stats OK"

# 2. Node graph loaded (object_info returns a non-trivial catalogue).
curl -fsS "$URL/object_info" >/tmp/comfy_object_info.json
node_count="$(grep -o '"' /tmp/comfy_object_info.json | wc -l)"
if [ "${node_count:-0}" -lt 2 ]; then
  echo "object_info returned an empty catalogue" >&2
  exit 1
fi
echo "object_info OK"

# 3. Optional, caller-supplied node-class assertions (smoke-tests only).
if [ -n "${VALIDATE_NODE_CLASSES:-}" ]; then
  for node in $VALIDATE_NODE_CLASSES; do
    curl -fsS "$URL/object_info/$node" >/dev/null
    echo "$node OK"
  done
fi
