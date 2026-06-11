#!/bin/bash
# make-release.sh — package a new pre-built release tarball
#
# Run this after a successful build to regenerate the tarball.
# The resulting tarball is portable: the wrapper passes --modulesdir explicitly
# so no symlinks or build-path knowledge is required on the target NAS.
#
# Usage: ./scripts/make-release.sh /path/to/samba-4.1.23

set -e

SAMBA_SRC="${1:-$HOME/build/samba-src/samba-4.1.23}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK=/tmp/samba4-release-$$
TARBALL="$REPO_DIR/samba-4.1.23-buffalo-armv5te.tar.gz"

if [ ! -f "$SAMBA_SRC/bin/smbd" ]; then
    echo "ERROR: smbd not found in $SAMBA_SRC/bin/ — run scripts/build.sh first"
    exit 1
fi

echo "=== Assembling install tree ==="
rm -rf "$WORK"
mkdir -p "$WORK/usr/local/samba4/"{sbin,lib/private,modules/vfs}

cp "$SAMBA_SRC/bin/smbd" "$WORK/usr/local/samba4/sbin/smbd"
chmod +x "$WORK/usr/local/samba4/sbin/smbd"

# Public shared libs (skip broken symlinks for unbuilt targets)
for f in "$SAMBA_SRC/bin/shared/"*.so*; do
    [ -f "$f" ] && cp "$f" "$WORK/usr/local/samba4/lib/"
done

# Private shared libs
for f in "$SAMBA_SRC/bin/shared/private/"*.so*; do
    [ -f "$f" ] && cp "$f" "$WORK/usr/local/samba4/lib/private/"
done

# VFS recycle
cp "$SAMBA_SRC/bin/default/source3/modules/libvfs-recycle.so" \
   "$WORK/usr/local/samba4/modules/vfs/recycle.so"

echo "Files: $(find "$WORK" -type f | wc -l)"
echo "Size:  $(du -sh "$WORK" | cut -f1)"

echo "=== Creating tarball ==="
(cd "$WORK" && tar czf "$TARBALL" usr/)
echo "=== Generating checksum ==="
(cd "$REPO_DIR" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256")

rm -rf "$WORK"

echo ""
echo "Created: $TARBALL"
echo "$(cat "$TARBALL.sha256")"
ls -lh "$TARBALL"
