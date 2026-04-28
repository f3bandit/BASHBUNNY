# Known Package Conflicts — Bash Bunny Stock Firmware

## Overview

The stock Bash Bunny Mark II firmware (1.7) ships with a mixed Jessie/Stretch
userspace. Some packages installed by Hak5 are from Debian 9 Stretch despite the
base OS being Debian 8 Jessie. This causes conflicts when attempting to install
Jessie versions of those packages.

---

## Confirmed Conflicts

### libsigc++-2.0-0c2a

**Stock package:** `libstdc++6 6.3.0-18+deb9u1` (Stretch)
**Conflicting package:** `libsigc++-2.0-0c2a 2.4.0-1` (Jessie)

**Error:**
```
libstdc++6:armhf (6.3.0-18+deb9u1) breaks libsigc++-2.0-0c2a (<= 2.4.1-1+b1)
```

**Resolution:** `libsigc++-2.0-0c2a` is listed in `EXCLUDED_PKGS` in the installer
and will never be attempted. No tools in this repo depend on it.

---

## Stock Firmware Mixed Package Versions

The following Stretch-era packages are present on stock BB 1.7 firmware:

| Package | Version | Origin |
|---------|---------|--------|
| libstdc++6 | 6.3.0-18+deb9u1 | Debian 9 Stretch |

These were likely installed by Hak5 during firmware build to support specific
tools. They cannot be downgraded without breaking those tools.

---

## Adding New Exclusions

To exclude additional packages from installation, add them to the `EXCLUDED_PKGS`
variable at the top of `install_bb_aio_v27_fixed.sh`:

```bash
EXCLUDED_PKGS="libsigc++-2.0-0c2a another-conflicting-pkg"
```

Space-separated, no quotes around individual names.
