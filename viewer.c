/*
 * Experimental wasm image viewer.
 *
 * All images from the manifest are decoded and downscaled into wasm linear
 * memory up front (slow load, fast viewing). JS is a dumb shim: it feeds in
 * file bytes, forwards advance events, and blits the framebuffer we hand back.
 *
 * Build: zig cc -target wasm32-freestanding (see build.ps1). No libc.
 */

#include <stddef.h>
#include <stdint.h>

#define WASM_EXPORT(name) __attribute__((export_name(name)))

/* ---------------------------------------------------------------- memory --
 * Bump allocator over linear memory. Nothing loaded is ever freed, which is
 * exactly the lifetime this app has. Each block gets an 8-byte size header
 * so realloc (needed by stb) can copy the old contents.
 */

extern unsigned char __heap_base;
static uintptr_t heap_ptr = 0;

static void *wa_malloc(size_t n) {
    if (heap_ptr == 0) heap_ptr = (uintptr_t)&__heap_base;
    heap_ptr = (heap_ptr + 7u) & ~(uintptr_t)7u;
    uintptr_t block = heap_ptr;
    uintptr_t end = block + 8 + n;
    size_t have = (size_t)__builtin_wasm_memory_size(0) * 65536u;
    if (end > have) {
        size_t need_pages = (end - have + 65535u) / 65536u;
        if (__builtin_wasm_memory_grow(0, need_pages) == (size_t)-1) return NULL;
    }
    *(size_t *)block = n;
    heap_ptr = end;
    return (void *)(block + 8);
}

static void wa_free(void *p) { (void)p; }

static void *wa_realloc(void *p, size_t n) {
    void *q = wa_malloc(n);
    if (!q || !p) return q;
    size_t old = *(size_t *)((uintptr_t)p - 8);
    size_t copy = old < n ? old : n;
    unsigned char *d = q;
    const unsigned char *s = p;
    for (size_t i = 0; i < copy; i++) d[i] = s[i];
    return q;
}

/* Freestanding: clang emits calls to these even without libc. */
void *memset(void *dst, int c, size_t n) {
    unsigned char *d = dst;
    for (size_t i = 0; i < n; i++) d[i] = (unsigned char)c;
    return dst;
}
void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dst;
}
void *memmove(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    if (d < s) { for (size_t i = 0; i < n; i++) d[i] = s[i]; }
    else       { for (size_t i = n; i > 0; i--) d[i-1] = s[i-1]; }
    return dst;
}

static int wa_abs(int v) { return v < 0 ? -v : v; }

/* ------------------------------------------------------------- stb_image -- */

#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_NO_THREAD_LOCALS
#define STBI_ASSERT(x) ((void)0)
#define STBI_MALLOC(n) wa_malloc(n)
#define STBI_REALLOC(p, n) wa_realloc(p, n)
#define STBI_FREE(p) wa_free(p)
#define abs wa_abs
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#undef abs

/* ----------------------------------------------------------------- state -- */

#define MAX_IMAGES 256
#define MAX_WIDTH 1600      /* downscale cap: quality traded for memory */
#define PAGE_SIZE 3

typedef struct {
    uint32_t *px;           /* RGBA */
    int w, h;
} Image;

static Image images[MAX_IMAGES];
static int image_count = 0;
static size_t pixel_bytes_total = 0;

static int page[PAGE_SIZE];  /* indices of images on the current page */
static int page_count = 0;   /* images currently stacked on the page */
static int cursor = 0;       /* next image index to show */

static uint32_t *fb = NULL;
static int fb_w = 0, fb_h = 0;
static size_t fb_cap = 0;

/* --------------------------------------------------------------- loading -- */

WASM_EXPORT("wa_alloc")
void *wa_alloc_export(size_t n) { return wa_malloc(n); }

/* Box-filter downscale to MAX_WIDTH, aspect preserved. */
static void downscale(const unsigned char *src, int sw, int sh, Image *out) {
    int dw = MAX_WIDTH;
    int dh = (int)((int64_t)sh * dw / sw);
    if (dh < 1) dh = 1;
    uint32_t *dst = wa_malloc((size_t)dw * dh * 4);
    if (!dst) { out->px = NULL; return; }
    for (int y = 0; y < dh; y++) {
        int sy0 = (int)((int64_t)y * sh / dh);
        int sy1 = (int)((int64_t)(y + 1) * sh / dh);
        if (sy1 <= sy0) sy1 = sy0 + 1;
        for (int x = 0; x < dw; x++) {
            int sx0 = (int)((int64_t)x * sw / dw);
            int sx1 = (int)((int64_t)(x + 1) * sw / dw);
            if (sx1 <= sx0) sx1 = sx0 + 1;
            uint32_t r = 0, g = 0, b = 0, a = 0, n = 0;
            for (int sy = sy0; sy < sy1; sy++) {
                const unsigned char *row = src + ((size_t)sy * sw + sx0) * 4;
                for (int sx = sx0; sx < sx1; sx++) {
                    r += row[0]; g += row[1]; b += row[2]; a += row[3];
                    row += 4;
                    n++;
                }
            }
            dst[(size_t)y * dw + x] =
                (uint32_t)(r / n) | ((uint32_t)(g / n) << 8) |
                ((uint32_t)(b / n) << 16) | ((uint32_t)(a / n) << 24);
        }
    }
    out->px = dst;
    out->w = dw;
    out->h = dh;
}

/* Decode file bytes already copied into wasm memory; keep only the
 * (possibly downscaled) pixel buffer. Returns 1 on success.
 *
 * The bump allocator can't free, so scratch (the compressed file bytes,
 * stb's decode temporaries, and the full-res pixels) would leak ~10x the
 * kept size per image. Instead, the kept buffer is slid down over the
 * scratch region and the bump pointer rewound, so only downscaled pixels
 * accumulate across the load. */
WASM_EXPORT("wa_load_image")
int wa_load_image(const unsigned char *data, int len) {
    if (image_count >= MAX_IMAGES) return 0;
    uintptr_t mark = (uintptr_t)data - 8; /* start of the file-bytes block */
    int w, h, comp;
    unsigned char *px = stbi_load_from_memory(data, len, &w, &h, &comp, 4);
    if (!px) { heap_ptr = mark; return 0; }
    Image *img = &images[image_count];
    if (w > MAX_WIDTH) {
        downscale(px, w, h, img);
        if (!img->px) { heap_ptr = mark; return 0; }
    } else {
        img->px = (uint32_t *)px;
        img->w = w;
        img->h = h;
    }
    size_t keep = (size_t)img->w * img->h * 4;
    memmove((void *)mark, img->px, keep);
    img->px = (uint32_t *)mark;
    heap_ptr = mark + keep;
    pixel_bytes_total += keep;
    image_count++;
    return 1;
}

WASM_EXPORT("wa_image_count") int wa_image_count(void) { return image_count; }
WASM_EXPORT("wa_pixel_bytes") size_t wa_pixel_bytes(void) { return pixel_bytes_total; }
WASM_EXPORT("wa_heap_bytes")
size_t wa_heap_bytes(void) { return (size_t)__builtin_wasm_memory_size(0) * 65536u; }

/* ------------------------------------------------------------------ auth --
 * Demo gate only, not security: constants live in the shipped binary. */

static const char AUTH_USER[] = "demo";
static const char AUTH_PASS[] = "demo";

static int str_eq(const char *a, int alen, const char *b) {
    int i = 0;
    for (; i < alen; i++) {
        if (b[i] == '\0' || a[i] != b[i]) return 0;
    }
    return b[i] == '\0';
}

WASM_EXPORT("wa_check_login")
int wa_check_login(const char *user, int ulen, const char *pass, int plen) {
    return str_eq(user, ulen, AUTH_USER) && str_eq(pass, plen, AUTH_PASS);
}

/* --------------------------------------------------------------- viewing -- */

#define BG_PIXEL 0xFF181818u  /* ABGR in memory: dark gray, opaque */

static void composite(void) {
    int w = 0, h = 0;
    for (int i = 0; i < page_count; i++) {
        Image *img = &images[page[i]];
        if (img->w > w) w = img->w;
        h += img->h;
    }
    if (w == 0 || h == 0) return;
    size_t need = (size_t)w * h * 4;
    if (need > fb_cap) {
        fb = wa_malloc(need);
        fb_cap = fb ? need : 0;
        if (!fb) return;
    }
    fb_w = w;
    fb_h = h;
    for (size_t i = 0, n = (size_t)w * h; i < n; i++) fb[i] = BG_PIXEL;
    int y = 0;
    for (int i = 0; i < page_count; i++) {
        Image *img = &images[page[i]];
        int x0 = (w - img->w) / 2;
        for (int row = 0; row < img->h; row++)
            memcpy(fb + (size_t)(y + row) * w + x0,
                   img->px + (size_t)row * img->w,
                   (size_t)img->w * 4);
        y += img->h;
    }
}

/* Advance: add the next image to the page, or start a new page after the
 * 3rd. Wraps past the last image. Recomposites the framebuffer. */
WASM_EXPORT("wa_advance")
void wa_advance(void) {
    if (image_count == 0) return;
    if (page_count >= PAGE_SIZE) page_count = 0;
    page[page_count++] = cursor;
    cursor = (cursor + 1) % image_count;
    composite();
}

WASM_EXPORT("wa_fb_ptr") uint32_t *wa_fb_ptr(void) { return fb; }
WASM_EXPORT("wa_fb_width") int wa_fb_width(void) { return fb_w; }
WASM_EXPORT("wa_fb_height") int wa_fb_height(void) { return fb_h; }
