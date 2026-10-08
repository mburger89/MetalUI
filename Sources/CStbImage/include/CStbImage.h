/* MetalUI's view of stb_image 2.30 (ruling PX-B): only the five functions
   MetalUI calls, declared with plain C types (stb_image.h's stbi_uc and
   stbi_us are unsigned char and unsigned short). The implementation, and the
   defines it is compiled with, are CStbImage.c. No C type of this header
   crosses MetalUI's public surface (`internal import CStbImage`). */
#ifndef CSTBIMAGE_H
#define CSTBIMAGE_H

#ifdef __cplusplus
extern "C" {
#endif

/* 8-bit samples, `desired_channels` per pixel; NULL on failure. */
extern unsigned char *stbi_load_from_memory(unsigned char const *buffer, int len, int *x, int *y,
                                            int *channels_in_file, int desired_channels);
/* 16-bit samples; NULL on failure. */
extern unsigned short *stbi_load_16_from_memory(unsigned char const *buffer, int len, int *x, int *y,
                                                int *channels_in_file, int desired_channels);
/* 1 when the file is a 16-bit PNG. */
extern int stbi_is_16_bit_from_memory(unsigned char const *buffer, int len);
/* The file's size and channel count without decoding; 0 on failure. */
extern int stbi_info_from_memory(unsigned char const *buffer, int len, int *x, int *y, int *comp);
/* Frees what a load returned. */
extern void stbi_image_free(void *retval_from_stbi_load);

#ifdef __cplusplus
}
#endif

#endif
