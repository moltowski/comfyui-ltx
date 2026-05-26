#!/usr/bin/env bash
set -euo pipefail

URL="${COMFYUI_URL:-http://127.0.0.1:8188}"

curl -fsS "$URL/system_stats" >/tmp/comfy_system_stats.json

nodes=(
  LTX2MemoryEfficientSageAttentionPatch
  LTXVChunkFeedForward
  ModelMemoryUsageFactorOverride
  AudioToFrameCount
  MelBandRoFormerModelLoader
  MelBandRoFormerSampler
  LTXDirector
  LTXDirectorGuide
  VHS_VideoCombine
  VAELoaderKJ
  LTXVReferenceAudio
)

for node in "${nodes[@]}"; do
  curl -fsS "$URL/object_info/$node" >/dev/null
  echo "$node OK"
done
