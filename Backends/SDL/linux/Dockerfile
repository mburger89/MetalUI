# Linux build and replay of Backends/SDL (build context: Backends/SDL): no Apple frameworks.
# SDL3 is built from source (Ubuntu 24.04 ships only SDL2). Rendering uses
# Mesa lavapipe, a CPU Vulkan driver, with SDL's offscreen video driver.
# SDL is built WITH its X11 and Wayland drivers (ruling VD-A) so the libSDL3.so.0 a
# consumer bundles from this image runs on a real Linux desktop; the X11, Wayland and
# libdecor client libraries are dlopened at run time from the user's system, never
# linked. CI stays headless through ENV SDL_VIDEO_DRIVER=offscreen below.
# SDL3 and AccessKit are installed on the compiler's default paths (/usr), the
# layout docs/getting-started.md documents for a consumer (ruling PX-I item 5):
# no pkg-config, no flags.
FROM swift:6.4-noble
RUN apt-get update && apt-get install -y --no-install-recommends \
      git cmake ninja-build pkg-config libvulkan1 mesa-vulkan-drivers vulkan-tools \
      libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxss-dev libxtst-dev \
      libxkbcommon-dev libwayland-dev wayland-protocols libegl-dev libdecor-0-dev \
    && rm -rf /var/lib/apt/lists/*
ARG SDL_TAG=release-3.4.16
RUN git clone --depth 1 --branch ${SDL_TAG} https://github.com/libsdl-org/SDL.git /tmp/SDL \
    && cmake -S /tmp/SDL -B /tmp/SDL/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
         -DSDL_X11=ON -DSDL_X11_SHARED=ON -DSDL_WAYLAND=ON -DSDL_WAYLAND_SHARED=ON -DSDL_WAYLAND_LIBDECOR=ON \
         -DSDL_AUDIO=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    && cmake --build /tmp/SDL/build && cmake --install /tmp/SDL/build && ldconfig \
    && rm -rf /tmp/SDL
# Ruling VD-B: SDL's cmake fails on a missing dev package, but the image still proves the
# built library lists x11, wayland, offscreen and dummy (SDL_GetVideoDriver), or the build fails.
COPY scripts/check-video-drivers.c /tmp/check-video-drivers.c
RUN clang /tmp/check-video-drivers.c -o /tmp/check-video-drivers -lSDL3 && /tmp/check-video-drivers \
    && rm /tmp/check-video-drivers /tmp/check-video-drivers.c
# AccessKit's C bindings (ruling AX-A): prebuilt on x86_64, built with cargo on
# aarch64, where the release ships no library. Baked in so every run reuses it.
RUN apt-get update && apt-get install -y --no-install-recommends python3 curl ca-certificates gcc \
    && rm -rf /var/lib/apt/lists/*
RUN if [ "$(uname -m)" != x86_64 ]; then \
      curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable; fi
COPY scripts/fetch-accesskit.py /opt/fetch-accesskit.py
RUN PATH="$HOME/.cargo/bin:$PATH" python3 /opt/fetch-accesskit.py --prefix /usr
ENV SDL_VIDEO_DRIVER=offscreen
# Mount the repository at /work: Backends/SDL depends on ../.. (the MetalUI package).
WORKDIR /work/Backends/SDL
