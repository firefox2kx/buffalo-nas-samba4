#!/bin/bash
# deploy-prebuilt.sh — install pre-built Samba 4.1.23 on Buffalo NAS
#
# Uses the binary tarball from the repo.  No cross-compilation required.
#
# Usage: ./scripts/deploy-prebuilt.sh <NAS_IP> <NAS_USER>
#
# Example:
#   ./scripts/deploy-prebuilt.sh 192.168.1.100 root

set -e

NAS_IP="${1:?Usage: $0 <NAS_IP> <NAS_USER>}"
NAS_USER="${2:?Usage: $0 <NAS_IP> <NAS_USER>}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="$REPO_DIR/samba-4.1.23-buffalo-armv5te.tar.gz"
SHA256_FILE="$TARBALL.sha256"

SSH_OPTS="-o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa"
SSH="ssh $SSH_OPTS ${NAS_USER}@${NAS_IP}"
SCP="scp $SSH_OPTS"

if [ ! -f "$TARBALL" ]; then
    echo "ERROR: Tarball not found: $TARBALL"
    exit 1
fi

if command -v sha256sum > /dev/null && [ -f "$SHA256_FILE" ]; then
    echo "=== Verifying tarball checksum ==="
    (cd "$REPO_DIR" && sha256sum -c "$SHA256_FILE")
fi

echo "=== Creating directory structure on NAS ==="
$SSH 'mkdir -p /usr/local/samba4/{sbin,lib/private,modules/vfs} \
              /var/lib/samba/private /var/cache/samba /etc/samba/lock'

echo "=== Uploading and extracting tarball ==="
$SCP "$TARBALL" "${NAS_USER}@${NAS_IP}:/tmp/samba4.tar.gz"
$SSH 'cd / && tar xzf /tmp/samba4.tar.gz && rm /tmp/samba4.tar.gz'
$SSH 'chmod +x /usr/local/samba4/sbin/smbd'

echo "=== Installing smbd wrapper ==="
$SCP "$REPO_DIR/wrapper/smbd" "${NAS_USER}@${NAS_IP}:/usr/local/sbin/smbd"
$SSH 'chmod +x /usr/local/sbin/smbd'

echo "=== Patching /etc/init.d/smb.sh ==="
$SSH 'cp /etc/init.d/smb.sh /etc/init.d/smb.sh.bak.prebuilt'
$SSH '
if grep -q "max protocol = SMB3" /etc/init.d/smb.sh; then
    echo "smb.sh already patched, skipping"
    exit 0
fi
# Find the line number of "exit 1" inside configure() and insert after it
LINE=$(grep -n "echo \"\$0 configure fail\"" /etc/init.d/smb.sh | head -1 | cut -d: -f1)
LINE=$((LINE + 1))
sed -i "${LINE}a\\
\t/bin/sed -i '\''3i\\\\\\\\    max protocol = SMB3\\\\\\\\'\'' /etc/samba/smb.conf\\
\t/bin/sed -i '\''4i\\\\\\\\    pid directory = /var/run\\\\\\\\'\'' /etc/samba/smb.conf\\
\t/bin/sed -i '\''s|passdb backend = tdbsam:/etc/samba/smbpasswd.tdb|passdb backend = tdbsam:/var/lib/samba/private/smbpasswd.tdb|'\'' /etc/samba/smb.conf\\
\t/bin/sed -i '\''/force.*mode/d'\'' /etc/samba/smb.conf" /etc/init.d/smb.sh
echo "smb.sh patched"
'

echo "=== Patching /etc/nsswitch.conf ==="
$SSH '
cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
sed -i "s/^\(passwd:.*\) winbind/\1/" /etc/nsswitch.conf
sed -i "s/^\(group:.*\) winbind/\1/"  /etc/nsswitch.conf
sed -i "s/^\(shadow:.*\) winbind/\1/" /etc/nsswitch.conf
echo "nsswitch.conf patched"'

echo "=== Migrating passdb (if Samba 3 accounts exist) ==="
$SSH '
mkdir -p /var/lib/samba/private
if [ -f /etc/samba/smbpasswd.tdb ] && [ ! -f /var/lib/samba/private/smbpasswd.tdb ]; then
    cp /etc/samba/smbpasswd.tdb /var/lib/samba/private/smbpasswd.tdb
    echo "passdb migrated from Samba 3"
else
    echo "passdb: nothing to migrate"
fi'

echo "=== Restarting Samba ==="
$SSH '/etc/init.d/smb.sh restart'

echo ""
echo "=== Done ==="
echo "Verify: nmap -p 445 --script smb2-security-mode ${NAS_IP}"
echo "Expected: smb2-security-mode: 2.02"
