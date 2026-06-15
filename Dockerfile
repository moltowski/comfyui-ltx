FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

LABEL org.opencontainers.image.source="https://github.com/moltowski/comfyui-ltx" \
      org.opencontainers.image.description="ComfyUI LTX template (env only; ComfyUI/nodes/models live on the network volume)"

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev python3-pip \
        build-essential gcc g++ ninja-build git git-lfs curl wget aria2 ffmpeg \
        libgl1 libglib2.0-0 libgoogle-perftools4 ca-certificates vim \
        imagemagick libmagickwand-dev && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    python3.12 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:$PATH"

# Build tooling for pip itself.
RUN pip install --no-cache-dir --upgrade pip setuptools wheel packaging

# --- Dependency install is split into several layers on purpose ---------------
# A single giant `pip install` produced one ~7 GB image layer, which RunPod pulls
# as a single stream. Cold pulls on the (few, busy) hosts pinned by our network
# volume then sit near 0% for a long time. Splitting into ordered layers lets the
# Docker daemon pull up to 3 layers in parallel, makes cold pulls much faster, and
# means a change in one dependency group only rebuilds/repushes that one layer.
# Ordered most-stable -> most-volatile for build-cache reuse.
# The exact package set is unchanged vs the previous single-layer build, so the
# resulting venv is byte-identical in intent and VENV_STAMP stays valid (no slow
# venv re-copy on existing pods).

# Layer 1: PyTorch (largest, changes rarely) + triton.
RUN pip install --no-cache-dir --pre \
        torch==2.12.0.dev20260407+cu128 \
        torchvision==0.27.0.dev20260407+cu128 \
        torchaudio==2.11.0.dev20260407+cu128 \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    pip install --no-cache-dir triton

# Layer 2: ComfyUI core ecosystem + frequently-needed runtime deps.
RUN pip install --no-cache-dir \
        comfyui-frontend-package==1.43.18 \
        comfyui-workflow-templates==0.9.82 \
        comfyui-embedded-docs==0.5.0 \
        torchsde einops "transformers[timm]>=4.50.0" tokenizers sentencepiece \
        safetensors "aiohttp>=3.11.8" "yarl>=1.18.0" scipy alembic \
        "SQLAlchemy>=2.0.0" "av>=14.2.0" "comfy-kitchen>=0.2.8" \
        comfy-aimdo==0.3.0 simpleeval blake3 "kornia==0.7.3" spandrel \
        "pydantic~=2.0" "pydantic-settings~=2.0" PyOpenGL glfw \
        huggingface_hub gdown pyyaml requests tqdm

# Layer 3: LTX / custom-node runtime deps (the other heavy group: mediapipe,
# opencv, ultralytics, scikit-image). Pulled in parallel with layer 1.
RUN pip install --no-cache-dir \
        sageattention reportlab rotary-embedding-torch wget scikit-image ollama \
        mediapipe color-matcher matplotlib mss \
        opencv-python opencv-python-headless \
        PyWavelets soundfile ultralytics langdetect redis wand

# Layer 4: Jupyter stack + ComfyUI Manager tooling.
RUN pip install --no-cache-dir \
        jupyterlab jupyterlab-lsp jupyter-server jupyter-server-terminals \
        ipykernel jupyterlab_code_formatter \
        comfyui-manager GitPython

# Stamp identifying the baked dependency set. start.sh compares this against the
# copy stored on the network volume; bump VENV_STAMP whenever the pip deps above
# change so existing pods refresh their persisted venv automatically.
# NOTE: unchanged from the previous build because the package set is identical.
ARG VENV_STAMP=2026-06-12.1
RUN echo "$VENV_STAMP" > /opt/venv.stamp

COPY src/start_script.sh /start_script.sh
COPY src/start.sh /start.sh
COPY src/update_ltx.sh /update_ltx.sh
COPY src/validate_ltx.sh /validate_ltx.sh
COPY src/custom_nodes.tsv /custom_nodes.tsv

RUN chmod +x /start_script.sh /start.sh /update_ltx.sh /validate_ltx.sh

CMD ["/start_script.sh"]
