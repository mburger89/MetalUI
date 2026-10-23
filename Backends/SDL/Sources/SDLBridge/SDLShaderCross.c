/* Run-time shader compiler loader (item XP-G25, rulings RC-B..RC-S). SDL_shadercross is loaded
   with SDL_LoadObject and its five entry points with SDL_LoadFunction, so MetalUI builds and links
   with no shadercross header or library (no pkgConfig, PX-J) and an absent library is a named
   error, not a link failure. The shadercross structs are mirrored here and pinned by static asserts
   to the layout measured at the pin (1ff05bec573988a98ef9e0260b4da44f512b8367, probe arm I).
   Compiled only under the `SDL` trait, like SDLBridge.c. */
#ifdef METALUI_SDL
#include "SDLBridge.h"
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

/* Mirrors of SDL_shadercross.h at the pin. Enums are plain `int`; the stage is compute (2). */
enum { MUI_SC_STAGE_COMPUTE = 2 };
typedef struct { char *name; char *value; } SCDefine;
typedef struct {
    const char *source;
    const char *entrypoint;
    const char *include_dir;
    SCDefine *defines;
    int shader_stage;
    uint32_t props;
} SCHLSLInfo;
typedef struct {
    const uint8_t *bytecode;
    size_t bytecode_size;
    const char *entrypoint;
    int shader_stage;
    uint32_t props;
} SCSPIRVInfo;
typedef struct {
    uint32_t num_samplers, num_readonly_storage_textures, num_readonly_storage_buffers,
             num_readwrite_storage_textures, num_readwrite_storage_buffers, num_uniform_buffers,
             threadcount_x, threadcount_y, threadcount_z;
} SCComputeMetadata;

#if UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
_Static_assert(sizeof(SCHLSLInfo) == 40 && offsetof(SCHLSLInfo, defines) == 24 && offsetof(SCHLSLInfo, shader_stage) == 32
               && offsetof(SCHLSLInfo, props) == 36, "SDL_ShaderCross_HLSL_Info layout");
_Static_assert(sizeof(SCDefine) == 16, "SDL_ShaderCross_HLSL_Define layout");
_Static_assert(sizeof(SCSPIRVInfo) == 32 && offsetof(SCSPIRVInfo, entrypoint) == 16 && offsetof(SCSPIRVInfo, shader_stage) == 24
               && offsetof(SCSPIRVInfo, props) == 28, "SDL_ShaderCross_SPIRV_Info layout");
#endif
_Static_assert(sizeof(SCComputeMetadata) == 36, "SDL_ShaderCross_ComputePipelineMetadata layout");
_Static_assert(sizeof(MuiShaderCrossReflection) == sizeof(SCComputeMetadata), "reflection mirror");

struct MuiShaderCross {
    SDL_SharedObject *object;
    bool (*init)(void);
    void *(*compile_spirv)(const SCHLSLInfo *, size_t *);
    void *(*compile_dxil)(const SCHLSLInfo *, size_t *);
    void *(*transpile_msl)(const SCSPIRVInfo *);
    SCComputeMetadata *(*reflect)(const uint8_t *, size_t, uint32_t);
};

static SDL_AtomicInt g_loads;
static SDL_AtomicInt g_empty_diagnostics;
static SDL_AtomicInt g_inited;   /* Init runs once per process (the header: once, from one thread) */

static void set_error(char *error, size_t capacity, const char *prefix) {
    if (error == NULL || capacity == 0) return;
    const char *text = SDL_GetAtomicInt(&g_empty_diagnostics) ? "" : SDL_GetError();
    snprintf(error, capacity, "%s%s", prefix, text);
}

int32_t mui_sc_loads(void) { return SDL_GetAtomicInt(&g_loads); }
void mui_sc_test_empty_diagnostics(bool empty) { SDL_SetAtomicInt(&g_empty_diagnostics, empty ? 1 : 0); }
void mui_sc_free(void *pointer) { SDL_free(pointer); }

#ifdef _WIN32
static void add_dll_directory(const char *path) {
    wchar_t wide[MAX_PATH * 2];
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, (int)(sizeof wide / sizeof wide[0]));
    if (n <= 0) return;
    wchar_t *slash = NULL;
    for (wchar_t *p = wide; *p; ++p) if (*p == L'\\' || *p == L'/') slash = p;
    if (slash == NULL) return;
    *slash = 0;
    SetDllDirectoryW(wide);
}
#endif

MuiShaderCross *mui_sc_load(const char *path, const char *const *preload, uint32_t preload_count,
                            bool counted, char *error, size_t error_capacity) {
    if (error && error_capacity) error[0] = 0;
#ifdef _WIN32
    add_dll_directory(path);
#endif
    for (uint32_t i = 0; i < preload_count; i++) {
        /* Dependents stay loaded for the life of the process: the library's own load then finds them by name. */
        SDL_ClearError();
        if (SDL_LoadObject(preload[i]) == NULL) {
            if (error && error_capacity) {
                const char *text = SDL_GetError();
                snprintf(error, error_capacity, "failed to load dependent %s: %s", preload[i], text);
            }
            return NULL;
        }
    }
    SDL_ClearError();
    SDL_SharedObject *object = SDL_LoadObject(path);
    if (object == NULL) { set_error(error, error_capacity, ""); return NULL; }
    MuiShaderCross *sc = (MuiShaderCross *)calloc(1, sizeof *sc);
    if (sc == NULL) { if (error && error_capacity) snprintf(error, error_capacity, "out of memory"); return NULL; }
    sc->object = object;
    sc->init = (bool (*)(void))SDL_LoadFunction(object, "SDL_ShaderCross_Init");
    sc->compile_spirv = (void *(*)(const SCHLSLInfo *, size_t *))SDL_LoadFunction(object, "SDL_ShaderCross_CompileSPIRVFromHLSL");
    sc->compile_dxil = (void *(*)(const SCHLSLInfo *, size_t *))SDL_LoadFunction(object, "SDL_ShaderCross_CompileDXILFromHLSL");
    sc->transpile_msl = (void *(*)(const SCSPIRVInfo *))SDL_LoadFunction(object, "SDL_ShaderCross_TranspileMSLFromSPIRV");
    sc->reflect = (SCComputeMetadata *(*)(const uint8_t *, size_t, uint32_t))SDL_LoadFunction(object, "SDL_ShaderCross_ReflectComputeSPIRV");
    if (!sc->init || !sc->compile_spirv || !sc->compile_dxil || !sc->transpile_msl || !sc->reflect) {
        if (error && error_capacity) {
            snprintf(error, error_capacity, "%s is not SDL_shadercross at the pin: %s is missing", path,
                     !sc->init ? "SDL_ShaderCross_Init" : !sc->compile_spirv ? "SDL_ShaderCross_CompileSPIRVFromHLSL"
                     : !sc->compile_dxil ? "SDL_ShaderCross_CompileDXILFromHLSL"
                     : !sc->transpile_msl ? "SDL_ShaderCross_TranspileMSLFromSPIRV" : "SDL_ShaderCross_ReflectComputeSPIRV");
        }
        free(sc);   /* the object is left loaded: a library is never unloaded (RC-B) */
        return NULL;
    }
    SDL_ClearError();
    if (SDL_CompareAndSwapAtomicInt(&g_inited, 0, 1) && !sc->init()) {
        SDL_SetAtomicInt(&g_inited, 0);
        set_error(error, error_capacity, "SDL_ShaderCross_Init failed: "); free(sc); return NULL; }
    if (counted) SDL_AddAtomicInt(&g_loads, 1);
    return sc;
}

int32_t mui_sc_compile_hlsl(const MuiShaderCross *sc, int32_t target, const char *source, const char *entry,
                            const char *include_dir, const char *const *define_names,
                            const char *const *define_values, uint32_t define_count,
                            uint8_t **out, size_t *out_size, char *error, size_t error_capacity) {
    *out = NULL; *out_size = 0;
    SCDefine *defines = NULL;
    if (define_count > 0) {
        /* The array ends with a fully NULL define (the pin's contract). */
        defines = (SCDefine *)calloc((size_t)define_count + 1, sizeof(SCDefine));
        if (defines == NULL) { snprintf(error, error_capacity, "out of memory"); return 1; }
        for (uint32_t i = 0; i < define_count; i++) {
            defines[i].name = (char *)define_names[i];
            defines[i].value = define_values[i] ? (char *)define_values[i] : NULL;
        }
    }
    SCHLSLInfo info; memset(&info, 0, sizeof info);
    info.source = source; info.entrypoint = entry; info.include_dir = include_dir;
    info.defines = defines; info.shader_stage = MUI_SC_STAGE_COMPUTE;
    size_t size = 0;
    SDL_ClearError();
    void *bytes = (target == 1 ? sc->compile_dxil : sc->compile_spirv)(&info, &size);
    if (bytes == NULL) set_error(error, error_capacity, "");   /* read before any other call (RC-D) */
    free(defines);
    if (bytes == NULL) return 1;
    *out = (uint8_t *)bytes; *out_size = size;
    return 0;
}

int32_t mui_sc_msl(const MuiShaderCross *sc, const uint8_t *spirv, size_t size, const char *entry,
                   uint8_t **out, size_t *out_size, char *error, size_t error_capacity) {
    *out = NULL; *out_size = 0;
    SCSPIRVInfo info; memset(&info, 0, sizeof info);
    info.bytecode = spirv; info.bytecode_size = size; info.entrypoint = entry; info.shader_stage = MUI_SC_STAGE_COMPUTE;
    SDL_ClearError();
    void *text = sc->transpile_msl(&info);
    if (text == NULL) { set_error(error, error_capacity, ""); return 1; }
    *out = (uint8_t *)text; *out_size = strlen((const char *)text);
    return 0;
}

int32_t mui_sc_reflect(const MuiShaderCross *sc, const uint8_t *spirv, size_t size,
                       MuiShaderCrossReflection *out, char *error, size_t error_capacity) {
    SDL_ClearError();
    SCComputeMetadata *metadata = sc->reflect(spirv, size, 0);
    if (metadata == NULL) { set_error(error, error_capacity, ""); return 1; }
    out->samplers = metadata->num_samplers;
    out->readonly_storage_textures = metadata->num_readonly_storage_textures;
    out->readonly_storage_buffers = metadata->num_readonly_storage_buffers;
    out->readwrite_storage_textures = metadata->num_readwrite_storage_textures;
    out->readwrite_storage_buffers = metadata->num_readwrite_storage_buffers;
    out->uniform_buffers = metadata->num_uniform_buffers;
    out->threadcount_x = metadata->threadcount_x;
    out->threadcount_y = metadata->threadcount_y;
    out->threadcount_z = metadata->threadcount_z;
    SDL_free(metadata);
    return 0;
}

#else
/* Built without the `SDL` trait: no SDL3 header, no SDL3 link. */
int mui_shadercross_built_without_sdl = 1;
#endif
