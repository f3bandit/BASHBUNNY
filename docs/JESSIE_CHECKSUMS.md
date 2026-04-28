# Jessie armhf Package Checksums

## How to Regenerate

Run this on the Bash Bunny after downloading all packages:

```bash
cd /root/bb_updates/debs
md5sum *.deb | sort > /root/udisk/loot/jessie_checksums.md5
sha256sum *.deb | sort > /root/udisk/loot/jessie_checksums.sha256
```

Or from WSL if you have the debs locally:

```bash
cd /path/to/debs
md5sum *.deb | sort > jessie_checksums.md5
sha256sum *.deb | sort > jessie_checksums.sha256
```

---

## Package Integrity Verification

The installer validates every `.deb` file using `dpkg-deb -I` before installation.
Any file that fails this check is deleted and re-downloaded.

To manually verify a specific package:

```bash
dpkg-deb -I /root/bb_updates/debs/packagename_version_armhf.deb
```

---

## Source Verification

All Jessie packages were sourced from:
```
https://archive.debian.org/debian/pool/main/
```

Package versions are pinned to their final Jessie security updates.
These are the same packages that would have been installed via:
```
deb http://archive.debian.org/debian jessie main
deb http://archive.debian.org/debian-security jessie/updates main
```

---

## Checksums File Location in Repo

After running the above commands on the BB, upload the generated files to:
```
jessie-armhf-debs/checksums.md5
jessie-armhf-debs/checksums.sha256
```

The installer will use these for verification in a future version.
