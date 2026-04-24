#!/bin/bash
set +e

echo "[LOCKED] Bash Bunny Python3 + pip runtime installer"

BASE_URL="https://raw.githubusercontent.com/f3bandit/BASHBUNNY/main/python3"
WORKDIR="/root/bb_updates/python3"

mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1
rm -f ./*.deb manifest.txt manifest_clean.txt

fetch() {
    FILE="$1"
    URL="$BASE_URL/$FILE"

    for i in 1 2 3; do
        echo "[DL] $FILE attempt $i"
        wget -q -O "$FILE" "$URL" && break
        sleep 1
    done

    if [ ! -f "$FILE" ]; then
        echo "[FATAL] missing $FILE"
        exit 1
    fi

    SIZE=$(wc -c < "$FILE")
    if [ "$SIZE" -lt 1000 ]; then
        echo "[FATAL] $FILE too small: $SIZE bytes"
        rm -f "$FILE"
        exit 1
    fi

    dpkg-deb -I "$FILE" >/dev/null 2>&1 || {
        echo "[FATAL] invalid deb: $FILE"
        rm -f "$FILE"
        exit 1
    }
}

cat > manifest_clean.txt <<'MANIFEST'
dh-python_1.20141111-2_all.deb
libexpat1-dev_2.1.0-6+deb8u4_armhf.deb
libmpdec2_2.4.2-1_armhf.deb
libpython3.4_3.4.2-1_armhf.deb
libpython3.4-minimal_3.4.2-1_armhf.deb
libpython3.4-stdlib_3.4.2-1_armhf.deb
libpython3-stdlib_3.4.2-2_armhf.deb
python3.4_3.4.2-1_armhf.deb
python3.4-minimal_3.4.2-1_armhf.deb
python3_3.4.2-2_armhf.deb
python3-chardet_2.3.0-1_all.deb
python3-colorama_0.3.2-1_all.deb
python3-distlib_0.1.9-1_all.deb
python3-html5lib_0.999-3_all.deb
python3-minimal_3.4.2-2_armhf.deb
python3-pip_1.5.6-5_all.deb
python3-pkg-resources_5.5.1-1_all.deb
python3-requests_2.4.3-6_all.deb
python3-setuptools_5.5.1-1_all.deb
python3-six_1.8.0-1_all.deb
python3-urllib3_1.9.1-3_all.deb
MANIFEST

while read f; do
    [ -z "$f" ] && continue
    fetch "$f"
done < manifest_clean.txt

echo "[OK] all runtime packages downloaded and validated"

echo "[*] removing broken/unneeded dev meta package if present"
dpkg --remove --force-remove-reinstreq python3-dev >/dev/null 2>&1 || true

echo "[*] installing base libs"
dpkg -i libmpdec2_*.deb || true
dpkg -i libexpat1-dev_*.deb || true

echo "[*] installing Python core"
dpkg -i libpython3.4-minimal_*.deb || true
dpkg -i python3.4-minimal_*.deb || true
dpkg -i libpython3.4-stdlib_*.deb || true
dpkg -i libpython3.4_*.deb || true
dpkg -i python3.4_*.deb || true
dpkg -i libpython3-stdlib_*.deb || true
dpkg -i python3-minimal_*.deb || true

dpkg --configure -a || true

echo "[*] installing Python meta"
dpkg -i dh-python_*.deb || true
dpkg -i python3_*.deb || true

dpkg --configure -a || true

echo "[*] installing pip dependency stack"
dpkg -i python3-pkg-resources_*.deb || true
dpkg -i python3-six_*.deb || true
dpkg -i python3-chardet_*.deb || true
dpkg -i python3-urllib3_*.deb || true
dpkg -i python3-requests_*.deb || true
dpkg -i python3-colorama_*.deb || true
dpkg -i python3-distlib_*.deb || true
dpkg -i python3-html5lib_*.deb || true

dpkg --configure -a || true

echo "[*] installing setuptools + pip"
dpkg -i python3-setuptools_*.deb || true
dpkg -i python3-pip_*.deb || true

dpkg --configure -a || true

echo "[VERIFY]"
cd /root
python3 --version || true
pip3 --version || true

echo "[DPKG CHECK]"
dpkg -C || true

echo "[DONE] Python3 runtime install complete"
