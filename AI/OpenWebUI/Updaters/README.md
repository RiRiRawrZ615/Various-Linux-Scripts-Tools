# llama.cpp GPU Updaters

Automated update and rebuild scripts for the official upstream [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp), with separate configurations for **AMD/Vulkan** and **NVIDIA/CUDA** systems.

Both updaters follow the same basic workflow:

1. Create a timestamped backup of the existing llama.cpp checkout.
2. Fetch the latest official upstream `master`.
3. Update the source tree.
4. Preserve the previous working build as `build-old`.
5. Create a completely fresh build in `build/`.
6. Verify the resulting binaries and GPU backend before reporting success.

## AMD / Vulkan

The AMD updater is installed at:

```text
~/bin/update-llama.sh
```

It expects the llama.cpp source tree at:

```text
~/llama.cpp-rdna2-fa
```

The build layout is:

```text
~/llama.cpp-rdna2-fa/build
    Current Vulkan build

~/llama.cpp-rdna2-fa/build-old
    Previous build
```

Backups are created as:

```text
~/llama.cpp-backup-YYYYMMDD-HHMMSS
```

The AMD configuration uses the Vulkan backend:

```text
-DGGML_VULKAN=ON
-DGGML_NATIVE=ON
-DCMAKE_INSTALL_RPATH='$ORIGIN'
-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
```

The `$ORIGIN` runtime path allows `llama-server` to locate its companion shared libraries from the same build directory.

The resulting binaries are:

```text
~/llama.cpp-rdna2-fa/build/bin/llama-cli
~/llama.cpp-rdna2-fa/build/bin/llama-server
```

The updater verifies shared-library resolution and Vulkan device detection after building.

Designed for AMD systems using the RADV/Vulkan stack, including RDNA2 GPUs such as the Radeon RX 6950 XT.

## NVIDIA / CUDA

The NVIDIA updater is installed at:

```text
~/bin/update-llama-nvidia.sh
```

It expects the llama.cpp source tree at:

```text
~/llama.cpp-nvidia
```

The build layout is:

```text
~/llama.cpp-nvidia/build
    Current CUDA build

~/llama.cpp-nvidia/build-old
    Previous build
```

Backups are created as:

```text
~/llama.cpp-nvidia-backup-YYYYMMDD-HHMMSS
```

The NVIDIA configuration explicitly uses CUDA:

```text
-DGGML_CUDA=ON
-DGGML_VULKAN=OFF
-DGGML_HIP=OFF
-DGGML_MUSA=OFF
-DGGML_NATIVE=ON
```

CUDA architecture is selected specifically for the target GPU so the resulting binaries are compiled for the appropriate NVIDIA architecture.

The resulting binaries are:

```text
~/llama.cpp-nvidia/build/bin/llama-cli
~/llama.cpp-nvidia/build/bin/llama-server
```

The updater verifies the NVIDIA GPU, driver, CUDA toolkit, resulting binaries, and CUDA device visibility before reporting success.

The NVIDIA updater can also migrate the old official `ggerganov/llama.cpp` remote to the current `ggml-org/llama.cpp` location.

## Rollback

Both configurations intentionally keep the previous build immediately available:

```text
build      = current
build-old  = previous
```

Each update also creates a full timestamped source-tree backup, providing an additional recovery point before any destructive source-tree operations.

The updaters are intended for dedicated GPU systems where reproducible, backend-specific llama.cpp builds and straightforward rollback are preferred over relying on prebuilt binaries.
