/* The portable decoder's rule (ruling PX-C), standalone: stb_image v2.30 with
   PNG and JPEG only and no stdio; 16-bit files decoded at 16 bits and rounded
   to 8 ((v * 255 + 32767) / 65535 — stb's own 8-bit path truncates, v >> 8,
   which differs from ImageIO by up to 2); then the straight-to-premultiplied
   rule of ImageTexture(width:height:straightRGBA:) ((c * a + 127) / 255).
   Prints "w h" and the premultiplied bytes, or "nil <reason>".
   Build: clang -O1 -I <dir holding stb_image.h> stb-decode.c -o stb-decode */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#include "stb_image.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); if (!f) { printf("nil open\n"); return 0; }
    fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    unsigned char *b = malloc(n); fread(b, 1, n, f); fclose(f);
    int w, h, ch; unsigned char *p8 = NULL; unsigned short *p16 = NULL;
    if (stbi_is_16_bit_from_memory(b, (int)n)) p16 = stbi_load_16_from_memory(b, (int)n, &w, &h, &ch, 4);
    else p8 = stbi_load_from_memory(b, (int)n, &w, &h, &ch, 4);
    if (!p8 && !p16) { printf("nil %s\n", stbi_failure_reason()); return 0; }
    printf("%d %d\n", w, h);
    for (long i = 0; i < (long)w * h * 4; i += 4) {
        unsigned px[4];
        for (int k = 0; k < 4; k++) px[k] = p16 ? (p16[i + k] * 255u + 32767u) / 65535u : p8[i + k];
        for (int k = 0; k < 3; k++) printf("%u ", (px[k] * px[3] + 127) / 255);
        printf("%u ", px[3]);
    }
    printf("\n");
    return 0;
}
