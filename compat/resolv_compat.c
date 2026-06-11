/*
 * resolv_compat.c — libresolv public-name shims for glibc 2.5
 *
 * On Buffalo NAS devices libresolv.so.2 exports only the private GLIBC_2.4
 * symbols __dn_expand / __res_query etc.  The public names dn_expand /
 * res_query are absent.  These thin wrappers satisfy the dynamic linker so
 * libaddns.so (pulled in by smbd) loads cleanly at runtime.
 */
#include <sys/types.h>

extern int __dn_expand(const unsigned char *msg, const unsigned char *eom,
                       const unsigned char *comp_dn, char *exp_dn, int length);
extern int __res_query(const char *dname, int class, int type,
                       unsigned char *answer, int anslen);
extern int __res_querydomain(const char *name, const char *domain,
                              int class, int type,
                              unsigned char *answer, int anslen);
extern int __res_search(const char *dname, int class, int type,
                        unsigned char *answer, int anslen);

int dn_expand(const unsigned char *msg, const unsigned char *eom,
              const unsigned char *comp_dn, char *exp_dn, int length)
{
    return __dn_expand(msg, eom, comp_dn, exp_dn, length);
}

int res_query(const char *dname, int class, int type,
              unsigned char *answer, int anslen)
{
    return __res_query(dname, class, type, answer, anslen);
}

int res_querydomain(const char *name, const char *domain,
                    int class, int type,
                    unsigned char *answer, int anslen)
{
    return __res_querydomain(name, domain, class, type, answer, anslen);
}

int res_search(const char *dname, int class, int type,
               unsigned char *answer, int anslen)
{
    return __res_search(dname, class, type, answer, anslen);
}
