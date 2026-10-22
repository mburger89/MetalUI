/* stb-phase-split.c — how much of a stb decode is the read phase (small-items item 9, SM-A).
   Run: cc -O2 -I Sources/CStbImage stb-phase-split.c -o t && ./t a.png && ./t a.jpg   (files as in stb-callback-eof.c)
   Recorded (macOS arm64, 2026-10-22, in-memory source):
     a.png read 0.57 ms decode 20.63 ms (2048x2048)      a.jpg read 0.27 ms decode 33.23 ms (2048x2048)
   Reading: a cancel that can only land in the read callback saves at most ~3 % (PNG) / ~1 % (JPEG) of the work. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_NO_SIMD
#include "stb_image.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now(){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1e3+t.tv_nsec/1e6;}
int main(int a,char**v){double t0=now();FILE*f=fopen(v[1],"rb");fseek(f,0,SEEK_END);size_t n=ftell(f);rewind(f);unsigned char*d=malloc(n);fread(d,1,n,f);double t1=now();
int w,h,c;unsigned char*p=stbi_load_from_memory(d,(int)n,&w,&h,&c,4);double t2=now();printf("%s read %.2f ms decode %.2f ms (%dx%d)\n",v[1],t1-t0,t2-t1,w,h);}
