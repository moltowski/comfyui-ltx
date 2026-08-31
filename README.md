# ComfyUI Prod RunPod Template

Production RunPod runtime for ComfyUI with persistent network storage.

This is a generic ComfyUI runtime image. It deliberately bakes **no model weights and no ComfyUI workspace** — only the OS, Python environment, and boot scripts. ComfyUI, custom nodes, and models all live on the network volume, which is the source of truth. Which model families a given pod can serve (WAN 2.2, MiniMax H3, Krea/FinePorn, …) depends entirely on what its volume carries, not on the image. A normal boot launches the existing `/workspace/ComfyUI` checkout and does no maintenance work first.

## Runtime Policy

- ComfyUI lives at `/workspace/ComfyUI`.
- `/workspace/ComfyUI/input` and `/workspace/ComfyUI/output` are protected user data and are never deleted or modified by the bootstrap.
- The default ComfyUI ref is `v0.34.2`.
- If `/workspace/ComfyUI` is missing, the template bootstraps ComfyUI and the managed nodes.
- If `/workspace/ComfyUI` already exists, `FAST_BOOT=true` (default) launches it directly and skips every git / pip / node-update / runtime-fix step — the fastest possible boot, and nothing on storage is touched.
- Custom nodes are updated only when `UPDATE_ON_BOOT=true` or when running `/update.sh`.
- Python requirements are installed only on first bootstrap, explicit updates, or when `INSTALL_REQUIREMENTS=true` (default is `false`, never `auto`).
- Runtime dependency fixes run only on first bootstrap, explicit updates, or when `RUNTIME_FIXES_ON_BOOT=true` (default `false`). The baked image venv already provides them, so a normal boot never needs them.
- Post-boot validation is **family-agnostic**: it checks that the server is up and its node graph loaded, nothing more. Per-family node assertions belong in the deploy smoke-test (submit one workflow of each family via `/prompt`); `/validate.sh` accepts an optional `VALIDATE_NODE_CLASSES` list for that.

## Persistent venv (no reinstalling nodes on restart)

The baked `/opt/venv` lives on the pod's ephemeral overlay filesystem, so every stop/start would otherwise wipe any pip package not baked into the image — breaking any custom node installed on the network storage outside this template.

The template keeps the Python environment on the network volume instead:

- On the first boot the baked `/opt/venv` is copied once to `/workspace/venv` (~15 GB, slow the first time only).
- `/opt/venv` is then replaced by a symlink to `/workspace/venv`, so every hard-coded `/opt/venv` path (pip, JupyterLab, ComfyUI Manager) resolves to storage. From then on, **any package you install — including via ComfyUI Manager — persists across restarts.**
- Right after the venv is first bootstrapped, a one-time heal installs `requirements.txt` for every node present under `custom_nodes/`, so nodes added outside this template get their dependencies once. A constraints file pins `torch`/`torchvision`/`torchaudio`/`numpy` so node requirements cannot downgrade the core stack. This heal never runs again on later boots.
- The image carries a stamp at `/opt/venv.stamp`; when you rebuild the image with changed baked deps (bump `VENV_STAMP`), existing pods refresh their persisted venv automatically on the next boot.

The result: the template's only steady-state job is to boot the pod. ComfyUI, custom nodes, and their Python dependencies all live on the network storage.

## Important Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `FAST_BOOT` | `true` | When `/workspace/ComfyUI` exists, skip all git/pip/node-update/fix steps and launch directly. Set `false` to force the reconcile path. |
| `COMFYUI_REF` | `v0.34.2` | Git ref/tag/branch for ComfyUI. |
| `PERSIST_VENV` | `true` | Keep the Python venv on the network volume (`/workspace/venv`) so pip installs survive restarts. |
| `VENV_PERSIST_DIR` | `$NETWORK_VOLUME/venv` | Where the persisted venv is stored. |
| `REBUILD_VENV` | `false` | Force-refresh the persisted venv from the baked image on next boot. |
| `HEAL_NODE_DEPS` | `true` | One-time install of every `custom_nodes/*/requirements.txt` when the venv is first bootstrapped. |
| `UPDATE_ON_BOOT` | `false` | Update ComfyUI and managed custom nodes before launch. |
| `INSTALL_REQUIREMENTS` | `false` | Install requirements on first bootstrap or explicit update. `true` to force, `auto` for the old probe-based behavior. |
| `RUNTIME_FIXES_ON_BOOT` | `false` | Install small runtime fix packages. `true` to force, `auto` to install only when the dependency check fails. |
| `VALIDATE_NODES` | `true` | Run the family-agnostic post-boot validation. (Old name `VALIDATE_LTX_NODES` still honoured.) |
| `STRICT_VALIDATION` | `false` | Fail the pod if validation fails. (Old name `STRICT_LTX_VALIDATION` still honoured.) |
| `VALIDATE_NODE_CLASSES` | empty | Optional space-separated node classes to assert in `/validate.sh` (smoke-tests). |
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
/update.sh
```

That stops ComfyUI, updates ComfyUI and the managed nodes, installs requirements, applies runtime fixes, then exits. Restart the pod afterwards to return to the normal fast boot path.

## Docker

The dependency install is split into several image layers (PyTorch / ComfyUI core / custom-node deps / Jupyter) instead of one ~7 GB layer. The Docker daemon pulls up to three layers in parallel, so cold pulls on the few hosts pinned by the network volume are much faster, and changing one dependency group only rebuilds/repushes that layer.

The GitHub Action publishes to both Docker Hub and GHCR, with **two protected pointers**:

```text
moltowski/comfyui-prod:latest          # ONLY from the main branch
moltowski/comfyui-prod:prod            # ONLY from a prod-* git tag (what production runs)
moltowski/comfyui-prod:prod-2026-08-31 # immutable dated build behind :prod
moltowski/comfyui-prod:<branch-or-tag> # any other branch/tag build (for testing)
ghcr.io/moltowski/comfyui-prod:…       # same tags on GHCR
```

- `latest` is published **only from `main`**. A test branch or a `v*` tag publishes an image tagged after that ref **without touching `latest`**, so a new build can be validated on a throwaway pod before being promoted.
- `prod` is the image **production runs**, and it moves **only** when you push a `prod-*` git tag:

  ```bash
  git tag prod-2026-08-31 && git push origin prod-2026-08-31
  ```

  That single push builds the image and tags it both `prod-2026-08-31` (immutable, reproducible) and `prod` (the moving pointer prod pods reference). A routine push to `main` can never move `prod`.

## RunPod Ports

- `8188`: ComfyUI
- `8888`: JupyterLab (token-less — keep it private, behind the RunPod proxy only; never expose it another way)
