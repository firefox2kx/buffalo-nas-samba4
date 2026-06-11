#!/bin/bash
# deploy.sh — deploy Samba 4.1.23 to Buffalo NAS
#
# Usage: ./scripts/deploy.sh <NAS_IP> <NAS_USER> [/path/to/samba-4.1.23]
#
# The NAS must be reachable via SSH.  Buffalo firmware requires legacy key
# exchange; this script sets the necessary SSH options automatically.

set -e

NAS_IP="${1:?Usage: $0 <NAS_IP> <NAS_USER> [/path/to/samba-4.1.23]}"
NAS_USER="${2:?Usage: $0 <NAS_IP> <NAS_USER> [/path/to/samba-4.1.23]}"
SAMBA_SRC="${3:-$HOME/build/samba-src/samba-4.1.23}"
REPO_DIR="$(dirname "$0")/.."

SSH_OPTS="-o KexAlgorithms=diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa"
SSH="ssh $SSH_OPTS ${NAS_USER}@${NAS_IP}"
SCP="scp $SSH_OPTS"

echo "=== Deploying Samba 4.1.23 to ${NAS_USER}@${NAS_IP} ==="

echo "--- Creating directory structure ---"
$SSH 'mkdir -p /usr/local/samba4/{sbin,lib/private,modules/vfs} /var/lib/samba/private /var/cache/samba /etc/samba/lock'

echo "--- Deploying smbd binary ---"
$SCP "$SAMBA_SRC/bin/smbd" "${NAS_USER}@${NAS_IP}:/usr/local/samba4/sbin/smbd"
$SSH 'chmod +x /usr/local/samba4/sbin/smbd'

echo "--- Deploying shared libraries ---"
find "$SAMBA_SRC/bin" -name '*.so' -not -name 'recycle.so' | while read lib; do
    base="$(basename "$lib")"
    # private libs go to lib/private, public to lib/
    if echo "$lib" | grep -q '/private/'; then
        $SCP "$lib" "${NAS_USER}@${NAS_IP}:/usr/local/samba4/lib/private/${base}"
    else
        $SCP "$lib" "${NAS_USER}@${NAS_IP}:/usr/local/samba4/lib/${base}"
    fi
done

echo "--- Deploying vfs_recycle.so ---"
$SCP "$SAMBA_SRC/bin/modules/vfs/recycle.so" \
    "${NAS_USER}@${NAS_IP}:/usr/local/samba4/modules/vfs/recycle.so"

echo "--- Creating symlink: smbd build-tree modules → /usr/local/samba4/modules ---"
# smbd (built without 'waf install') looks for VFS modules at its build-tree
# path bin/modules/.  The symlink redirects that path to the installed location.
BUILDTREE_MODULES="$SAMBA_SRC/bin/modules"
$SSH "ln -sfn /usr/local/samba4/modules '$BUILDTREE_MODULES'"

echo "--- Installing smbd wrapper ---"
$SCP "$REPO_DIR/wrapper/smbd" "${NAS_USER}@${NAS_IP}:/usr/local/sbin/smbd"
$SSH 'chmod +x /usr/local/sbin/smbd'

echo "--- Patching /etc/init.d/smb.sh ---"
$SSH 'cp /etc/init.d/smb.sh /etc/init.d/smb.sh.bak'
$SSH '
grep -q "max protocol = SMB3" /etc/init.d/smb.sh && { echo "smb.sh already patched, skipping"; exit 0; }
# Insert after the "exit 1" line that follows nas_configgen error check
sed -i "/echo \"\$0 configure fail\"/{n;n;a\\
\\t/bin/sed -i '\''3i\\\\\\\\    max protocol = SMB3\\\\\\\\'\'' /etc/samba/smb.conf\\
\\t/bin/sed -i '\''4i\\\\\\\\    pid directory = /var/run\\\\\\\\'\'' /etc/samba/smb.conf\\
\\t/bin/sed -i '\''s|passdb backend = tdbsam:/etc/samba/smbpasswd.tdb|passdb backend = tdbsam:/var/lib/samba/private/smbpasswd.tdb|'\'' /etc/samba/smb.conf\\
\\t/bin/sed -i '\''/force.*mode/d'\'' /etc/samba/smb.conf
}" /etc/init.d/smb.sh
echo "smb.sh patched"
'

echo "--- Patching /etc/nsswitch.conf ---"
$SSH 'cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
sed -i "s/^\(passwd:.*\) winbind/\1/" /etc/nsswitch.conf
sed -i "s/^\(group:.*\) winbind/\1/" /etc/nsswitch.conf
sed -i "s/^\(shadow:.*\) winbind/\1/" /etc/nsswitch.conf
echo "nsswitch.conf patched"'

echo "--- Initialising passdb ---"
$SSH 'mkdir -p /var/lib/samba/private
# Copy existing smbpasswd.tdb if Samba 3 one exists
[ -f /etc/samba/smbpasswd.tdb ] && cp /etc/samba/smbpasswd.tdb /var/lib/samba/private/smbpasswd.tdb
echo "passdb ready at /var/lib/samba/private/smbpasswd.tdb"'

echo "--- Restarting Samba ---"
$SSH '/etc/init.d/smb.sh restart'

echo ""
echo "=== Deployment complete ==="
echo "Verify with: nmap -p 445 --script smb2-security-mode ${NAS_IP}"
