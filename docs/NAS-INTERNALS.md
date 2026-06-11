# Buffalo NAS System Internals

Reference for understanding how the Buffalo LinkStation firmware manages
its Samba configuration.  Useful when diagnosing issues or extending the
setup beyond what this project covers.

## Hardware (LS-QVL01D and similar)

| Component | Value |
|-----------|-------|
| CPU | Marvell Feroceon 88FR131, ARMv5TE, ~800 MHz |
| RAM | 256 MB DDR2 |
| Kernel | 3.3.4-88f6281 |
| libc | glibc 2.5 (`/lib/libc-2.5.so`) |
| Python | 2.6.2 |
| Original Samba | 3.6.3-31a.osstech, compiled *without* `WITH_SMB2` |

## Configuration architecture

```
WebUI (Perl/CGI via SpeedyCGI)
        │
        ▼
/etc/melco/ parameter files
   shareinfo, info, workgroup, …
        │
        ▼
nas_configgen -c samba      (closed-source ARM binary)
        │
        ▼
/etc/samba/smb.conf          (regenerated on every start/reload)
        │
        ▼  (+ our sed injections in smb.sh)
smbd
```

`smb.conf` is **not persistent** — it is regenerated from `/etc/melco/`
every time smb.sh start/reload is called.  Never edit it directly.

## nas_configgen

`/usr/local/sbin/nas_configgen -c samba` reads the `/etc/melco/` files and
writes `/etc/samba/smb.conf`.  It is a statically-linked ARM binary with no
external templates.

**Hardcoded values that can only be overridden via sed injection:**

| smb.conf key | Hardcoded value | Override |
|---|---|---|
| `passdb backend` | `tdbsam:/etc/samba/smbpasswd.tdb` | sed replacement in smb.sh |
| `force create mode` | `0666` | sed deletion in smb.sh |
| `force directory mode` | `0777` | sed deletion in smb.sh |
| `max protocol` | (not written) | sed insert at line 3 |
| `pid directory` | (not written) | sed insert at line 4 |

## /etc/melco/shareinfo format

One line per share, fields separated by `<>`, terminated by `;`.

```
<name><>array<>comment<>valid-users<>…<>f8<>f9<>f10<>f11<>f12<>f13<>f14<>…;
```

**Selected field index (0-based):**

| Index | Meaning |
|-------|---------|
| 0 | Share name |
| 1 | Array (`array1` or `array2`) |
| 2 | Comment / description |
| 3 | Valid users (comma-separated) |
| 7 | Read-only flag |
| 9 | Browseable flag |
| 10 | Guest-ok flag |
| 13 | Recycle-bin enabled (1=yes, 0=no) → `vfs objects = recycle` |

When field 13 is `1`, nas_configgen appends to the share section:

```ini
vfs objects = recycle
recycle:repository = trashbox/%U
recycle:keeptree = yes
recycle:versions = yes
recycle:touch = yes
```

## Service management

| Component | Role |
|-----------|------|
| `/etc/init.d/smb.sh` | Start/stop/reload smbd + nmbd |
| `daemonwatch` | Watchdog: monitors `/var/run/smbd.pid`, restarts via `smb.sh start` |
| `global_init_system` | Main init coordinator, calls smb.sh on boot |

`daemonwatch` re-runs `smb.sh start`, which re-runs `configure()` and all
sed injections — the patches are applied fresh on every restart.

## WebUI architecture

The web interface runs via Apache + SpeedyCGI (persistent Perl processes).
User management calls `pdbedit` directly:

```perl
# BufUserCommand.pm (simplified)
readpipe("echo -e '$pass\n$pass\n' | /usr/local/bin/pdbedit -t -a -u '$name'");
```

`pdbedit` reads `passdb backend` from `/etc/samba/smb.conf` and writes
the user directly to `/var/lib/samba/private/smbpasswd.tdb` (after our
smb.sh injection fixes the path).  No manual copy step is needed when
creating users via the WebUI.

## Plugin system (exec_trigger)

`/www/cgi-bin/module/BufModulesInfo.pm` implements a simple plugin
mechanism:  modules installed under `/modules/<name>/` can provide a
`www/cgi-bin/trigger.pl` that the WebUI executes on certain events.
The `/modules/` directory is empty on stock firmware.
