# BASHBUNNY — Bash Bunny Mark II Package Repository

A self-contained offline package repository and installer for the Hak5 Bash Bunny Mark II.
Designed to extend the stock Debian Jessie firmware with security tools, a build toolchain,
Python 3, and custom Bunny-specific tools — without requiring access to archive.debian.org.

---

## What This Repo Does

The stock Bash Bunny Mark II ships with **Debian 8 Jessie** (EOL June 2018).
Standard `apt-get update` fails because Jessie mirrors are gone.

This repo provides:

1. A cached set of Jessie armhf `.deb` packages hosted directly on GitHub
2. A Python 3.4 stack for the Jessie environment
3. Custom Bunny tool packages (gohttp, impacket, metasploit, responder)
4. An all-in-one installer script that downloads, validates, and installs everything
5. A test script to verify all tools are working

All packages are downloaded over HTTPS from this GitHub repo. No external mirrors needed.

---

## Repository Structure

```
BASHBUNNY/
├── jessie-armhf-debs/          ← Debian Jessie armhf .deb cache (271 packages)
│   ├── manifest.txt            ← List of all .deb filenames
│   ├── checksums.md5           ← MD5 checksums for all .deb files
│   └── *.deb                   ← Package files
│
├── python3/                    ← Python 3.4 stack for Jessie armhf (25 packages)
│   ├── manifest.txt
│   └── *.deb
│
├── tools/                      ← Custom Bunny tool packages (5 files)
│   ├── manifest.txt
│   ├── gohttp-bunny.deb
│   ├── impacket-bunny.deb
│   ├── metasploit-bunny.deb
│   ├── responder-bunny.deb
│   └── macchanger-1.7.0.tar.gz ← Built from source during install
│
├── scripts/                    ← Installer and test scripts
│   ├── install_bb_aio.sh   ← Main installer (current version)
│   └── test_wrappers.sh           ← Tool verification script
│
└── docs/
    ├── PACKAGE_LIST.md         ← Full list of all packages with versions
    ├── JESSIE_CHECKSUMS.md     ← MD5/SHA256 checksums for Jessie debs
    └── KNOWN_CONFLICTS.md      ← Known package conflicts with stock BB firmware
```

---

## Quick Start

### Prerequisites
- Bash Bunny Mark II on stock firmware 1.7
- Internet access via RNDIS/ECM USB ethernet (host PC sharing connection)
- SSH access to the BB (`ssh root@172.16.64.1`)

### Install

```bash
# SSH into the Bash Bunny
ssh root@172.16.64.1

# Mount the udisk if not already mounted
udisk mount

# Copy installer to BB (from Windows host)
# Copy scripts/install_bb_aio.sh to BB udisk root/udisk/scripts/

# Run installer
cd /root/udisk/scripts
./install_bb_aio.sh

# Reload shell after completion
exec /bin/bash -l
```

### Verify Installation

```bash
cd /root/udisk/scripts
./test_wrappers.sh
```

---

## What Gets Installed

### Build Toolchain
- gcc 4.9.2, g++ 4.9.2, cpp 4.9.2
- make, autoconf, automake, libtool
- binutils, pkg-config, patch, m4
- build-essential, fakeroot, dpkg-dev

### Python 3
- Python 3.4.2 + pip
- python3-requests, python3-setuptools, python3-pip
- Full dev stack: python3-dev, python3.4-dev, libpython3.4-dev

### Networking & Security Tools
- nmap, tcpdump, netcat-traditional, socat
- curl, wget, dnsutils, traceroute
- aircrack-ng, iw, wireless-tools
- whois, telnet, iputils-ping

### Debug & Analysis Tools
- strace, ltrace, lsof, gdb
- htop, procps, psmisc
- sqlite3, p7zip-full

### Custom Bunny Tools
- **gohttp** — lightweight HTTP server for file serving payloads
- **impacket** — Python network protocol library (SMB, NTLM, etc.)
- **metasploit-framework** — penetration testing framework
- **responder** — LLMNR/NBT-NS/MDNS poisoner
- **macchanger 1.7.0** — MAC address changer (built from source)

### Shell Environment
- Color PS1 prompt (`user@bb:dir# `)
- Aliases: `ll`, `la`, `l`, `ls --color`, `grep --color`
- `applytheme` — reapply color profile
- `reloadtheme` — reload login shell
- `colortest` — test terminal color support
- `restoreprofile` — restore original `.profile`

---

## Package Sources

### Jessie Packages
All Jessie armhf packages were sourced from:
```
https://archive.debian.org/debian/pool/main/
```
Archived at the time of collection. Packages are pinned to their exact Jessie versions
and will not be updated by apt after install (local repo only, no live mirror).

### Python 3 Packages
Python 3.4 stack sourced from Jessie archive. Python 3.4 is the latest Python 3
version available for Debian Jessie armhf.

### Custom Tools
- **gohttp**: Custom Bunny-specific build
- **impacket**: Packaged from impacket source for armhf
- **metasploit**: Packaged for BB armhf environment
- **responder**: Packaged from Responder project source
- **macchanger**: Source tarball from https://github.com/alobbs/macchanger (v1.7.0)

---

## Known Issues & Conflicts

### libsigc++-2.0-0c2a
The stock BB firmware ships with `libstdc++6 6.3.0-18+deb9u1` (Stretch-era),
which conflicts with the Jessie version of `libsigc++-2.0-0c2a 2.4.0-1`.
The installer automatically excludes this package. No tools in this repo require it.

### Clock / TLS
The BB clock defaults to 2021. The installer syncs time via HTTP header before
any HTTPS downloads so TLS certificate validation works.

### ntpdate
`ntpdate` is not present on stock BB firmware. The installer uses an HTTP Date
header fallback for clock sync.

---

## Hardware Requirements

- **Device**: Bash Bunny Mark II only (not Mark I)
- **Firmware**: Stock 1.7 (ch_fw_1.7_332)
- **SoC**: Allwinner A33 (sun8i), quad-core ARM Cortex-A7
- **Kernel**: Linux 3.4.39
- **Storage**: ~500MB free on nandd (rootfs partition)
- **RAM**: 512MB

---

## License

Scripts and documentation in this repo are provided as-is for educational and
authorized security research purposes only. Tool packages retain their original
licenses. See individual tool documentation for details.
