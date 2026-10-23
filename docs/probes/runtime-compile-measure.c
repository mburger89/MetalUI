// Measurement program for runtime-compile-measure.sh (RC-H, record 151): the compile times of
// generated compute kernels of about 200, 1000 and 2000 lines through SDL_shadercross, loaded at
// run time by full path as MetalUISDLGPU loads it. Wall clock, dated by the script, never pinned.
//
//   usage: measure libSDL3_shadercross dependent...   (dependents are preloaded first, RC-N)
//   prints: "first <s>" (the first compile in the process: library load excluded, DXC start included),
//           "load <s>" (SDL_LoadObject of everything), then per size and route the median of 3 runs.
#include <SDL3/SDL.h>
#include <SDL3_shadercross/SDL_shadercross.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void *(*p_spirv)(const SDL_ShaderCross_HLSL_Info *, size_t *);
static void *(*p_dxil)(const SDL_ShaderCross_HLSL_Info *, size_t *);
static void *(*p_msl)(const SDL_ShaderCross_SPIRV_Info *);
static bool (*p_init)(void);

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static char *generated(int lines) {
    size_t cap = (size_t)lines * 80 + 512, n = 0;
    char *s = malloc(cap);
    n += snprintf(s + n, cap - n, "RWStructuredBuffer<float> dst : register(u0, space1);\n"
        "cbuffer P : register(b0, space2) { float k; };\n"
        "float f0(float x) { return x * 1.0001 + k; }\n[numthreads(64, 1, 1)]\n"
        "void main(uint3 id : SV_DispatchThreadID) {\n float v = float(id.x);\n");
    for (int i = 0; i < lines - 8; i++)
        n += snprintf(s + n, cap - n, " v = f0(v) * %d.5 + sqrt(abs(v) + %d.0) - floor(v * 0.%03d);\n", i % 7 + 1, i, i % 1000);
    n += snprintf(s + n, cap - n, " dst[id.x] = v;\n}\n");
    return s;
}

static int cmp(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s lib [dependent...]\n", argv[0]); return 2; }
    double t0 = now();
    for (int i = 2; i < argc; i++) if (!SDL_LoadObject(argv[i])) printf("preload %s failed: %s\n", argv[i], SDL_GetError());
    void *lib = SDL_LoadObject(argv[1]);
    if (!lib) { printf("LOAD FAILED: %s\n", SDL_GetError()); return 1; }
    p_init = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_Init");
    p_spirv = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_CompileSPIRVFromHLSL");
    p_dxil = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_CompileDXILFromHLSL");
    p_msl = (void *)SDL_LoadFunction(lib, "SDL_ShaderCross_TranspileMSLFromSPIRV");
    p_init();
    printf("load %.3f s\n", now() - t0);

    int sizes[3] = {200, 1000, 2000};
    for (int i = 0; i < 3; i++) {
        char *src = generated(sizes[i]);
        SDL_ShaderCross_HLSL_Info hi; memset(&hi, 0, sizeof hi);
        hi.source = src; hi.entrypoint = "main"; hi.shader_stage = SDL_SHADERCROSS_SHADERSTAGE_COMPUTE;
        double spv[3], msl[3], dxil[3]; size_t spvBytes = 0, dxilBytes = 0;
        for (int r = 0; r < 3; r++) {
            double a = now(); size_t s1 = 0; void *code = p_spirv(&hi, &s1); double b = now();
            if (i == 0 && r == 0) printf("first %.3f s (HLSL to SPIR-V, first compile in the process)\n", b - a);
            if (!code) { printf("%d lines: SPIR-V FAILED: %s\n", sizes[i], SDL_GetError()); return 1; }
            spv[r] = b - a; spvBytes = s1;
            SDL_ShaderCross_SPIRV_Info si; memset(&si, 0, sizeof si);
            si.bytecode = code; si.bytecode_size = s1; si.entrypoint = "main"; si.shader_stage = SDL_SHADERCROSS_SHADERSTAGE_COMPUTE;
            double c = now(); char *m = p_msl(&si); msl[r] = now() - c; SDL_free(m); SDL_free(code);
            double d = now(); size_t s2 = 0; void *dx = p_dxil(&hi, &s2); dxil[r] = now() - d; dxilBytes = dx ? s2 : 0; SDL_free(dx);
        }
        qsort(spv, 3, sizeof(double), cmp); qsort(msl, 3, sizeof(double), cmp); qsort(dxil, 3, sizeof(double), cmp);
        printf("%d lines: hlsl->spirv %.3f s (%zu bytes), spirv->msl %.3f s, hlsl->dxil %.3f s (%zu bytes) [median of 3]\n",
               sizes[i], spv[1], spvBytes, msl[1], dxil[1], dxilBytes);
        free(src);
    }
    return 0;
}
