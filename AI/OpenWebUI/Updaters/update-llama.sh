#!/usr/bin/env bash
set -e

REPO="$HOME/llama.cpp-rdna2-fa"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/llama.cpp-backup-$STAMP"

echo
echo "=================================================="
echo " llama.cpp AMD/Vulkan updater"
echo "=================================================="

if [ ! -d "$REPO/.git" ]; then
    echo "ERROR: $REPO is not a git repository."
    exit 1
fi

cd "$REPO"

echo
echo "Current:"
git log -1 --oneline --decorate

echo
echo "Creating backup..."
cp -a --reflink=auto "$REPO" "$BACKUP"

echo "Backup:"
echo "  $BACKUP"

echo
echo "Fetching latest official upstream..."
git fetch origin --prune

echo
echo "Updating source..."
git pull --ff-only origin master

echo
echo "Updated:"
git log -1 --oneline --decorate

echo
echo "Rotating builds..."

if [ -d "$REPO/build-old" ]; then
    rm -rf "$REPO/build-old"
fi

if [ -d "$REPO/build" ]; then
    mv "$REPO/build" "$REPO/build-old"
fi

echo
echo "Configuring fresh Vulkan build..."

cmake -S "$REPO" -B "$REPO/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DGGML_VULKAN=ON \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON

echo
echo "Building..."

cmake --build "$REPO/build" \
    --config Release \
    -j"$(nproc)"

echo
echo "Verifying binaries..."

test -x "$REPO/build/bin/llama-cli"
test -x "$REPO/build/bin/llama-server"

echo
echo "Vulkan devices:"
"$REPO/build/bin/llama-cli" --list-devices

echo
echo "Checking shared libraries..."

if ldd "$REPO/build/bin/llama-server" 2>/dev/null | grep -q 'not found'; then
    echo
    echo "ERROR: llama-server has unresolved shared libraries:"
    ldd "$REPO/build/bin/llama-server" | grep 'not found'
    exit 1
fi

echo
echo "=================================================="
echo " AMD/VULKAN UPDATE COMPLETE"
echo "=================================================="
echo
echo "Current:"
echo "  $REPO/build"
echo
echo "Previous:"
echo "  $REPO/build-old"
echo
echo "Backup:"
echo "  $BACKUP"
echo
