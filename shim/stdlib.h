/* Minimal stdlib.h shim for wasm32-freestanding. stb_image's allocation is
 * redirected to the bump allocator via STBI_MALLOC/REALLOC/FREE, so only
 * types and NULL are needed here. */
#ifndef SHIM_STDLIB_H
#define SHIM_STDLIB_H
#include <stddef.h>
#endif
