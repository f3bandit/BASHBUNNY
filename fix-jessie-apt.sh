#!/bin/bash
# fix-jessie-apt.sh
# Repairs archived Jessie APT sources + sets time (EST)

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root."
  exit 1
fi

echo "[*] Setting timezone to EST (America/New_York)..."

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "America/New_York" > /etc/timezone

# Try to sync time (multiple fallbacks)
echo "[*] Attempting time synchronization..."

if command -v ntpdate >/dev/null 2>&1; then
  ntpdate -u pool.ntp.org || true
elif command -v ntpd >/dev/null 2>&1; then
  ntpd -q -p pool.ntp.org || true
elif busybox ntpd -h >/dev/null 2>&1; then
  busybox ntpd -q -p pool.ntp.org || true
else
  echo "[!] No NTP client available. Time may be incorrect."
fi

echo "[*] Current system time:"
date

echo "[*] Starting Jessie APT archive fix..."

SOURCES_FILE="/etc/apt/sources.list"
APT_CONF_FIX="/etc/apt/apt.conf.d/99no-check-valid"
BACKUP_DIR="/root/apt-fix-backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp -a "$file" "$BACKUP_DIR/$(basename "$file").$TIMESTAMP.bak"
    echo "[*] Backed up $file"
  fi
}

echo "[*] Backing up existing APT config..."
backup_file "$SOURCES_FILE"

for f in /etc/apt/apt.conf /etc/apt/apt.conf.d/*; do
  [ -e "$f" ] || continue
  backup_file "$f"
done

echo "[*] Writing archived Jessie sources..."
cat > "$SOURCES_FILE" <<'EOF'
deb http://archive.debian.org/debian jessie main contrib non-free
deb http://archive.debian.org/debian-security jessie/updates main
EOF

echo "[*] Writing archive compatibility config..."
cat > "$APT_CONF_FIX" <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF

echo "[*] Removing invalid APT::Default-Release \"jessie\" lines if present..."

for f in /etc/apt/apt.conf /etc/apt/apt.conf.d/*; do
  [ -e "$f" ] || continue
  if grep -q 'APT::Default-Release[[:space:]]*"jessie"' "$f" 2>/dev/null; then
    sed -i '/APT::Default-Release[[:space:]]*"jessie"[[:space:]]*;/d' "$f"
    echo "[*] Removed invalid Default-Release from $f"
  fi
done

echo "[*] Cleaning APT cache..."
apt-get clean

echo "[*] Running apt-get update..."
if apt-get update; then
  echo "[+] Jessie archive fix applied successfully."
else
  echo "[!] apt-get update failed."
  echo "    Check network connectivity and verify the archive repositories are reachable."
  exit 1
fi
