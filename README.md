# ComfyUI LTX RunPod Template

Daily RunPod template for an LTX-focused ComfyUI environment with persistent network storage.

This image intentionally does not bake model weights or a full ComfyUI workspace. The network storage remains the source of truth, and daily boots prefer launching the existing `/workspace/ComfyUI` checkout without doing maintenance work first.

## Runtime Policy

- ComfyUI lives at `/workspace/ComfyUI`.
- `/workspace/ComfyUI/input` and `/workspace/ComfyUI/output` are protected user data and are never deleted or modified by the bootstrap.
- The default ComfyUI ref is `v0.22.2`, matching the known-good pod state from May 24, 2026.
- If `/workspace/ComfyUI` is missing, the template bootstraps ComfyUI and the managed LTX nodes.
- If `/workspace/ComfyUI` already exists, the template starts it as-is by default.
- LTX custom nodes are updated only when `UPDATE_ON_BOOT=true` or when running `/update_ltx.sh`.
- Python requirements are installed for first bootstrap, explicit updates, or when `INSTALL_REQUIREMENTS=true`.
- A post-boot validation checks the critical LTX node classes through `/object_info`.

## Important Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMFYUI_REF` | `v0.22.2` | Git ref/tag/branch for ComfyUI. |
| `UPDATE_ON_BOOT` | `false` | Update ComfyUI and managed custom nodes before launch. |
| `INSTALL_REQUIREMENTS` | `auto` | Install requirements on first bootstrap or explicit update. Use `true` to force, `false` to skip. |
| `RUNTIME_FIXES_ON_BOOT` | `auto` | Install small runtime fix packages on first bootstrap or explicit update. |
| `VALIDATE_LTX_NODES` | `true` | Check critical node availability after startup. |
| `STRICT_LTX_VALIDATION` | `false` | Fail the pod when validation is missing a critical LTX node. |
| `ENABLE_MANAGER` | `false` | Add `--enable-manager` to ComfyUI launch. |
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

The GitHub Action publishes:

```text
moltowski/comfyui-ltx:latest
moltowski/comfyui-ltx:<branch-or-tag>
```

## RunPod Ports

- `8188`: ComfyUI
- `8888`: JupyterLab

## Notes

This replaces the old Wan template for LTX work. It avoids Wan model downloads, Wan workflow copies, and old pins such as ComfyUI `v0.17.2`.
