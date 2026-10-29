/* The run-time shader compiler loader (items XP-G25 and XP-G27, rulings RC-B..RC-S, HX-C, HX-D).
   SDL_shadercross is loaded with dlopen (LoadLibraryW on Windows) and its five entry points, plus the
   three SDL functions the compiler needs, are resolved through its handle. No SDL or shadercross header,
   no link: the process need not hold SDL3. No C type of this header crosses MetalUI's public surface
   (`internal import CShaderCross`). */
#ifndef CSHADERCROSS_H
#define CSHADERCROSS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct MuiRSC MuiRSC;   /* never freed: a library is never unloaded (RC-B) */

/* The compute counts and thread group SDL_CreateGPUComputePipeline needs: the nine Uint32s of
   SDL_ShaderCross_ComputePipelineMetadata, in its order. */
typedef struct {
    uint32_t samplers, readonly_storage_textures, readonly_storage_buffers,
             readwrite_storage_textures, readwrite_storage_buffers, uniform_buffers,
             threadcount_x, threadcount_y, threadcount_z;
} MuiRSCReflection;

/* 1 when an SDL3 is already in the process (POSIX: dlsym(RTLD_DEFAULT, "SDL_GetVersion") != NULL;
   Windows: GetModuleHandleW(L"SDL3.dll") != NULL). Decides whether the SDL3 preload runs (HX-D). */
bool mui_rsc_process_has_sdl3(void);

/* Loads `preload` (full paths, in order) then `path` (a full path or a bare loader name), resolves the
   five shadercross functions and SDL_GetError / SDL_ClearError / SDL_free through the shadercross
   handle (HX-D), and runs SDL_ShaderCross_Init once per process. NULL on failure with the loader's text
   (or the missing symbol) in `error`. `counted` adds one to mui_rsc_loads. On Windows the library's
   directory is added to the DLL search path first. Never unloaded. */
MuiRSC *mui_rsc_load(const char *path, const char *const *preload, uint32_t preload_count,
                     bool counted, char *error, size_t error_capacity);
/* How many counted loads happened in this process. */
int32_t mui_rsc_loads(void);
/* HLSL compute to SPIR-V (`target` 0) or DXIL (1). `*out` is shadercross-malloc'd: free it with
   mui_rsc_free. Defines are `define_count` name/value pairs (a NULL value is a bare define). 0 on success. */
int32_t mui_rsc_compile_hlsl(const MuiRSC *rsc, int32_t target, const char *source, const char *entry,
                             const char *include_dir, const char *const *define_names,
                             const char *const *define_values, uint32_t define_count,
                             uint8_t **out, size_t *out_size, char *error, size_t error_capacity);
/* SPIR-V compute to MSL text; `*out` is malloc'd by shadercross (NUL-terminated, `*out_size` without the NUL). */
int32_t mui_rsc_msl(const MuiRSC *rsc, const uint8_t *spirv, size_t size, const char *entry,
                    uint8_t **out, size_t *out_size, char *error, size_t error_capacity);
/* Reflection of a compute SPIR-V module. */
int32_t mui_rsc_reflect(const MuiRSC *rsc, const uint8_t *spirv, size_t size, MuiRSCReflection *out,
                        char *error, size_t error_capacity);
/* That instance's SDL_free for what the functions above returned. */
void mui_rsc_free(const MuiRSC *rsc, void *pointer);
/* Test hook (RC-J): while set, every failure's text is emptied. */
void mui_rsc_test_empty_diagnostics(bool empty);

#endif
