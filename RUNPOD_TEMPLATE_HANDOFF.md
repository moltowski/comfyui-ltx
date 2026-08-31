# RunPod ComfyUI Prod Template — Operational notes

> The original handoff here was a 2026-05 snapshot of the (then LTX-named) template.
> It is **superseded by [`README.md`](README.md)**, which is the authoritative
> description of the current prod runtime (env-only image, volume = source of truth,
> ComfyUI v0.34.2, `latest`/`prod` pointers). This file now keeps only the
> operational troubleshooting notes, which are still accurate.

## Boot / launch policy (summary)

- Image = generic ComfyUI runtime; it bakes **no models and no ComfyUI workspace**. Everything durable (ComfyUI, custom nodes, models, venv) lives on the network volume at `/workspace`.
- Normal boot: `FAST_BOOT=true` launches whatever is already on the volume and touches nothing — it does **not** read `custom_nodes.tsv` or run any git/pip step.
- `custom_nodes.tsv` is only consulted when **provisioning a fresh/empty volume** (first bootstrap or maintenance), never on a warm boot.
- Maintenance (update ComfyUI/nodes): SSH in and run `/update.sh`, or boot once with `UPDATE_ON_BOOT=true`.

Full env-var reference and the `latest`/`prod` publishing model are in `README.md`.

## Troubleshooting

**Slow boot is not necessarily a crash.** ComfyUI loads many custom nodes and some do network checks at startup. Watch progress before declaring the pod dead:

```bash
tail -f /workspace/comfyui.log
curl http://127.0.0.1:8188/system_stats
/validate.sh
```

**ComfyUI won't start** — inspect the log and running processes:

```bash
tail -120 /workspace/comfyui.log
pgrep -af main.py
cat /workspace/comfyui.pid
```

**Database lock:**

```text
Could not acquire lock on database '/workspace/ComfyUI/user/comfyui.db'
```

Means two ComfyUI processes are running. Confirm with `pgrep -af main.py`, kill the old one, then restart.

**A Python dependency is missing at boot** — add it to the Dockerfile, and to `install_runtime_fixes()` in `src/start.sh` if existing pods also need the repair. Do **not** bake frequently-changing custom nodes into the image; keep them in `src/custom_nodes.tsv` + the volume so they update without a rebuild.
