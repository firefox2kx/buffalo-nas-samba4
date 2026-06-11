# buffalo-nas-samba4

Cross-compiled Samba 4.1.23 for Buffalo LinkStation / TeraStation devices
running armv5te with glibc 2.5, enabling **SMB2 and SMB3** to replace the
factory SMBv1-only Samba 3.6.3.

## Motivation

Buffalo's factory firmware ships Samba 3.6.3 compiled without `WITH_SMB2`.
Modern clients (Windows 11, macOS 13+) deprecate or disable SMBv1, making
the NAS inaccessible or slow.  This project provides everything needed to
cross-compile Samba 4.1.23 and deploy it alongside the existing firmware
infrastructure — including the BuffaloNAS WebUI and daemonwatch.

## Tested hardware

| Model | CPU | Architecture | glibc |
|-------|-----|--------------|-------|
| LS-QVL01D (LinkStation Quad) | Marvell Feroceon 88FR131 | ARMv5TE | 2.5 |

Other Buffalo models with the same Marvell platform (LS-WVL, LS-XHL, etc.)
likely work with the same build.

## What this project provides

| Component | Description |
|-----------|-------------|
| `compat/` | glibc 2.5 compatibility shims (isoc99, resolv) |
| `patches/` | Source patches for Samba's waf build system |
| `wrapper/smbd` | Drop-in replacement for `/usr/local/sbin/smbd` |
| `nas/smb.sh.patch` | Adds SMB3 + Samba 4 config injections to smb.sh |
| `nas/nsswitch.conf.patch` | Removes winbind from NSS (prevents CPU spin) |
| `scripts/build.sh` | Automated cross-compilation |
| `scripts/deploy.sh` | Automated deployment over SSH |
| `docs/` | Build guide, deployment guide, NAS internals reference |

## Quick start

### Prerequisites

```sh
apt-get install gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
                qemu-user-static python3 pkg-config libgnutls28-dev sshpass
```

Download Samba 4.1.23:

```sh
wget https://download.samba.org/pub/samba/stable/samba-4.1.23.tar.gz
tar xzf samba-4.1.23.tar.gz
```

Prepare a sysroot from your NAS (see [docs/BUILD.md](docs/BUILD.md)):

```sh
rsync -a root@<NAS_IP>:/lib     ~/build/nas-sysroot/
rsync -a root@<NAS_IP>:/usr/lib ~/build/nas-sysroot/usr/
```

### Build

```sh
./scripts/build.sh ~/build/samba-src/samba-4.1.23 ~/build/nas-sysroot
```

### Deploy

```sh
./scripts/deploy.sh <NAS_IP> root ~/build/samba-src/samba-4.1.23
```

### Verify

```sh
nmap -p 445 --script smb2-security-mode <NAS_IP>
# smb2-security-mode: 2.02  ← SMB2/3 active
```

## Key technical challenges solved

**glibc 2.5 compatibility** — gcc ≥ 4.6 emits `__isoc99_sscanf` references
that don't exist in glibc 2.5.  The `compat/` library provides thin wrappers.

**Build-time host tools** — `asn1_compile` and `compile_et` must run on
the build host (x86_64), not be cross-compiled.  The patch to
`samba_optimisation.py` adds the `apply_hostcc` waf feature.

**_FILE_OFFSET_BITS** — Samba configure enables 64-bit file offsets, but
glibc 2.5 doesn't implement the full API.  A post-configure patch to
`config.h` disables this.

**Passdb path** — nas_configgen hardcodes the Samba 3 passdb path.  A sed
injection in `smb.sh` redirects it to the Samba 4 location.

**Module path** — smbd (without `waf install`) looks for VFS modules at
the build-tree path.  A symlink on the NAS redirects this to the installed
location at `/usr/local/samba4/modules/`.

See [docs/NAS-INTERNALS.md](docs/NAS-INTERNALS.md) for a full explanation
of the Buffalo firmware architecture.

## What continues to work after the upgrade

- All existing shares and user accounts
- Buffalo WebUI (share management, user management, disk status)
- daemonwatch (automatic restart on crash)
- Recycle-bin (Papierkorb) per share
- nmbd / NetBIOS name resolution

## Limitations

- SMBv1 is disabled (`max protocol = SMB3` in `[global]`).  Re-enable with
  `min protocol = NT1` if needed for legacy clients.
- Samba 4.1.23 is old by current standards but is the most recent version
  that can be built with a simple waf command against a glibc 2.5 sysroot.
  Later versions require Python 3 and have deeper waf integration.
- Active Directory (ADS) features are not built (`--without-ads`).
- No LDAP support (`--without-ldap`).

## License

MIT — see [LICENSE](LICENSE).

The Samba source code itself is GPL v3.
`compat/isoc99_compat.c` and `compat/resolv_compat.c` are original work
released under MIT.
