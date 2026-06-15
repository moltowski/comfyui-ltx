# ComfyUI LTX RunPod Template

Daily RunPod template for an LTX-focused ComfyUI environment with persistent network storage.

This image intentionally does not bake model weights or a full ComfyUI workspace. The network storage remains the source of truth, and daily boots prefer launching the existing `/workspace/ComfyUI` checkout without doing maintenance work first.

## Runtime Policy

- ComfyUI lives at `/workspace/ComfyUI`.
- `/workspace/ComfyUI/input` and `/workspace/ComfyUI/output` are protected user data and are never deleted or modified by the bootstrap.
- The default ComfyUI ref is `v0.22.2`, matching the known-good pod state from May 24, 2026.
- If `/workspace/ComfyUI` is missing, the template bootstraps ComfyUI and the managed LTX nodes.
- If `/workspace/ComfyUI` already exists, `FAST_BOOT=true` (default) launches it directly and skips every git / pip / node-update / runtime-fix step — the fastest possible boot, and nothing on storage is touched.
- LTX custom nodes are updated only when `UPDATE_ON_BOOT=true` or when running `/update_ltx.sh`.
- Python requirements are installed only on first bootstrap, explicit updates, or when `INSTALL_REQUIREMENTS=true` (default is now `false`, never `auto`).
- Runtime dependency fixes run only on first bootstrap, explicit updates, or when `RUNTIME_FIXES_ON_BOOT=true` (default is now `false`). The fully-baked image venv already provides them, so a normal boot never needs them.
- The managed optional nodes include the Z-Image and LTX workflow helpers used on the daily storage, such as RES4LYF, rgthree, CRT-Nodes, Fill-Nodes, PromptRelay, CameraForensicRealism, and quantum spectral nodes.
- A post-boot validation checks the critical LTX node classes through `/object_info`.

## Persistent venv (no more reinstalling nodes on restart)

The baked `/opt/venv` lives on the pod's ephemeral overlay filesystem, so every stop/start used to wipe any pip package that was not baked into the image — breaking every custom node installed on the network storage outside this template.

The template now keeps the Python environment on the network volume:

- On the first boot the baked `/opt/venv` is copied once to `/workspace/venv` (15 GB, slow the first time only).
- `/opt/venv` is then replaced by a symlink to `/workspace/venv`, so every hard-coded `/opt/venv` path (pip, JupyterLab, ComfyUI Manager) transparently resolves to storage. From then on, **any package you install — including via ComfyUI Manager — persists across restarts.**
- Right after the venv is first bootstrapped, a one-time heal installs `requirements.txt` for every node present under `custom_nodes/`, so nodes you added outside this template get their dependencies once. A constraints file pins `torch`/`torchvision`/`torchaudio`/`numpy` so node requirements cannot downgrade the core stack. This heal never runs again on later boots.
- The image carries a stamp at `/opt/venv.stamp`; when you rebuild the image with changed baked deps (bump `VENV_STAMP`), existing pods refresh their persisted venv automatically on the next boot.

The result: the template's only steady-state job is to boot the pod. ComfyUI, custom nodes, and their Python dependencies all live on the network storage.

## Important Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `FAST_BOOT` | `true` | When `/workspace/ComfyUI` exists, skip all git/pip/node-update/fix steps and launch directly. Set `false` to force the reconcile path. |
| `COMFYUI_REF` | `v0.22.2` | Git ref/tag/branch for ComfyUI. |
| `PERSIST_VENV` | `true` | Keep the Python venv on the network volume (`/workspace/venv`) so pip installs survive restarts. |
| `VENV_PERSIST_DIR` | `$NETWORK_VOLUME/venv` | Where the persisted venv is stored. |
| `REBUILD_VENV` | `false` | Force-refresh the persisted venv from the baked image on next boot. |
| `HEAL_NODE_DEPS` | `true` | One-time install of every `custom_nodes/*/requirements.txt` when the venv is first bootstrapped. |
| `UPDATE_ON_BOOT` | `false` | Update ComfyUI and managed custom nodes before launch. |
| `INSTALL_REQUIREMENTS` | `false` | Install requirements on first bootstrap or explicit update. Use `true` to force, `auto` to restore the old probe-based behavior. |
| `RUNTIME_FIXES_ON_BOOT` | `false` | Install small runtime fix packages. Use `true` to force, `auto` to install only when the LTX dependency check fails. |
| `VALIDATE_LTX_NODES` | `true` | Check critical node availability after startup. |
| `STRICT_LTX_VALIDATION` | `false` | Fail the pod when validation is missing a critical LTX node. |
| `ENABLE_MANAGER` | `true` | Add `--enable-manager` to ComfyUI launch. |
| `ENABLE_MANAGER_LEGACY_UI` | `true` | Add `--enable-manager-legacy-ui` so the visible Manager menu is exposed in current ComfyUI builds. |
| `USE_SAGE_ATTENTION` | `true` | Add `--use-sage-attention` when the package imports correctly. |
| `COMFYUI_EXTRA_ARGS` | empty | Extra args appended to ComfyUI. |
| `COMFYUI_START_TIMEOUT` | `600` | Seconds to wait for ComfyUI before treating startup as failed. |
| `PIP_DEFAULT_TIMEOUT` | `60` | Default pip network timeout. |
| `RETRY_ATTEMPTS` | `5` | Retry count for git and pip network operations. |
| `RETRY_DELAY` | `8` | Seconds between git/pip retries. |
| `GIT_TIMEOUT` | `180` | Max seconds for one git network command before retrying. |
| `GIT_HTTP_LOW_SPEED_TIME` | `30` | Abort a slow git HTTP transfer after this many seconds. |
| `GIT_HTTP_LOW_SPEED_LIMIT` | `1000` | Bytes/second threshold for git low-speed detection. |

## Manual Updates

Daily pod starts should be fast-path launches. When you actually want maintenance, SSH into the pod and run:

```bash
/update_ltx.sh
```

That stops ComfyUI, updates ComfyUI and the managed LTX nodes, installs requirements, applies runtime fixes, then exits. Restart the pod afterwards to return to the normal fast boot path.

## Docker

The dependency install is split into several image layers (PyTorch / ComfyUI core / LTX node deps / Jupyter) instead of one ~7 GB layer. The Docker daemon pulls up to three layers in parallel, so cold pulls on the few hosts pinned by the network volume are much faster, and changing one dependency group only rebuilds/repushes that layer.

The GitHub Action publishes to both Docker Hub and GHCR:

```text
moltowski/comfyui-ltx:latest        # ONLY from the main branch
moltowski/comfyui-ltx:<branch-or-tag>
ghcr.io/moltowski/comfyui-ltx:latest
ghcr.io/moltowski/comfyui-ltx:<branch-or-tag>
```

`latest` is published **only from `main`**. Pushing a test branch (e.g. `fast-deploy`) or a `v*` tag publishes an image tagged after that ref **without overwriting `latest`**, so a new build can be validated on a throwaway pod before being promoted. Point the RunPod template at `ghcr.io/moltowski/comfyui-ltx:fast-deploy` to test, then merge to `main` to promote to `latest`.

## RunPod Ports

- `8188`: ComfyUI
- `8888`: JupyterLab

## Notes

This replaces the old Wan template for LTX work. It avoids Wan model downloads, Wan workflow copies, and old pins such as ComfyUI `v0.17.2`.
