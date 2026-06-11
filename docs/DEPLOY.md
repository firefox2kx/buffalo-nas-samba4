# Deployment Guide — Samba 4.1.23 on Buffalo NAS

## SSH access

Buffalo firmware uses legacy SSH key exchange algorithms.  Always connect
with:

```sh
ssh -o KexAlgorithms=diffie-hellman-group1-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    root@<NAS_IP>
```

For scripted deployment, use `sshpass`:

```sh
apt-get install sshpass
sshpass -p '<password>' ssh ...
```

Or set up key-based auth (`ssh-copy-id` works with the options above).

The automated script `scripts/deploy.sh` handles all steps below:

```sh
./scripts/deploy.sh <NAS_IP> root
```

## Manual deployment

### 1. Create directories on NAS

```sh
mkdir -p /usr/local/samba4/{sbin,lib/private,modules/vfs}
mkdir -p /var/lib/samba/private
mkdir -p /var/cache/samba
mkdir -p /etc/samba/lock
```

### 2. Deploy smbd binary

```sh
scp [...] bin/smbd root@<NAS_IP>:/usr/local/samba4/sbin/smbd
ssh  [...] root@<NAS_IP> 'chmod +x /usr/local/samba4/sbin/smbd'
```

### 3. Deploy shared libraries

Copy all `bin/libsamba*.so`, `bin/libtalloc*.so`, `bin/libtdb*.so`, and
other `.so` files from the build tree:

```sh
for lib in bin/*.so; do
    scp [...] "$lib" root@<NAS_IP>:/usr/local/samba4/lib/
done
# Private libs (in bin/private/ or matching *samba4*.so):
for lib in bin/private/*.so; do
    scp [...] "$lib" root@<NAS_IP>:/usr/local/samba4/lib/private/
done
```

### 4. Deploy vfs_recycle.so

```sh
scp [...] bin/modules/vfs/recycle.so \
    root@<NAS_IP>:/usr/local/samba4/modules/vfs/recycle.so
```

### 5. Module path symlink

`smbd` is built without `waf install`, so it looks for VFS modules at its
build-tree path.  A symlink redirects that to the installed location:

```sh
# On the NAS:
BUILDTREE_MODULES=/path/to/samba-4.1.23/bin/modules
ln -sfn /usr/local/samba4/modules "$BUILDTREE_MODULES"
```

The path must match the build host path.  If you used `/home/user/build/...`,
set that path here.  Alternatively, `waf install` eliminates the need for
this symlink (see note below).

> **Note:** Running `waf install` (with `--destdir=`) would install smbd to
> a path where it looks for modules relative to `MODULESDIR` (set to
> `/usr/local/lib/samba` at configure time), removing the need for the
> symlink.  The deploy script uses the symlink approach to keep things
> explicit and reversible.

### 6. Install smbd wrapper

The Buffalo firmware calls `/usr/local/sbin/smbd` to start Samba.  This
wrapper replaces the original Samba 3 binary:

```sh
cp wrapper/smbd /usr/local/sbin/smbd
chmod +x /usr/local/sbin/smbd
```

Content of the wrapper:

```sh
#!/bin/sh
export LD_LIBRARY_PATH=/usr/local/samba4/lib:/usr/local/samba4/lib/private
exec /usr/local/samba4/sbin/smbd -s /etc/samba/smb.conf "$@"
```

### 7. Patch /etc/init.d/smb.sh

Back up the original, then add four sed injections after the `nas_configgen`
call in the `configure()` function:

```sh
cp /etc/init.d/smb.sh /etc/init.d/smb.sh.bak
```

Add these lines after `nas_configgen -c samba` succeeds:

```sh
/bin/sed -i '3i\\    max protocol = SMB3\\' /etc/samba/smb.conf
/bin/sed -i '4i\\    pid directory = /var/run\\' /etc/samba/smb.conf
/bin/sed -i 's|passdb backend = tdbsam:/etc/samba/smbpasswd.tdb|passdb backend = tdbsam:/var/lib/samba/private/smbpasswd.tdb|' /etc/samba/smb.conf
/bin/sed -i '/force.*mode/d' /etc/samba/smb.conf
```

**Why each line:**

| Injection | Reason |
|-----------|--------|
| `max protocol = SMB3` | Enable SMB2/SMB3; nas_configgen does not write this |
| `pid directory = /var/run` | smbd 4.1.23 compiled with `PIDDIR=/var/run/samba` which doesn't exist; redirect to `/var/run` |
| `passdb backend = …` | Samba 4 uses `/var/lib/samba/private/smbpasswd.tdb`; nas_configgen hardcodes the Samba 3 path |
| `force.*mode` deletion | `force create mode` / `force directory mode` are hardcoded in nas_configgen; Samba 4 rejects them in combination with other options |

### 8. Patch /etc/nsswitch.conf

Remove `winbind` from the NSS lookup chain.  winbindd is not running in a
standalone setup; leaving it in causes smbd to spin trying to contact the
missing winbind socket:

```sh
cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
sed -i 's/^\(passwd:.*\) winbind/\1/' /etc/nsswitch.conf
sed -i 's/^\(group:.*\) winbind/\1/'  /etc/nsswitch.conf
sed -i 's/^\(shadow:.*\) winbind/\1/' /etc/nsswitch.conf
```

### 9. Migrate passdb

If Samba 3 user accounts exist, copy the existing TDB:

```sh
cp /etc/samba/smbpasswd.tdb /var/lib/samba/private/smbpasswd.tdb
```

New users added via the WebUI will be written directly to the new path
(the WebUI calls `pdbedit`, which reads `passdb backend` from smb.conf).

### 10. Restart and verify

```sh
/etc/init.d/smb.sh restart
```

Verify SMB2/3 is active from the client host:

```sh
nmap -p 445 --script smb2-security-mode <NAS_IP>
# Expected: smb2-security-mode: 2.02
```

Mount with SMB3:

```sh
mount -t cifs -o vers=3.0,username=<user> //<NAS_IP>/<share> /mnt/test
```

## Recycle-bin (Papierkorb)

The recycle-bin VFS module is controlled by `/etc/melco/shareinfo`, field
index 13 (0-indexed, `<>`-separated).  Set it to `1` for shares that should
have a recycle bin, `0` to disable.  The `nas_configgen` binary writes the
corresponding `vfs objects = recycle` and `recycle:*` lines into `smb.conf`
when the field is `1`.

Files deleted via SMB land in `trashbox/` in the share root directory.

## Rollback

To revert to Samba 3:

```sh
cp /etc/init.d/smb.sh.bak /etc/init.d/smb.sh
cp /etc/nsswitch.conf.bak /etc/nsswitch.conf
cp /usr/local/samba4/sbin/smbd.original /usr/local/sbin/smbd  # if backed up
/etc/init.d/smb.sh restart
```
