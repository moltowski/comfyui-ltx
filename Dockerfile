FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

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

RUN pip install --no-cache-dir --upgrade pip setuptools wheel packaging && \
    pip install --no-cache-dir --pre \
        torch==2.12.0.dev20260407+cu128 \
        torchvision==0.27.0.dev20260407+cu128 \
        torchaudio==2.11.0.dev20260407+cu128 \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    pip install --no-cache-dir \
        jupyterlab jupyterlab-lsp jupyter-server jupyter-server-terminals \
        ipykernel jupyterlab_code_formatter \
        opencv-python pyyaml requests tqdm huggingface_hub gdown triton \
        comfyui-frontend-package==1.43.18 \
        comfyui-workflow-templates==0.9.82 \
        comfyui-embedded-docs==0.5.0 \
        torchsde einops "transformers[timm]>=4.50.0" tokenizers sentencepiece \
        safetensors "aiohttp>=3.11.8" "yarl>=1.18.0" scipy alembic \
        "SQLAlchemy>=2.0.0" "av>=14.2.0" "comfy-kitchen>=0.2.8" \
        comfy-aimdo==0.3.0 simpleeval blake3 "kornia==0.7.3" spandrel \
        "pydantic~=2.0" "pydantic-settings~=2.0" PyOpenGL glfw \
        sageattention reportlab rotary-embedding-torch wget scikit-image ollama \
        mediapipe color-matcher matplotlib mss opencv-python-headless \
        PyWavelets soundfile ultralytics langdetect redis wand \
        comfyui-manager GitPython

COPY src/start_script.sh /start_script.sh
COPY src/start.sh /start.sh
COPY src/update_ltx.sh /update_ltx.sh
COPY src/validate_ltx.sh /validate_ltx.sh
COPY src/custom_nodes.tsv /custom_nodes.tsv

RUN chmod +x /start_script.sh /start.sh /update_ltx.sh /validate_ltx.sh

CMD ["/start_script.sh"]
