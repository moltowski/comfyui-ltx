# RunPod ComfyUI LTX Template Handoff

Date: 2026-05-28

## Objectif

Ce template remplace l'ancien template WAN par un template ComfyUI oriente LTX. Le but est de pouvoir lancer un pod RunPod connecte au network storage et retrouver un environnement exploitable sans devoir reinstaller manuellement les dependances et les custom nodes a chaque demarrage.

Le choix retenu est hybride:

- L'image Docker contient la base stable: CUDA, Python, PyTorch nightly CUDA 12.8, dependances ComfyUI/LTX frequentes, scripts de boot.
- Le network storage garde le checkout ComfyUI, les custom nodes, les modeles et les logs.
- Les mises a jour de ComfyUI/nodes restent pilotables au boot via variables d'environnement, sans devoir rebuilder l'image Docker a chaque update de node.

## Repositories et images

Repo local principal:

```text
D:\comfyui-ltx
```

Repo GitHub cible:

```text
moltowski/comfyui-ltx
```

Images cible:

```text
moltowski/comfyui-ltx:latest
ghcr.io/moltowski/comfyui-ltx:latest
```

Etat Git local au 2026-05-28:

```text
main...origin/main [ahead 1]
0f8c3de Harden fast boot dependency checks
```

Important: le commit local existe mais n'a pas encore ete pousse. Le push a ete bloque par des credentials GitHub locaux qui n'avaient pas le droit d'ecriture sur `moltowski/comfyui-ltx`.

## Fichiers importants

```text
Dockerfile
.github/workflows/docker-build.yml
src/start.sh
src/start_script.sh
src/update_ltx.sh
src/validate_ltx.sh
src/custom_nodes.tsv
README.md
```

## Ce qui a ete modifie dans le template LTX

### Dockerfile

Base:

```text
nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04
```

Python:

```text
Python 3.12
/opt/venv
```

PyTorch:

```text
torch==2.12.0.dev20260407+cu128
torchvision==0.27.0.dev20260407+cu128
torchaudio==2.11.0.dev20260407+cu128
```

Dependances ajoutees/preinstallees pour eviter les reinstallations recurrentes:

```text
SQLAlchemy
alembic
comfy-aimdo
blake3
kornia==0.7.3
sageattention
reportlab
rotary-embedding-torch
wget
scikit-image
ollama
mediapipe
color-matcher
matplotlib
mss
opencv-python-headless
comfyui-manager
GitPython
```

Raison: plusieurs pods echouaient ou redemarraient avec des nodes manquants, notamment autour de ComfyUI core, LTXVideo, Manager et KJNodes.

### start.sh

Le script de boot gere maintenant:

- creation/utilisation de `/workspace/ComfyUI`
- clone de ComfyUI si absent
- checkout de `COMFYUI_REF`
- clone/update des custom nodes depuis `src/custom_nodes.tsv`
- installation conditionnelle des `requirements.txt`
- installation des fixes runtime LTX si necessaire
- demarrage JupyterLab
- demarrage ComfyUI
- activation de ComfyUI Manager par defaut
- validation des nodes LTX critiques apres demarrage

Variables principales:

```text
NETWORK_VOLUME=/workspace
COMFYUI_REF=v0.22.2
UPDATE_ON_BOOT=false
INSTALL_REQUIREMENTS=auto
RUNTIME_FIXES_ON_BOOT=auto
VALIDATE_LTX_NODES=true
STRICT_LTX_VALIDATION=false
ENABLE_MANAGER=true
ENABLE_MANAGER_LEGACY_UI=true
USE_SAGE_ATTENTION=true
COMFYUI_PORT=8188
JUPYTER_PORT=8888
MAINTENANCE_ONLY=false
```

Point important: `UPDATE_ON_BOOT=false` par defaut evite de refaire des updates lourdes a chaque lancement. Si on veut forcer une grosse mise a jour ponctuelle, mettre `UPDATE_ON_BOOT=true`.

### update_ltx.sh

Script de maintenance pour forcer une mise a jour sans lancer ComfyUI:

```bash
/update_ltx.sh
```

Il definit:

```text
UPDATE_ON_BOOT=true
INSTALL_REQUIREMENTS=true
RUNTIME_FIXES_ON_BOOT=true
MAINTENANCE_ONLY=true
```

Il arrete ComfyUI avant update si `STOP_COMFY_FOR_UPDATE=true`.

### validate_ltx.sh

Validation post-demarrage via `/object_info`.

Nodes critiques verifies:

```text
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
```

Si `STRICT_LTX_VALIDATION=false`, un echec de validation est loggue mais ne tue pas le pod.

## Custom nodes suivis

Manifest:

```text
src/custom_nodes.tsv
```

Nodes requis:

```text
ComfyUI-KJNodes
ComfyUI-LTXVideo
WhatDreamsCost-ComfyUI
ComfyUI-Manager
comfyui-videohelpersuite
ComfyUI-GGUF
ComfyUI-MelBandRoFormer
Listhelper
```

Nodes optionnels:

```text
RES4LYF
Comfyui_TTP_Toolset
```

Pour ajouter un node au template, ajouter une ligne TSV:

```text
folder<TAB>git_url<TAB>ref<TAB>true|false
```

Exemple:

```text
ComfyUI-KJNodes	https://github.com/kijai/ComfyUI-KJNodes.git	main	true
```

## GitHub Actions

Workflow:

```text
.github/workflows/docker-build.yml
```

Declencheurs:

```text
push sur main
tag v*
```

Images poussees:

```text
moltowski/comfyui-ltx:latest
moltowski/comfyui-ltx:${github.ref_name}
ghcr.io/moltowski/comfyui-ltx:latest
ghcr.io/moltowski/comfyui-ltx:${github.ref_name}
```

Secrets requis pour Docker Hub:

```text
DOCKER_USERNAME
DOCKER_TOKEN
```

GHCR utilise:

```text
GITHUB_TOKEN
```

Permissions du workflow:

```yaml
permissions:
  contents: read
  packages: write
```

## Etat des tests effectues

Verifications locales:

```text
git diff --check: OK
src/start.sh syntax check via bash -n sur pod: OK
```

Limite locale:

```text
Docker Desktop n'etait pas demarre, donc pas de docker build local complet.
```

Verifications sur pod:

- Installation des dependances ComfyUI core manquantes.
- Installation des dependances LTX runtime manquantes.
- Installation/activation ComfyUI Manager.
- Redemarrage ComfyUI avec Manager active.
- Verification que les nodes LTX critiques etaient visibles via `/object_info`.

Problemes rencontres et corriges:

- `sqlalchemy` manquant.
- `comfy_aimdo` manquant.
- `rotary_embedding_torch` manquant.
- incompatibilites autour de `kornia`; version pinnee a `kornia==0.7.3`.
- ComfyUI Manager absent ou non active; ajoute et lance avec `--enable-manager`.
- Sur ComfyUI 0.22.x, `--enable-manager` active le backend Manager mais ne suffit pas toujours a afficher le menu. Le template ajoute donc aussi `--enable-manager-legacy-ui` via `ENABLE_MANAGER_LEGACY_UI=true`.

## RunPod template recommande

Pour le nouveau template RunPod LTX:

```text
Container image: ghcr.io/moltowski/comfyui-ltx:latest
Container disk: au moins 20 GB si possible
Network volume: monte sur /workspace
Expose HTTP ports: 8188, 8888
```

Variables conseillees pour usage quotidien stable:

```text
NETWORK_VOLUME=/workspace
UPDATE_ON_BOOT=false
INSTALL_REQUIREMENTS=auto
RUNTIME_FIXES_ON_BOOT=auto
VALIDATE_LTX_NODES=true
STRICT_LTX_VALIDATION=false
ENABLE_MANAGER=true
ENABLE_MANAGER_LEGACY_UI=true
USE_SAGE_ATTENTION=true
```

Pour une session de maintenance ou grosse mise a jour:

```text
UPDATE_ON_BOOT=true
INSTALL_REQUIREMENTS=true
RUNTIME_FIXES_ON_BOOT=true
```

Ou lancer dans le pod:

```bash
/update_ltx.sh
```

## Points a faire ensuite

1. Corriger les credentials GitHub locaux ou pousser depuis un environnement qui a acces write au repo `moltowski/comfyui-ltx`.
2. Pousser le commit local `0f8c3de`.
3. Verifier que GitHub Actions build et push bien Docker Hub + GHCR.
4. Creer ou mettre a jour le template RunPod avec `ghcr.io/moltowski/comfyui-ltx:latest`.
5. Lancer un pod neuf avec network storage existant.
6. Verifier au boot:

```bash
tail -f /workspace/comfyui.log
curl http://127.0.0.1:8188/system_stats
/validate_ltx.sh
```

## Notes operationnelles

Si le pod demarre lentement, ce n'est pas forcement anormal: ComfyUI charge beaucoup de custom nodes et certains font des checks reseau au demarrage.

Si des nodes changent souvent, eviter de les figer dans l'image Docker. Les garder dans `src/custom_nodes.tsv` + network storage permet de les mettre a jour sans rebuild complet.

Si une dependance Python manque regulierement au boot, l'ajouter dans le Dockerfile et dans `install_runtime_fixes()` de `src/start.sh` si elle doit aussi reparer les pods existants.

Si ComfyUI ne demarre pas:

```bash
tail -120 /workspace/comfyui.log
pgrep -af main.py
cat /workspace/comfyui.pid
```

Si le database lock apparait:

```text
Could not acquire lock on database '/workspace/ComfyUI/user/comfyui.db'
```

Verifier qu'il n'y a pas deux process ComfyUI actifs, puis tuer l'ancien process avant restart.

## Decision actuelle

On part sur le template LTX plutot que continuer a bricoler WAN. L'ancien naming WAN etait historique; le workflow de travail actuel utilise LTX, donc le repo/image/template doivent suivre ce nom pour eviter la confusion.
