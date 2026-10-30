/* A stand-in for shadercross (XP-G35 / BT-X): finds `-o <path>` and writes a non-empty file there
   (`{}` for a .json path), exit 0. Enough for the plugin's compile arm to succeed. */
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *out = NULL;
    for (int i = 1; i + 1 < argc; i++) if (strcmp(argv[i], "-o") == 0) out = argv[i + 1];
    if (!out) { fprintf(stderr, "stub: no -o\n"); return 2; }
    FILE *file = fopen(out, "wb");
    if (!file) { fprintf(stderr, "stub: cannot write %s\n", out); return 3; }
    size_t length = strlen(out);
    fputs(length >= 5 && strcmp(out + length - 5, ".json") == 0 ? "{}" : "stub\n", file);
    fclose(file);
    return 0;
}
