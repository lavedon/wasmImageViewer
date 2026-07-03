/* Minimal string.h shim for wasm32-freestanding. Implementations live in
 * viewer.c. */
#ifndef SHIM_STRING_H
#define SHIM_STRING_H
#include <stddef.h>
void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
#endif
