FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev python3-pip \
        build-essential gcc g++ ninja-build git git-lfs curl wget aria2 ffmpeg \
        libgl1 libglib2.0-0 libgoogle-perftools4 ca-certificates vim && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    python3.12 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip setuptools wheel packaging && \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    pip install \
        jupyterlab jupyterlab-lsp jupyter-server jupyter-server-terminals \
        ipykernel jupyterlab_code_formatter \
        opencv-python pyyaml requests tqdm huggingface_hub gdown triton

COPY src/start_script.sh /start_script.sh
COPY src/start.sh /start.sh
COPY src/validate_ltx.sh /validate_ltx.sh
COPY src/custom_nodes.tsv /custom_nodes.tsv

RUN chmod +x /start_script.sh /start.sh /validate_ltx.sh

CMD ["/start_script.sh"]
