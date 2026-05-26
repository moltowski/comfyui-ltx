# ComfyUI LTX RunPod Template

Daily RunPod template for an LTX-focused ComfyUI environment with persistent network storage.

This image intentionally does not bake model weights or a full ComfyUI workspace. It bootstraps and maintains `/workspace/ComfyUI` at pod startup so the network storage remains the source of truth.

## Runtime Policy

- ComfyUI lives at `/workspace/ComfyUI`.
- `/workspace/ComfyUI/input` and `/workspace/ComfyUI/output` are protected user data and are never deleted or modified by the bootstrap.
- The default ComfyUI ref is `v0.22.2`, matching the known-good pod state from May 24, 2026.
- LTX custom nodes are cloned or fast-forwarded at boot.
- Python requirements are installed at boot for ComfyUI and the LTX node packs.
- A post-boot validation checks the critical LTX node classes through `/object_info`.

## Important Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMFYUI_REF` | `v0.22.2` | Git ref/tag/branch for ComfyUI. |
| `UPDATE_ON_BOOT` | `true` | Update ComfyUI and managed custom nodes before launch. |
| `INSTALL_REQUIREMENTS` | `true` | Install `requirements.txt` for ComfyUI/custom nodes. |
| `VALIDATE_LTX_NODES` | `true` | Check critical node availability after startup. |
| `ENABLE_MANAGER` | `false` | Add `--enable-manager` to ComfyUI launch. |
| `USE_SAGE_ATTENTION` | `true` | Add `--use-sage-attention` when the package imports correctly. |
| `COMFYUI_EXTRA_ARGS` | empty | Extra args appended to ComfyUI. |

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
