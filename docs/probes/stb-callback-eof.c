/* stb-callback-eof.c — what stb_image 2.30 does when an stbi_io_callbacks read callback
   reports EOF early (small-items item 9, ruling SM-A / IH-K).
   Run: python3 the PNG generator in the header below -> /tmp/a.png (2048x2048 RGBA, 1.97 MB, 61 reads);
        sips -s format jpeg a.png --out a.jpg (1.36 MB, 10641 reads);
        cc -O1 -I Sources/CStbImage stb-callback-eof.c -o probe && ./probe a.png && ./probe a.jpg
   Recorded output (macOS arm64, 2026-10-22, same #defines as Sources/CStbImage/CStbImage.c):
     a.png cancelAfter=0 -> NULL reads=0 ; =3 -> NULL reads=3 bytes=65705/1965565 ; =50 -> NULL ; =1000000 -> IMAGE (byte-identical to from_memory)
     a.jpg cancelAfter=0 -> NULL ; =1 -> NULL ; =3 -> IMAGE (partial, zero-padded) reads=3 bytes=384/1362069 ; =50 -> IMAGE reads=50
   Reading: a PNG fails on a truncated IDAT stream; a JPEG after its header returns a FULL-SIZE IMAGE built from zeros.
   So an EOF callback alone breaks the truncation rule (partial image); a cancel flag must be checked after the call.
   Separating arm: cancelAfter=-1 (never) -> IMAGE, identical to stbi_load_from_memory. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_NO_SIMD
#define STBI_MAX_DIMENSIONS 16384
#include "stb_image.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { unsigned char*d; size_t n,pos; long reads,bytes; long cancelAfterReads; int cancelled; long eofs; } Ctx;
static int rd(void*u,char*b,int sz){Ctx*c=u; if(c->cancelAfterReads>=0&&c->reads>=c->cancelAfterReads){c->cancelled=1;c->eofs++;return 0;} c->reads++; size_t k=c->n-c->pos; if(k>(size_t)sz)k=sz; memcpy(b,c->d+c->pos,k); c->pos+=k; c->bytes+=k; return (int)k;}
static void sk(void*u,int n){Ctx*c=u; if(n>0){c->pos+=n; if(c->pos>c->n)c->pos=c->n;} else c->pos= (n<0 && (size_t)-n>c->pos)?0:c->pos+n;}
static int eof(void*u){Ctx*c=u; return c->cancelled||c->pos>=c->n;}
int main(int a,char**v){FILE*f=fopen(v[1],"rb");fseek(f,0,SEEK_END);size_t n=ftell(f);rewind(f);unsigned char*d=malloc(n);fread(d,1,n,f);
 stbi_io_callbacks cb={rd,sk,eof};
 long afters[]={-1,0,1,3,10,50,1000000};
 for(int i=0;i<7;i++){Ctx c={d,n,0,0,0,afters[i],0,0}; int w,h,ch; unsigned char*p=stbi_load_from_callbacks(&cb,&c,&w,&h,&ch,4);
  printf("%s cancelAfter=%ld -> %s reads=%ld bytes=%ld/%zu eofs=%ld\n",v[1],afters[i],p?"IMAGE":"NULL",c.reads,c.bytes,n,c.eofs); stbi_image_free(p);} 
 /* memory vs callbacks identical? */
 int w,h,ch; unsigned char*m=stbi_load_from_memory(d,(int)n,&w,&h,&ch,4); Ctx c={d,n,0,0,0,-1,0,0}; int w2,h2; unsigned char*p=stbi_load_from_callbacks(&cb,&c,&w2,&h2,&ch,4);
 printf("identical=%d reads(buffer 4096)=%ld\n", m&&p&&w==w2&&h==h2&&!memcmp(m,p,(size_t)w*h*4), c.reads); return 0;}
