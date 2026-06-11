#!/bin/bash
# build.sh — cross-compile Samba 4.1.23 for Buffalo NAS (armv5te, glibc 2.5)
#
# Prerequisites (Ubuntu/Debian host):
#   apt-get install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
#                   qemu-user-static python3 pkg-config
#
# Usage: ./scripts/build.sh [/path/to/samba-4.1.23] [/path/to/sysroot]
#
# The sysroot must contain the NAS lib/usr/lib tree; see docs/BUILD.md for
# how to create it from the firmware.

set -e

SAMBA_SRC="${1:-$HOME/build/samba-src/samba-4.1.23}"
SYSROOT="${2:-$HOME/build/nas-sysroot}"
COMPAT_DIR="$(dirname "$0")/../compat"
CROSS_PREFIX="arm-linux-gnueabi"
CROSS_CC="${CROSS_PREFIX}-gcc"
CROSS_AR="${CROSS_PREFIX}-ar"

if [ ! -d "$SAMBA_SRC" ]; then
    echo "ERROR: Samba source not found at $SAMBA_SRC"
    echo "Download: https://download.samba.org/pub/samba/stable/samba-4.1.23.tar.gz"
    exit 1
fi

if [ ! -d "$SYSROOT" ]; then
    echo "ERROR: Sysroot not found at $SYSROOT"
    echo "See docs/BUILD.md — 'Preparing the sysroot'"
    exit 1
fi

echo "=== Step 1: Build compatibility library ==="
cd "$COMPAT_DIR"
CC="$CROSS_CC" AR="$CROSS_AR" make clean all
COMPAT_LIB="$(pwd)/libisoc99_compat.a"
cd - > /dev/null

echo "=== Step 2: Apply source patches ==="
cd "$SAMBA_SRC"

# Patch 0001: apply_hostcc in samba_optimisation.py
if ! grep -q 'apply_hostcc' buildtools/wafsamba/samba_optimisation.py; then
    patch -p1 < "$(dirname "$0")/../patches/0001-wafsamba-apply-hostcc.diff"
    echo "  Applied: 0001-wafsamba-apply-hostcc.diff"
else
    echo "  Skipped (already applied): 0001-wafsamba-apply-hostcc.diff"
fi

echo "=== Step 3: Configure ==="
./configure \
    --cross-compile \
    --cross-answers=cross-answers-armv5te.txt \
    --cross-execute="qemu-arm-static -L $SYSROOT" \
    CC="$CROSS_CC" \
    AR="$CROSS_AR" \
    RANLIB="${CROSS_PREFIX}-ranlib" \
    STRIP="${CROSS_PREFIX}-strip" \
    CFLAGS="-march=armv5te -mfloat-abi=soft -Os -D_FORTIFY_SOURCE=0 -B${COMPAT_DIR}" \
    LDFLAGS="-march=armv5te -mfloat-abi=soft -B${COMPAT_DIR} -L${COMPAT_DIR} \
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
    --without-fam \
    2>&1 | tee configure.log

echo "=== Step 4: Patch generated config.h ==="
sed -i 's|^#define _FILE_OFFSET_BITS 64|/* #undef _FILE_OFFSET_BITS */|' \
    bin/default/include/config.h
echo "  _FILE_OFFSET_BITS disabled in config.h"

echo "=== Step 5: Build smbd ==="
./buildtools/bin/waf build --targets=smbd/smbd 2>&1 | tee build-smbd.log

echo "=== Step 6: Build vfs_recycle ==="
./buildtools/bin/waf build --targets=vfs_recycle 2>&1 | tee build-vfs.log

echo ""
echo "=== Build complete ==="
echo "  smbd:       $SAMBA_SRC/bin/smbd"
echo "  recycle.so: $SAMBA_SRC/bin/modules/vfs/recycle.so"
echo ""
echo "Next: run scripts/deploy.sh"
