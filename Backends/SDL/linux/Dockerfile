# Linux build and replay of Portable/: no MetalUI, no Apple frameworks.
# SDL3 is built from source (Ubuntu 24.04 ships only SDL2). Rendering uses
# Mesa lavapipe, a CPU Vulkan driver, with SDL's offscreen video driver.
FROM swift:6.4-noble
RUN apt-get update && apt-get install -y --no-install-recommends \
      git cmake ninja-build pkg-config libvulkan1 mesa-vulkan-drivers vulkan-tools \
    && rm -rf /var/lib/apt/lists/*
ARG SDL_TAG=release-3.4.16
RUN git clone --depth 1 --branch ${SDL_TAG} https://github.com/libsdl-org/SDL.git /tmp/SDL \
    && cmake -S /tmp/SDL -B /tmp/SDL/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
         -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_AUDIO=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    && cmake --build /tmp/SDL/build && cmake --install /tmp/SDL/build && ldconfig \
    && rm -rf /tmp/SDL
ENV SDL_VIDEO_DRIVER=offscreen
# Mount the repository at /work: Backends/SDL depends on ../.. (the MetalUI package).
WORKDIR /work/Backends/SDL
