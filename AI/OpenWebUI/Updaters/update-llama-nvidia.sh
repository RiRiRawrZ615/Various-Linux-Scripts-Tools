#!/usr/bin/env bash
set -e

REPO="$HOME/llama.cpp-nvidia"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/llama.cpp-nvidia-backup-$STAMP"

echo
echo "=================================================="
echo " llama.cpp NVIDIA/CUDA updater"
echo "=================================================="
echo

# --------------------------------------------------
# Verify repository
# --------------------------------------------------

if [ ! -d "$REPO/.git" ]; then
    echo "ERROR: $REPO is not a git repository."
    exit 1
fi

cd "$REPO"

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"

case "$REMOTE_URL" in
    https://github.com/ggml-org/llama.cpp*|git@github.com:ggml-org/llama.cpp*)
        echo "Repository: official ggml-org/llama.cpp"
        ;;
    *)
        echo "ERROR: origin is not official ggml-org/llama.cpp."
        echo "Remote: $REMOTE_URL"
        exit 1
        ;;
esac

# --------------------------------------------------
# Verify NVIDIA GPU
# --------------------------------------------------

echo
echo "=================================================="
echo " VERIFYING NVIDIA GPU"
echo "=================================================="

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "ERROR: nvidia-smi was not found."
    exit 1
fi

GPU="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"

if [ -z "$GPU" ]; then
    echo "ERROR: No NVIDIA GPU detected."
    exit 1
fi

echo "Detected GPU: $GPU"

case "$GPU" in
    *"RTX 4070"*)
        echo "Confirmed: GeForce RTX 4070"
        ;;
    *)
        echo "ERROR: This updater is specifically for RTX 4070."
        echo "Detected: $GPU"
        exit 1
        ;;
esac

echo
echo "NVIDIA driver:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1

# --------------------------------------------------
# Verify CUDA toolkit
# --------------------------------------------------

echo
echo "=================================================="
echo " VERIFYING CUDA TOOLKIT"
echo "=================================================="

if ! command -v nvcc >/dev/null 2>&1; then
    echo "ERROR: nvcc was not found."
    echo "The NVIDIA driver is present, but CUDA toolkit is not in PATH."
    exit 1
fi

echo "nvcc: $(command -v nvcc)"
nvcc --version

# --------------------------------------------------
# Show current source state
# --------------------------------------------------

echo
echo "=================================================="
echo " CURRENT SOURCE"
echo "=================================================="

echo "Branch:"
git branch --show-current

echo
echo "Commit:"
git log -1 --oneline --decorate

echo
echo "Status:"
git status --short

# --------------------------------------------------
# Full backup
# --------------------------------------------------

echo
echo "=================================================="
echo " CREATING FULL BACKUP"
echo "=================================================="

cp -a --reflink=auto "$REPO" "$BACKUP"

echo "Backup:"
echo "  $BACKUP"

# --------------------------------------------------
# Fetch/update source
# --------------------------------------------------

echo
echo "=================================================="
echo " FETCHING LATEST UPSTREAM"
echo "=================================================="

git fetch origin --prune

echo
echo "Latest origin/master:"
git log -1 --oneline origin/master

echo
echo "Updating with fast-forward only..."
git pull --ff-only origin master

echo
echo "Now at:"
git log -1 --oneline --decorate

# --------------------------------------------------
# Rotate builds
#
# build      = NEW/current
# build-old  = PREVIOUS
# --------------------------------------------------

echo
echo "=================================================="
echo " ROTATING BUILD DIRECTORIES"
echo "=================================================="

if [ -d "$REPO/build-old" ]; then
    echo "Removing existing build-old..."
    rm -rf "$REPO/build-old"
fi

if [ -d "$REPO/build" ]; then
    echo "Renaming:"
    echo "  build -> build-old"
    mv "$REPO/build" "$REPO/build-old"
else
    echo "No existing build directory."
fi

# --------------------------------------------------
# Configure CUDA
#
# RTX 4070 = NVIDIA Ada Lovelace = SM 8.9
# --------------------------------------------------

echo
echo "=================================================="
echo " CONFIGURING CUDA BUILD"
echo "=================================================="

cmake -S "$REPO" -B "$REPO/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DGGML_CUDA=ON \
    -DGGML_VULKAN=OFF \
    -DGGML_HIP=OFF \
    -DGGML_MUSA=OFF \
    -DCMAKE_CUDA_ARCHITECTURES=89

echo
echo "Build configuration:"
grep -E \
    'GGML_CUDA:BOOL|GGML_VULKAN:BOOL|GGML_HIP:BOOL|GGML_MUSA:BOOL|CMAKE_CUDA_ARCHITECTURES|CMAKE_BUILD_TYPE' \
    "$REPO/build/CMakeCache.txt" || true

# --------------------------------------------------
# Build
# --------------------------------------------------

echo
echo "=================================================="
echo " BUILDING"
echo "=================================================="

cmake --build "$REPO/build" \
    --config Release \
    -j"$(nproc)"

# --------------------------------------------------
# Verify binaries
# --------------------------------------------------

echo
echo "=================================================="
echo " VERIFYING BINARIES"
echo "=================================================="

test -x "$REPO/build/bin/llama-cli"
test -x "$REPO/build/bin/llama-server"

ls -lh \
    "$REPO/build/bin/llama-cli" \
    "$REPO/build/bin/llama-server"

# --------------------------------------------------
# Verify CUDA/NVIDIA device
# --------------------------------------------------

echo
echo "=================================================="
echo " VERIFYING CUDA DEVICE"
echo "=================================================="

"$REPO/build/bin/llama-cli" --list-devices

echo
echo "=================================================="
echo " NVIDIA BUILD SUCCESSFUL"
echo "=================================================="
echo
echo "Current build:"
echo "  $REPO/build"
echo
echo "Previous build:"
echo "  $REPO/build-old"
echo
echo "Full source backup:"
echo "  $BACKUP"
echo
echo "GPU:"
echo "  $GPU"
echo
