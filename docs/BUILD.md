# Build Guide — Samba 4.1.23 for Buffalo NAS (armv5te / glibc 2.5)

## Host requirements

Tested on Ubuntu 22.04 / Debian 12.

```
apt-get install \
    gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
    qemu-user-static \
    python3 python3-dev \
    pkg-config libgnutls28-dev
```

## 1. Prepare the sysroot

The sysroot provides headers and libraries from the NAS so that the linker
can resolve symbols at build time.  You need a copy of the following
directories from a live NAS or firmware image:

```
/lib/          (libc, libm, libpthread, libresolv, …)
/usr/lib/
/usr/local/lib/
/usr/include/
```

Copy them to a single directory, e.g. `~/build/nas-sysroot`:

```sh
rsync -a root@<NAS_IP>:/lib     ~/build/nas-sysroot/
rsync -a root@<NAS_IP>:/usr/lib ~/build/nas-sysroot/usr/
rsync -a root@<NAS_IP>:/usr/include ~/build/nas-sysroot/usr/
```

## 2. Download Samba 4.1.23

```sh
wget https://download.samba.org/pub/samba/stable/samba-4.1.23.tar.gz
tar xzf samba-4.1.23.tar.gz
```

## 3. Build the compatibility library

gcc ≥ 4.6 emits `__isoc99_sscanf` / `__isoc99_fscanf` calls for C99 scanf
usage.  These symbols were added in glibc 2.7; the NAS ships glibc 2.5.
The `compat/` directory contains thin wrappers that delegate to the
`v*scanf` functions available in glibc 2.5.

```sh
cd compat/
make
# Produces: libisoc99_compat.a
cd ..
```

## 4. Apply source patch

The patch adds an `apply_hostcc` waf feature decorator to
`buildtools/wafsamba/samba_optimisation.py`.  Without it, build-time host
tools (`asn1_compile`, `compile_et`) are cross-compiled and cannot run on
the build host.

```sh
cd samba-4.1.23/
patch -p1 < ../patches/0001-wafsamba-apply-hostcc.diff
```

## 5. Configure

```sh
SYSROOT=~/build/nas-sysroot
COMPAT=~/buffalo-nas-samba4/compat

./configure \
    --cross-compile \
    --cross-execute="qemu-arm-static -L $SYSROOT" \
    CC=arm-linux-gnueabi-gcc \
    AR=arm-linux-gnueabi-ar \
    RANLIB=arm-linux-gnueabi-ranlib \
    STRIP=arm-linux-gnueabi-strip \
    CFLAGS="-march=armv5te -mfloat-abi=soft -Os -D_FORTIFY_SOURCE=0 -B${COMPAT}" \
    LDFLAGS="-march=armv5te -mfloat-abi=soft \
             -B${COMPAT} -L${COMPAT} \
             -L${SYSROOT}/lib -L${SYSROOT}/usr/lib -L${SYSROOT}/usr/local/lib \
             -Wl,-rpath-link,${SYSROOT}/lib \
             -Wl,-rpath-link,${SYSROOT}/usr/lib \
             -Wl,-rpath-link,${SYSROOT}/usr/local/lib \
             -lisoc99_compat" \
    --prefix=/usr/local/samba4 \
    --without-ads \
    --without-ldap \
    --without-pam \
    --without-acl-support \
    --disable-python \
    --without-dmapi \
    --without-fam
```

`--cross-execute` uses qemu-arm-static to run ARM test binaries on the
host — no cross-answers file is needed.

## 6. Patch generated config.h

After configure, disable `_FILE_OFFSET_BITS=64`.  glibc 2.5 does not
implement the full 64-bit file offset API surface used by Samba:

```sh
sed -i 's|^#define _FILE_OFFSET_BITS 64|/* #undef _FILE_OFFSET_BITS */|' \
    bin/default/include/config.h
```

## 7. Build

Build only the targets you need (full `waf build` would also attempt
Samba4/AD/Python targets that will not cross-compile cleanly):

```sh
# smbd daemon
./buildtools/bin/waf build --targets=smbd/smbd

# Recycle-bin VFS module (optional but recommended)
./buildtools/bin/waf build --targets=vfs_recycle
```

Build takes roughly 10–15 minutes on a modern host.

## 8. Output files

| File | Purpose |
|------|---------|
| `bin/smbd` | smbd daemon binary (ARM ELF) |
| `bin/modules/vfs/recycle.so` → `bin/default/source3/modules/libvfs-recycle.so` | Recycle-bin VFS module |
| `bin/libsamba*.so`, `bin/libtalloc*.so`, … | Shared libraries needed at runtime |

Continue with [DEPLOY.md](DEPLOY.md).
