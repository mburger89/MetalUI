// Probe for RC- (record 151): what SDL_shadercross at the pin does when its
// shared library is loaded at run time and called from the app's process.
//
// Pin: libsdl-org/SDL_shadercross 1ff05bec573988a98ef9e0260b4da44f512b8367.
// Build and run (macOS; SX = an install prefix of that pin, SDL3 = Homebrew's):
//
//   cc -O1 -I"$SX/include" $(pkg-config --cflags sdl3) docs/probes/sdl-shadercross-runtime.c \
//      $(pkg-config --libs sdl3) -o /tmp/sxprobe
//   /tmp/sxprobe "$SX/lib/libSDL3_shadercross.dylib" "$SX/lib/libdxcompiler.dylib" "$SX/lib/libspirv-cross-c-shared.dylib"
//   (without the two dependents: "Library not loaded: @rpath/libspirv-cross-c-shared.0.dylib", the install has no LC_RPATH)
//
// Arms (each prints one line; the output of the recorded run is in the header
// of docs/superpowers/2026-10-22-sdl-gpu-runtime-shaders-decisions.md, RC-B..RC-H):
//   A  positive control: a valid compute kernel compiles to SPIR-V and MSL.
//   B  separating arm: a kernel with a syntax error fails, and SDL_GetError holds DXC's text.
//   C  reflection of the compute SPIR-V names the counts and the thread group.
//   D  MSL entry point name.
//   E  DXIL from HLSL (needs dxil beside dxcompiler).
//   F  eight threads compile at once and every result equals the serial one.
//   H  (run with the dependent libraries as extra arguments) a full-path load works once they are preloaded.
//   I  the real struct sizes and offsets (the mirror structs of SDLShaderCross.h must equal them).
//   G  compile time of generated kernels of about 200, 1000 and 2000 lines.
#include <SDL3/SDL.h>
#include <SDL3_shadercross/SDL_shadercross.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void *lib;
#define FN(ret, name, args) static ret (*name) args;
FN(bool, p_init, (void))
FN(void *, p_spirv, (const SDL_ShaderCross_HLSL_Info *, size_t *))
FN(void *, p_dxil, (const SDL_ShaderCross_HLSL_Info *, size_t *))
FN(void *, p_msl, (const SDL_ShaderCross_SPIRV_Info *))
FN(SDL_ShaderCross_ComputePipelineMetadata *, p_reflect, (const Uint8 *, size_t, SDL_PropertiesID))

static const char *ok_src =
    "StructuredBuffer<uint> src : register(t0, space0);\n"
    "RWStructuredBuffer<uint> dst : register(u0, space1);\n"
    "cbuffer P : register(b0, space2) { uint n; };\n"
    "[numthreads(64, 1, 1)]\n"
    "void main(uint3 id : SV_DispatchThreadID) { if (id.x < n) dst[id.x] = src[id.x] * 2u; }\n";

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static void *compile_spirv(const char *src, size_t *size) {
    SDL_ShaderCross_HLSL_Info info; memset(&info, 0, sizeof info);
    info.source = src; info.entrypoint = "main"; info.shader_stage = SDL_SHADERCROSS_SHADERSTAGE_COMPUTE;
    return p_spirv(&info, size);
}

static char *generated(int lines) {
    size_t cap = (size_t)lines * 80 + 512;
    char *s = malloc(cap); size_t n = 0;
    n += snprintf(s + n, cap - n, "RWStructuredBuffer<float> dst : register(u0, space1);\n"
        "cbuffer P : register(b0, space2) { float k; };\n"
        "float f0(float x) { return x * 1.0001 + k; }\n[numthreads(64, 1, 1)]\n"
        "void main(uint3 id : SV_DispatchThreadID) {\n float v = float(id.x);\n");
    for (int i = 0; i < lines - 8; i++)
        n += snprintf(s + n, cap - n, " v = f0(v) * %d.5 + sqrt(abs(v) + %d.0) - floor(v * 0.%03d);\n", i % 7 + 1, i, i % 1000);
    n += snprintf(s + n, cap - n, " dst[id.x] = v;\n}\n");
    return s;
}

typedef struct { void *out; size_t size; } Result;
static void *worker(void *arg) {
    (void)arg; return NULL;
}
static int g_fail; static void *g_ref; static size_t g_refSize;
static int thread_body(void *data) {
    (void)data;
    for (int i = 0; i < 3; i++) {
        size_t size = 0; void *out = compile_spirv(ok_src, &size);
        if (!out || size != g_refSize || memcmp(out, g_ref, size) != 0) g_fail++;
        SDL_free(out);
    }
    return 0;
}

int main(int argc, char **argv) {
    (void)worker;
    if (argc < 2) { fprintf(stderr, "usage: %s path/to/libSDL3_shadercross\n", argv[0]); return 2; }
    // Dependencies first (arms H): a library installed with no LC_RPATH / RUNPATH does not find its
    // @rpath or sibling dependents when loaded by full path from another process, but both dyld and
    // glibc treat an already-loaded image as satisfying a dependency of the same install name / SONAME.
    for (int i = 2; i < argc; i++) {
        void *dep = SDL_LoadObject(argv[i]);
        printf("H preload %s -> %s\n", argv[i], dep ? "ok" : SDL_GetError());
    }
    lib = SDL_LoadObject(argv[1]);
    if (!lib) { printf("LOAD FAILED %s: %s\n", argv[1], SDL_GetError()); return 1; }
    p_init = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_Init");
    p_spirv = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_CompileSPIRVFromHLSL");
    p_dxil = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_CompileDXILFromHLSL");
    p_msl = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_TranspileMSLFromSPIRV");
    p_reflect = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_ReflectComputeSPIRV");
    printf("symbols init=%d spirv=%d dxil=%d msl=%d reflect=%d\n", !!p_init, !!p_spirv, !!p_dxil, !!p_msl, !!p_reflect);
    printf("I sizeof HLSL_Info=%zu (source@%zu entry@%zu include@%zu defines@%zu stage@%zu props@%zu) HLSL_Define=%zu SPIRV_Info=%zu (bytecode@%zu size@%zu entry@%zu stage@%zu props@%zu) ComputeMetadata=%zu\n",
           sizeof(SDL_ShaderCross_HLSL_Info), offsetof(SDL_ShaderCross_HLSL_Info, source), offsetof(SDL_ShaderCross_HLSL_Info, entrypoint),
           offsetof(SDL_ShaderCross_HLSL_Info, include_dir), offsetof(SDL_ShaderCross_HLSL_Info, defines), offsetof(SDL_ShaderCross_HLSL_Info, shader_stage),
           offsetof(SDL_ShaderCross_HLSL_Info, props), sizeof(SDL_ShaderCross_HLSL_Define), sizeof(SDL_ShaderCross_SPIRV_Info),
           offsetof(SDL_ShaderCross_SPIRV_Info, bytecode), offsetof(SDL_ShaderCross_SPIRV_Info, bytecode_size), offsetof(SDL_ShaderCross_SPIRV_Info, entrypoint),
           offsetof(SDL_ShaderCross_SPIRV_Info, shader_stage), offsetof(SDL_ShaderCross_SPIRV_Info, props), sizeof(SDL_ShaderCross_ComputePipelineMetadata));
    printf("init -> %d\n", p_init());

    size_t size = 0; void *spv = compile_spirv(ok_src, &size);
    printf("A spirv %s, %zu bytes, magic %08x\n", spv ? "ok" : "FAILED", size, spv ? *(Uint32 *)spv : 0);
    g_ref = spv; g_refSize = size;

    size_t bad = 0; void *none = compile_spirv("[numthreads(1,1,1)] void main( { nonsense }\n", &bad);
    const char *text = SDL_GetError();
    printf("B syntax error -> %s; error text %zu bytes: %.160s\n", none ? "UNEXPECTEDLY OK" : "NULL", strlen(text), text);

    SDL_ShaderCross_ComputePipelineMetadata *m = p_reflect(spv, size, 0);
    if (m) printf("C reflect samplers=%u rotex=%u robuf=%u rwtex=%u rwbuf=%u ubo=%u threads=%u,%u,%u\n",
                  m->num_samplers, m->num_readonly_storage_textures, m->num_readonly_storage_buffers,
                  m->num_readwrite_storage_textures, m->num_readwrite_storage_buffers, m->num_uniform_buffers,
                  m->threadcount_x, m->threadcount_y, m->threadcount_z);
    else printf("C reflect FAILED: %s\n", SDL_GetError());
    SDL_free(m);

    SDL_ShaderCross_SPIRV_Info si; memset(&si, 0, sizeof si);
    si.bytecode = spv; si.bytecode_size = size; si.entrypoint = "main"; si.shader_stage = SDL_SHADERCROSS_SHADERSTAGE_COMPUTE;
    char *msl = p_msl(&si);
    printf("D msl %s, %zu chars, has main0=%d\n", msl ? "ok" : "FAILED", msl ? strlen(msl) : 0, msl && strstr(msl, "main0") != NULL);
    SDL_free(msl);

    SDL_ShaderCross_HLSL_Info hi; memset(&hi, 0, sizeof hi);
    hi.source = ok_src; hi.entrypoint = "main"; hi.shader_stage = SDL_SHADERCROSS_SHADERSTAGE_COMPUTE;
    size_t dsize = 0; void *dxil = p_dxil(&hi, &dsize);
    printf("E dxil %s, %zu bytes%s%s\n", dxil ? "ok" : "FAILED", dsize, dxil ? "" : ": ", dxil ? "" : SDL_GetError());
    if (dxil) { const unsigned char *d = dxil; printf("E container magic %.4s, digest bytes 4..19 =", (const char *)d);
                for (int i = 4; i < 20; i++) printf(" %02x", d[i]); printf(" (all zero = unsigned: D3D12 refuses it)\n"); }
    SDL_free(dxil);

    SDL_Thread *threads[8];
    for (int i = 0; i < 8; i++) threads[i] = SDL_CreateThread(thread_body, "sx", NULL);
    for (int i = 0; i < 8; i++) SDL_WaitThread(threads[i], NULL);
    printf("F 8 threads x 3 compiles: %d mismatches\n", g_fail);

    int sizes[3] = {200, 1000, 2000};
    for (int i = 0; i < 3; i++) {
        char *src = generated(sizes[i]);
        double t0 = now(); size_t s1 = 0; void *a = compile_spirv(src, &s1); double t1 = now();
        char *m2 = NULL;
        if (a) { SDL_ShaderCross_SPIRV_Info sj = si; sj.bytecode = a; sj.bytecode_size = s1; m2 = p_msl(&sj); }
        double t2 = now();
        printf("G %d lines: hlsl->spirv %.3f s (%zu bytes)%s, spirv->msl %.3f s\n", sizes[i], t1 - t0, s1,
               a ? "" : " FAILED", t2 - t1);
        if (!a) printf("  %s\n", SDL_GetError());
        SDL_free(a); SDL_free(m2); free(src);
    }
    SDL_free(spv);
    return 0;
}
