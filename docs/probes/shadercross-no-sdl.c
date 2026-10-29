// Probe for HX- (XP-G27, record 160): SDL_shadercross at the pin loaded and called from a process that
// does NOT link SDL3, with no SDL or shadercross header (the structs are SDLShaderCross.c's mirrors).
// macOS only as written (.dylib names); the Linux arms are owed (HX-B).
//
// Pin: libsdl-org/SDL_shadercross 1ff05bec573988a98ef9e0260b4da44f512b8367, built with docs/packaging.md 4a.
//   cc -O1 -Wall docs/probes/shadercross-no-sdl.c -o /tmp/hxprobe        # links libSystem only
//   /tmp/hxprobe local   /opt/homebrew/lib/libSDL3.0.dylib "$SX/lib"      # arm L: SDL3 preloaded RTLD_LOCAL
//   /tmp/hxprobe preload /opt/homebrew/lib/libSDL3.0.dylib "$SX/lib"      # SDL3 preloaded RTLD_GLOBAL
//   /tmp/hxprobe nosdl   -                                 "$SX/lib"      # SDL3 not preloaded
// Arms P/R (an .app on a Mac without Homebrew): copy $SX/lib/*.dylib and libSDL3.0.dylib to RELOC, then
//   install_name_tool -change /opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib /nonexistent/hx/libSDL3.0.dylib RELOC/libSDL3_shadercross.0.0.0.dylib
//   install_name_tool -id /nonexistent/hx/libSDL3.0.dylib RELOC/libSDL3.0.dylib; codesign -f -s - RELOC/libSDL3_shadercross.0.0.0.dylib RELOC/libSDL3.0.dylib
//   /tmp/hxprobe nosdl - RELOC                      # P: "Library not loaded: /nonexistent/hx/libSDL3.0.dylib"
//   /tmp/hxprobe local RELOC/libSDL3.0.dylib RELOC  # R: every arm passes (dyld binds the absolute path to the loaded install name)
// Arm T (two SDL3 instances): EXTRA_SDL=RELOC/libSDL3.0.dylib /tmp/hxprobe preload /opt/homebrew/lib/libSDL3.0.dylib RELOC
//
// Recorded 2026-10-28, macOS 27.2 arm64, SDL3 3.4.18 (Homebrew), load average 145-225 (other sessions):
// the full output is in docs/superpowers/2026-10-28-runtime-compile-no-sdl-decisions.md, HX-B.
#include <dlfcn.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <dirent.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

typedef struct { char *name; char *value; } SCDefine;
typedef struct { const char *source, *entrypoint, *include_dir; SCDefine *defines; int shader_stage; uint32_t props; } SCHLSLInfo;
typedef struct { const uint8_t *bytecode; size_t bytecode_size; const char *entrypoint; int shader_stage; uint32_t props; } SCSPIRVInfo;
typedef struct { uint32_t s, rot, rob, rwt, rwb, ubo, tx, ty, tz; } SCMeta;
_Static_assert(sizeof(SCHLSLInfo) == 40, "hlsl info");
_Static_assert(sizeof(SCSPIRVInfo) == 32, "spirv info");
_Static_assert(sizeof(SCMeta) == 36, "meta");

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static const char *ok_src =
    "StructuredBuffer<uint> src : register(t0, space0);\n"
    "RWStructuredBuffer<uint> dst : register(u0, space1);\n"
    "cbuffer P : register(b0, space2) { uint n; };\n"
    "[numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * 2u; }\n";
static const char *bad_src = "[numthreads(1,1,1)] void main( { }";

static void *open_one(const char *path, int flags) {
    double t = now();
    void *h = dlopen(path, flags);
    printf("  dlopen %s -> %s (%.3f s)%s%s\n", path, h ? "ok" : "FAILED", now() - t, h ? "" : ": ", h ? "" : dlerror());
    return h;
}

static void list_sdl_images(void) {
#ifdef __APPLE__
    int n = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "libSDL3.") || strstr(name, "libSDL3_")) { printf("  N image %s\n", name); if (strstr(name, "libSDL3.")) n++; }
    }
    printf("N SDL3 images in process: %d\n", n);
#endif
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s preload|nosdl|local SDL3PATH|- SCDIR\n", argv[0]); return 2; }
    const char *mode = argv[1], *sdlpath = argv[2], *dir = argv[3];
    char path[4096];
    double t0 = now();
    void *sdl = NULL;
    if (strcmp(mode, "nosdl") != 0) {
        sdl = open_one(sdlpath, RTLD_NOW | (strcmp(mode, "local") == 0 ? RTLD_LOCAL : RTLD_GLOBAL));
        if (!sdl) return 1;
    }
    if (getenv("EXTRA_SDL")) { if (!open_one(getenv("EXTRA_SDL"), RTLD_NOW | RTLD_LOCAL)) return 1; }  // arm T: a second SDL3
    // RC-N: dependents by full path (shortest name first per group, as preloadSet does).
    const char *deps[] = {"libdxcompiler.dylib", "libspirv-cross-c-shared.0.dylib", "libdxil.dylib"};
    for (int i = 0; i < 3; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, deps[i]);
        void *h = open_one(path, RTLD_NOW | (strcmp(mode, "local") == 0 || strcmp(mode, "nosdl") == 0 ? RTLD_LOCAL : RTLD_GLOBAL));
        if (!h && i < 2) return 1;
    }
    snprintf(path, sizeof path, "%s/libSDL3_shadercross.dylib", dir);
    void *sc = open_one(path, RTLD_NOW | RTLD_LOCAL);
    if (!sc) { printf("L FAILED\n"); list_sdl_images(); return 1; }
    printf("L loaded in %.3f s total\n", now() - t0);

    bool (*init)(void) = dlsym(sc, "SDL_ShaderCross_Init");
    void *(*spirv)(const SCHLSLInfo *, size_t *) = dlsym(sc, "SDL_ShaderCross_CompileSPIRVFromHLSL");
    void *(*dxil)(const SCHLSLInfo *, size_t *) = dlsym(sc, "SDL_ShaderCross_CompileDXILFromHLSL");
    void *(*msl)(const SCSPIRVInfo *) = dlsym(sc, "SDL_ShaderCross_TranspileMSLFromSPIRV");
    SCMeta *(*reflect)(const uint8_t *, size_t, uint32_t) = dlsym(sc, "SDL_ShaderCross_ReflectComputeSPIRV");
    // SDL functions through the shadercross handle: dlsym(handle) searches the image and its dependents.
    const char *(*get_error)(void) = dlsym(sc, "SDL_GetError");
    bool (*clear_error)(void) = dlsym(sc, "SDL_ClearError");
    void (*sdl_free)(void *) = dlsym(sc, "SDL_free");
    printf("R init=%p spirv=%p dxil=%p msl=%p reflect=%p | via sc: GetError=%p ClearError=%p free=%p\n",
           (void *)init, (void *)spirv, (void *)dxil, (void *)msl, (void *)reflect, (void *)get_error, (void *)clear_error, (void *)sdl_free);
    if (sdl) {
        void *ge2 = dlsym(sdl, "SDL_GetError");
        printf("S GetError via SDL handle=%p, same instance as via shadercross: %s\n", ge2, ge2 == (void *)get_error ? "yes" : "NO");
    }
    void *global_ge = dlsym(RTLD_DEFAULT, "SDL_GetError");
    printf("S GetError via RTLD_DEFAULT=%p (%s)\n", global_ge, global_ge == (void *)get_error ? "same" : global_ge ? "DIFFERENT" : "not global");
    list_sdl_images();
    if (!init || !spirv || !dxil || !msl || !reflect || !get_error || !clear_error || !sdl_free) { printf("R FAILED\n"); return 1; }
    printf("I init -> %d\n", init());

    SCHLSLInfo info; memset(&info, 0, sizeof info);
    info.source = ok_src; info.entrypoint = "main"; info.shader_stage = 2;
    size_t size = 0;
    double t = now();
    clear_error();
    uint8_t *bytes = spirv(&info, &size);
    printf("A spirv %s, %zu bytes, magic %02x%02x%02x%02x, %.3f s (first compile)\n", bytes ? "ok" : "FAILED", size,
           bytes ? bytes[3] : 0, bytes ? bytes[2] : 0, bytes ? bytes[1] : 0, bytes ? bytes[0] : 0, now() - t);
    if (!bytes) { printf("  error: %s\n", get_error()); return 1; }
    t = now(); clear_error();
    uint8_t *again = spirv(&info, &size);
    printf("A second compile %.3f s\n", now() - t); sdl_free(again);

    SCSPIRVInfo sinfo; memset(&sinfo, 0, sizeof sinfo);
    sinfo.bytecode = bytes; sinfo.bytecode_size = size; sinfo.entrypoint = "main"; sinfo.shader_stage = 2;
    clear_error();
    char *text = msl(&sinfo);
    printf("D msl %s, %zu chars, main0: %s\n", text ? "ok" : "FAILED", text ? strlen(text) : 0, text && strstr(text, "main0") ? "yes" : "no");
    if (text) sdl_free(text);

    clear_error();
    SCMeta *m = reflect(bytes, size, 0);
    if (m) { printf("C samplers=%u rotex=%u robuf=%u rwtex=%u rwbuf=%u ubo=%u threads=%u,%u,%u\n", m->s, m->rot, m->rob, m->rwt, m->rwb, m->ubo, m->tx, m->ty, m->tz); sdl_free(m); }
    else printf("C FAILED: %s\n", get_error());
    sdl_free(bytes);

    size_t dsize = 0; clear_error();
    uint8_t *d = dxil(&info, &dsize);
    printf("E dxil %s, %zu bytes, container %.4s\n", d ? "ok" : "FAILED", dsize, d ? (const char *)d : "-");
    if (d) sdl_free(d); else printf("  error: %s\n", get_error());

    SCHLSLInfo bad = info; bad.source = bad_src;
    clear_error();
    void *nothing = spirv(&bad, &size);
    const char *err = get_error();
    printf("B broken kernel -> %s; SDL_GetError (dlsym'd via shadercross) %zu bytes: %.90s\n", nothing ? "COMPILED?!" : "NULL", strlen(err), err);
    // The separating arm: an SDL_GetError of a *different* instance would be empty.
    if (global_ge && global_ge != (void *)get_error) {
        const char *(*other)(void) = (const char *(*)(void))global_ge;
        printf("B other instance's SDL_GetError: %zu bytes\n", strlen(other()));
    }
    return 0;
}
