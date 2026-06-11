/*
 * isoc99_compat.c — glibc 2.5 compatibility shims
 *
 * Buffalo NAS devices ship with glibc 2.5.  The __isoc99_* scanf variants
 * were added in glibc 2.7 and are emitted by gcc ≥ 4.6 for C99 scanf calls.
 * These thin wrappers delegate to the vsscanf/vfscanf/vscanf functions that
 * are available in glibc 2.5, so the smbd binary links and runs correctly.
 *
 * Build into a static archive and pass -lisoc99_compat at link time.
 */
#include <stdio.h>
#include <stdarg.h>

int __isoc99_sscanf(const char *str, const char *fmt, ...) {
    va_list ap;
    int ret;
    va_start(ap, fmt);
    ret = vsscanf(str, fmt, ap);
    va_end(ap);
    return ret;
}

int __isoc99_fscanf(FILE *stream, const char *fmt, ...) {
    va_list ap;
    int ret;
    va_start(ap, fmt);
    ret = vfscanf(stream, fmt, ap);
    va_end(ap);
    return ret;
}

int __isoc99_scanf(const char *fmt, ...) {
    va_list ap;
    int ret;
    va_start(ap, fmt);
    ret = vscanf(fmt, ap);
    va_end(ap);
    return ret;
}

int __isoc99_vsscanf(const char *str, const char *fmt, va_list ap) {
    return vsscanf(str, fmt, ap);
}

int __isoc99_vfscanf(FILE *stream, const char *fmt, va_list ap) {
    return vfscanf(stream, fmt, ap);
}

int __isoc99_vscanf(const char *fmt, va_list ap) {
    return vscanf(fmt, ap);
}
