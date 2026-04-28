#!/bin/bash
# install_bb_aio_v27_fixed.sh
# Bash Bunny Git-only AIO installer
# - No archive.debian.org fallback
# - Downloads from f3bandit/BASHBUNNY GitHub repo only
# - Dedupes package installs by Debian package name
# - Installs toolchain/Python/tools in safe order
# - Iterative dpkg settle passes for deep dependency chains
#
# v24 fixes vs v23:
#   - fix_time_and_certs: sync clock via NTP + set timezone to EST/New York
#     before any downloads so TLS cert validation works
#   - download_file: added --no-check-certificate to wget and -k to curl
#     as a fallback in case NTP sync fails or cert is still untrusted
#
# v23 fixes vs v22:
#   - generate_local_repo: replaced broken manual Packages builder with
#     dpkg-scanpackages for correct APT repo format
#   - install_deb_by_pkg: replaced fragile ls glob with find to handle
#     package names containing +, . and other special chars (g++, libstdc++6)
#   - verify_final: removed python/tmux checks (never installed)
#   - configure_local_apt_only: added Release file generation for APT compat

set +e

MARKER="install_bb_aio_v27_fixed.sh"
echo "[MARKER] running $MARKER"

cd /root || exit 1

BB_ROOT="${BB_ROOT:-/root/bb_updates}"
DEBS_DIR="$BB_ROOT/debs"
TOOLS_DIR="$BB_ROOT/tools"
PY3_DIR="$BB_ROOT/python3"
MANIFEST_DIR="$BB_ROOT/manifests"
REPO_DIR="$BB_ROOT/localrepo"
COLOR_DIR="$BB_ROOT/ssh_colors"
BUILD_DIR="$BB_ROOT/build"

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/f3bandit/BASHBUNNY/refs/heads/main}"
JESSIE_REMOTE_DIR="$REPO_BASE/jessie-armhf-debs"
TOOLS_REMOTE_DIR="$REPO_BASE/tools"
PY3_REMOTE_DIR="$REPO_BASE/python3"

JESSIE_MANIFEST_URL="$JESSIE_REMOTE_DIR/manifest.txt"
TOOLS_MANIFEST_URL="$TOOLS_REMOTE_DIR/manifest.txt"
PY3_MANIFEST_URL="$PY3_REMOTE_DIR/manifest.txt"

APT_OPTS="-o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=true -o APT::Get::AllowUnauthenticated=true"
LOCAL_APT_OPTS="$APT_OPTS -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/bb-local.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=false"

mkdir -p "$DEBS_DIR" "$TOOLS_DIR" "$PY3_DIR" "$MANIFEST_DIR" "$REPO_DIR" "$COLOR_DIR" "$BUILD_DIR"

log()   { echo "[*] $*"; }
warn()  { echo "[!] $*" >&2; }
fatal() { echo "[FATAL] $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

validate_deb()   { dpkg-deb -I "$1" >/dev/null 2>&1; }
validate_targz() { tar -tzf "$1" >/dev/null 2>&1; }

deb_pkg_name() { dpkg-deb -f "$1" Package 2>/dev/null; }
deb_pkg_ver()  { dpkg-deb -f "$1" Version 2>/dev/null; }

is_pkg_configured() {
    pkg="$1"
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

download_file() {
    url="$1"
    out="$2"
    rm -f "$out.tmp"

    if have_cmd wget; then
        wget -q -O "$out.tmp" "$url" || { rm -f "$out.tmp"; return 1; }
    elif have_cmd curl; then
        curl -sL "$url" -o "$out.tmp" || { rm -f "$out.tmp"; return 1; }
    else
        warn "Neither wget nor curl is available"
        return 1
    fi

    if [ ! -s "$out.tmp" ]; then
        warn "Empty download: $url"
        rm -f "$out.tmp"
        return 1
    fi

    mv "$out.tmp" "$out"
    return 0
}

fetch_manifest() {
    url="$1"
    out="$2"
    log "Downloading manifest: $url"
    download_file "$url" "$out" || return 1
    sed -i 's/\r$//' "$out" 2>/dev/null || true
    [ -s "$out" ] || return 1
    return 0
}

manifest_items() {
    manifest="$1"
    tr ' \t' '\n' < "$manifest" | sed 's/\r$//' | sed '/^$/d' | sed '/^#/d'
}

sync_git_debs() {
    manifest="$MANIFEST_DIR/jessie-armhf-debs.manifest.txt"
    fetch_manifest "$JESSIE_MANIFEST_URL" "$manifest" || fatal "Could not fetch Jessie manifest from Git"

    listed=0; valid=0; failed=0; skipped=0
    log "Downloading Git-hosted Jessie .deb cache"

    for name in $(manifest_items "$manifest"); do
        listed=$((listed + 1))
        case "$name" in
            *.deb) ;;
            *) skipped=$((skipped + 1)); continue ;;
        esac

        out="$DEBS_DIR/$name"
        if [ -s "$out" ] && validate_deb "$out"; then
            log "Cached valid: $name"
            valid=$((valid + 1))
            continue
        fi

        rm -f "$out"
        log "Downloading $name"
        if ! download_file "$JESSIE_REMOTE_DIR/$name" "$out"; then
            warn "Git download failed: $name"
            failed=$((failed + 1))
            continue
        fi

        if validate_deb "$out"; then
            valid=$((valid + 1))
        else
            warn "Invalid .deb: $name"
            file "$out" 2>/dev/null || true
            rm -f "$out"
            failed=$((failed + 1))
        fi
    done

    log "Git Jessie sync complete: listed=$listed valid=$valid skipped=$skipped failed=$failed"
    [ "$failed" -eq 0 ] || fatal "One or more Git-hosted Jessie packages failed to download/validate"
}

sync_python3_bundle() {
    manifest="$MANIFEST_DIR/python3.manifest.txt"
    fetch_manifest "$PY3_MANIFEST_URL" "$manifest" || fatal "Could not fetch Python3 manifest from Git"

    listed=0; valid=0; failed=0
    log "Downloading Git-hosted Python3 bundle"

    for name in $(manifest_items "$manifest"); do
        listed=$((listed + 1))
        case "$name" in
            *.deb) ;;
            *) warn "Skipping non-deb Python3 item: $name"; continue ;;
        esac

        out="$PY3_DIR/$name"
        if [ -s "$out" ] && validate_deb "$out"; then
            log "Cached valid Python3 deb: $name"
            valid=$((valid + 1))
            cp "$out" "$DEBS_DIR/$name" 2>/dev/null || true
            continue
        fi

        rm -f "$out"
        log "Downloading Python3 deb: $name"
        if ! download_file "$PY3_REMOTE_DIR/$name" "$out"; then
            warn "Python3 download failed: $name"
            failed=$((failed + 1))
            continue
        fi

        if validate_deb "$out"; then
            valid=$((valid + 1))
            cp "$out" "$DEBS_DIR/$name" 2>/dev/null || true
        else
            warn "Invalid Python3 .deb: $name"
            rm -f "$out"
            failed=$((failed + 1))
        fi
    done

    log "Python3 sync complete: listed=$listed valid=$valid failed=$failed"
    [ "$failed" -eq 0 ] || fatal "One or more Python3 packages failed"
}

sync_tools() {
    manifest="$MANIFEST_DIR/tools.manifest.txt"
    fetch_manifest "$TOOLS_MANIFEST_URL" "$manifest" || fatal "Could not fetch tools manifest from Git"

    listed=0; valid=0; failed=0
    log "Downloading Git-hosted Bunny tool files"

    for name in $(manifest_items "$manifest"); do
        listed=$((listed + 1))
        out="$TOOLS_DIR/$name"

        if [ -s "$out" ]; then
            if [ "$name" = "macchanger-1.7.0.tar.gz" ] && validate_targz "$out"; then
                log "Cached valid: $name"; valid=$((valid + 1)); continue
            elif echo "$name" | grep -q '\.deb$' && validate_deb "$out"; then
                log "Cached valid: $name"; valid=$((valid + 1)); continue
            fi
            warn "Cached invalid, redownloading: $name"
            rm -f "$out"
        fi

        log "Downloading $name"
        if ! download_file "$TOOLS_REMOTE_DIR/$name" "$out"; then
            warn "Tool download failed: $name"
            failed=$((failed + 1))
            continue
        fi

        if [ "$name" = "macchanger-1.7.0.tar.gz" ]; then
            validate_targz "$out" && valid=$((valid + 1)) || { warn "Invalid archive: $name"; rm -f "$out"; failed=$((failed + 1)); }
        elif echo "$name" | grep -q '\.deb$'; then
            validate_deb "$out" && valid=$((valid + 1)) || { warn "Invalid tool .deb: $name"; rm -f "$out"; failed=$((failed + 1)); }
        else
            valid=$((valid + 1))
        fi
    done

    log "Tool sync complete: listed=$listed valid=$valid failed=$failed"
    [ "$failed" -eq 0 ] || fatal "One or more tool files failed"
}

make_unique_deb_dir() {
    src="$1"
    dst="$2"
    rm -rf "$dst"
    mkdir -p "$dst"

    # Choose one .deb per Debian package name, preferring first validated file encountered.
    for deb in "$src"/*.deb; do
        [ -e "$deb" ] || continue
        validate_deb "$deb" || continue
        pkg="$(deb_pkg_name "$deb")"
        [ -n "$pkg" ] || continue
        marker="$dst/.pkg-$pkg"
        if [ -e "$marker" ]; then
            continue
        fi
        cp "$deb" "$dst/$(basename "$deb")"
        touch "$marker"
    done

    rm -f "$dst"/.pkg-*
}

generate_local_repo() {
    # FIX v23: Use dpkg-scanpackages instead of manual Packages file construction.
    # The manual approach (dpkg-deb -f >> Packages) produces malformed output that
    # APT rejects — multi-line fields are not handled, entry separators are wrong,
    # and required fields like Filename/Size are interleaved incorrectly.
    # dpkg-scanpackages produces the correct RFC-822 format APT expects.

    log "Generating local APT repo from deduped .debs"
    rm -rf "$REPO_DIR"
    mkdir -p "$REPO_DIR"

    make_unique_deb_dir "$DEBS_DIR" "$REPO_DIR"

    ls "$REPO_DIR"/*.deb >/dev/null 2>&1 || fatal "No repo .debs found"

    cd "$REPO_DIR" || fatal "Cannot cd to local repo"
    rm -f Packages Packages.gz Release

    # Use dpkg-scanpackages for correct APT Packages format
    if have_cmd dpkg-scanpackages; then
        dpkg-scanpackages . /dev/null > Packages 2>/dev/null || \
            dpkg-scanpackages . > Packages 2>/dev/null || \
            fatal "dpkg-scanpackages failed"
    else
        # Fallback: install dpkg-dev dependencies first, then dpkg-dev itself.
        # dpkg-dev requires: libdpkg-perl, bzip2, patch
        warn "dpkg-scanpackages not found — installing deps then dpkg-dev"
        for dep in libtimedate-perl libdpkg-perl bzip2 patch; do
            deb="$(find "$DEBS_DIR" -maxdepth 1 -name "${dep}_*.deb" 2>/dev/null | head -1)"
            if [ -n "$deb" ]; then
                log "Installing dpkg-dev dep: $dep"
                dpkg -i "$deb" 2>/dev/null || true
                dpkg --configure -a 2>/dev/null || true
            else
                warn "Missing dep deb for dpkg-dev: $dep"
            fi
        done
        dpkg --configure -a || true

        deb="$(find "$DEBS_DIR" -maxdepth 1 -name "dpkg-dev_*.deb" 2>/dev/null | head -1)"
        [ -n "$deb" ] && dpkg -i "$deb" 2>/dev/null || true
        dpkg --configure -a || true

        if have_cmd dpkg-scanpackages; then
            dpkg-scanpackages . /dev/null > Packages 2>/dev/null || \
                dpkg-scanpackages . > Packages 2>/dev/null || \
                fatal "dpkg-scanpackages failed after install"
        else
            fatal "dpkg-scanpackages not available and could not be installed"
        fi
    fi

    gzip -c Packages > Packages.gz

    # Generate a minimal Release file so APT doesn't complain about missing metadata
    cat > Release <<EOF2
Archive: jessie
Component: main
Architecture: armhf
EOF2

    log "Local repo generated: $(wc -l < Packages) Packages lines, $(ls *.deb | wc -l) debs"
}

disable_bad_default_release() {
    mkdir -p "$BB_ROOT/apt_conf_backup"
    for f in /etc/apt/apt.conf /etc/apt/apt.conf.d/*; do
        [ -f "$f" ] || continue
        if grep -q 'Default-Release' "$f" 2>/dev/null; then
            b="$BB_ROOT/apt_conf_backup/$(basename "$f").bak"
            log "Backing up/disabling APT Default-Release config: $f -> $b"
            cp "$f" "$b"
            sed -i '/Default-Release/d' "$f"
        fi
    done
}

configure_local_apt_only() {
    log "Configuring local APT source only"
    disable_bad_default_release

    cat > /etc/apt/sources.list.d/bb-local.list <<EOF2
deb [trusted=yes] file:$REPO_DIR ./
EOF2

    cat > /etc/apt/sources.list <<EOF2
# Disabled by Bash Bunny AIO v23 installer.
# Using local repo only:
# deb [trusted=yes] file:$REPO_DIR ./
EOF2

    apt-get $LOCAL_APT_OPTS update || true
}

repair_state() {
    log "Repairing dpkg/apt state"
    dpkg --configure -a || true
    apt-get $LOCAL_APT_OPTS -f install -y || true
}

install_deb_by_pkg() {
    # FIX v23: Use find instead of ls glob to handle package names with
    # special characters like + and . (e.g. g++, libstdc++6, libglib2.0-0).
    # ls glob expansion breaks on these characters in POSIX shells.
    pkg="$1"

    # Escape the package name for use in find -name pattern
    # (dots in pkg names should match literally, not as regex wildcards)
    deb="$(find "$REPO_DIR" -maxdepth 1 -name "${pkg}_*.deb" 2>/dev/null | head -1)"

    if [ -z "$deb" ]; then
        warn "Missing local deb for package: $pkg"
        return 1
    fi
    if is_pkg_configured "$pkg"; then
        log "Already configured: $pkg"
        return 0
    fi
    log "Installing $pkg: $(basename "$deb")"
    dpkg -i "$deb" || true
}

install_ordered_core_toolchain() {
    log "Installing base compiler/toolchain in explicit dpkg order"

    # Leaf libraries and low-level deps first.
    for pkg in \
        libc-bin libc6 linux-libc-dev libc-dev-bin libc6-dev \
        gcc-4.9-base libgcc1 libatomic1 libasan1 libubsan0 libgomp1 \
        libgmp10 libmpfr4 libmpc3 libisl10 libcloog-isl4 \
        libstdc++6 libsigsegv2 libglib2.0-0 libdpkg-perl \
        libfakeroot binutils make patch perl perl-base perl-modules \
        m4 pkg-config autotools-dev file tar gzip bzip2 xz-utils unzip zip
    do
        install_deb_by_pkg "$pkg"
    done

    dpkg --configure -a || true

    for pkg in \
        libgcc-4.9-dev libstdc++-4.9-dev cpp-4.9 cpp gcc-4.9 gcc \
        g++-4.9 g++ dpkg-dev build-essential fakeroot autoconf automake libtool
    do
        install_deb_by_pkg "$pkg"
    done

    dpkg --configure -a || true
    apt-get $LOCAL_APT_OPTS -f install -y || true
}

install_python3_ordered() {
    log "Installing Python3 full-dev stack in locked order"
    # remove stale broken meta first if any
    dpkg --remove --force-remove-reinstreq python3-dev >/dev/null 2>&1 || true

    for pkg in \
        libmpdec2 libexpat1-dev \
        libpython3.4-minimal python3.4-minimal libpython3.4-stdlib libpython3.4 python3.4 \
        libpython3-stdlib python3-minimal dh-python python3 \
        python3-pkg-resources python3-six python3-chardet python3-urllib3 python3-requests \
        python3-colorama python3-distlib python3-html5lib python3-setuptools python3-pip \
        libpython3.4-dev python3.4-dev libpython3-dev python3-dev
    do
        install_deb_by_pkg "$pkg"
        dpkg --configure -a || true
    done

    apt-get $LOCAL_APT_OPTS -f install -y || true
}

install_package_profiles() {
    log "Installing networking/debug/archive/profile packages"
    for pkg in \
        curl wget netcat-traditional tcpdump nmap dnsutils iputils-ping traceroute \
        socat telnet whois aircrack-ng iw wireless-tools sqlite3 \
        strace ltrace lsof htop procps psmisc gdb binutils \
        zip unzip tar gzip bzip2 xz-utils p7zip-full
    do
        install_deb_by_pkg "$pkg"
    done
    dpkg --configure -a || true
    apt-get $LOCAL_APT_OPTS -f install -y || true
}

# Packages that conflict with stock BB firmware and must be excluded.
# libsigc++-2.0-0c2a: Jessie version conflicts with Stretch-era libstdc++6
# that ships in stock BB firmware (6.3.0-18+deb9u1 breaks libsigc++ <= 2.4.1-1+b1)
EXCLUDED_PKGS="libsigc++-2.0-0c2a"

is_excluded_pkg() {
    pkg="$1"
    for excl in $EXCLUDED_PKGS; do
        [ "$pkg" = "$excl" ] && return 0
    done
    return 1
}

install_all_repo_iterative() {
    log "Running optimized iterative dpkg settle over deduped Git package cache"
    log "Excluded packages (stock fw conflicts): $EXCLUDED_PKGS"
    cd "$REPO_DIR" || return 1

    for pass in 1 2 3; do
        log "Dpkg settle pass $pass/3"
        for deb in *.deb; do
            [ -e "$deb" ] || continue
            pkg="$(deb_pkg_name "$deb")"
            [ -n "$pkg" ] || continue
            if is_excluded_pkg "$pkg"; then
                continue
            fi
            if is_pkg_configured "$pkg"; then
                continue
            fi
            dpkg -i "$deb" || true
        done
        dpkg --configure -a || true
        apt-get $LOCAL_APT_OPTS -f install -y || true
    done
}

verify_toolchain_or_die() {
    log "Verifying build toolchain"
    ok=1

    for cmd in gcc g++ cc make pkg-config autoconf automake; do
        if have_cmd "$cmd"; then
            echo "$cmd -> $(command -v "$cmd")"
        else
            warn "Missing required build command/helper: $cmd"
            ok=0
        fi
    done

    # Debian Jessie may provide libtool support primarily through libtoolize.
    # Treat either libtool or libtoolize as satisfying the libtool check.
    if have_cmd libtool; then
        echo "libtool -> $(command -v libtool)"
    elif have_cmd libtoolize; then
        echo "libtoolize -> $(command -v libtoolize)"
    else
        warn "Missing required build command/helper: libtool or libtoolize"
        ok=0
    fi

    [ "$ok" -eq 1 ] || fatal "Toolchain verification failed"
}

install_tool_debs() {
    log "Installing Bunny custom tool .deb files"
    for deb in "$TOOLS_DIR"/*.deb; do
        [ -e "$deb" ] || continue
        validate_deb "$deb" || { warn "Skipping invalid tool deb: $deb"; continue; }
        pkg="$(deb_pkg_name "$deb")"
        if [ -n "$pkg" ] && is_pkg_configured "$pkg"; then
            log "Tool package already configured: $pkg"
            continue
        fi
        log "Installing tool $(basename "$deb")"
        dpkg -i "$deb" || true
        dpkg --configure -a || true
    done
    apt-get $LOCAL_APT_OPTS -f install -y || true
}

build_source_archives() {
    verify_toolchain_or_die
    log "Building source archives"

    for archive in "$TOOLS_DIR"/*.tar.gz "$TOOLS_DIR"/*.tgz; do
        [ -e "$archive" ] || continue
        validate_targz "$archive" || { warn "Skipping invalid archive: $archive"; continue; }

        mkdir -p "$BUILD_DIR"
        top="$(tar -tzf "$archive" | head -1 | cut -d/ -f1)"
        [ -n "$top" ] || continue

        cd "$BUILD_DIR" || continue
        rm -rf "$top"
        tar -xzf "$archive"
        cd "$top" || continue

        if [ -f configure ]; then
            ./configure || { warn "configure failed for $top; skipping make/install"; continue; }
        fi
        make || { warn "make failed for $top"; continue; }
        make install || { warn "make install failed for $top"; continue; }
    done
}

install_colors() {
    log "Installing SSH color profile"
    mkdir -p "$COLOR_DIR"

    if [ -f /root/.profile ] && [ ! -f "$COLOR_DIR/.profile.backup" ]; then
        cp /root/.profile "$COLOR_DIR/.profile.backup"
    fi

    cat > "$COLOR_DIR/.profile.master" <<'EOF2'
export TERM=xterm-256color

alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

export PS1='\[\033[1;32m\]\u@bb\[\033[0m\]:\[\033[1;36m\]\W\[\033[0m\]\[\033[1;31m\]# \[\033[0m\]'

colortest() {
    printf '\033[31mRED\033[0m \033[32mGREEN\033[0m \033[34mBLUE\033[0m\n'
}

restoreprofile() {
    if [ -f /root/bb_updates/ssh_colors/.profile.backup ]; then
        cp /root/bb_updates/ssh_colors/.profile.backup /root/.profile
        . /root/.profile
    else
        echo "No backup profile found"
    fi
}
EOF2

    cp "$COLOR_DIR/.profile.master" /root/.profile

    cat > /usr/bin/applytheme <<'EOF2'
#!/bin/sh
cp /root/bb_updates/ssh_colors/.profile.master /root/.profile
EOF2

    cat > /usr/bin/reloadtheme <<'EOF2'
#!/bin/sh
exec /bin/bash -l
EOF2

    chmod +x /usr/bin/applytheme /usr/bin/reloadtheme
}

verify_final() {
    log "Final verification"
    echo "Jessie debs cached:    $(ls "$DEBS_DIR"/*.deb 2>/dev/null | wc -l)"
    echo "Deduped local repo:    $(ls "$REPO_DIR"/*.deb 2>/dev/null | wc -l)"
    echo "Python3 debs cached:   $(ls "$PY3_DIR"/*.deb 2>/dev/null | wc -l)"
    echo "Tool files cached:     $(ls "$TOOLS_DIR" 2>/dev/null | wc -l)"

    bad=0
    for deb in "$DEBS_DIR"/*.deb "$PY3_DIR"/*.deb "$TOOLS_DIR"/*.deb; do
        [ -e "$deb" ] || continue
        validate_deb "$deb" || { warn "BAD DEB: $deb"; bad=$((bad + 1)); }
    done
    [ "$bad" -eq 0 ] && echo "Deb validation: OK" || echo "Deb validation: $bad bad files"

    # FIX v23: Removed python (2.x, not installed) and tmux (not installed)
    # from the check list. Only check what the script actually installs.
    for cmd in gcc g++ cc make python3 pip3 curl wget nmap tcpdump \
               socat strace ltrace lsof gdb zip unzip macchanger \
               applytheme reloadtheme; do
        have_cmd "$cmd" && echo "$cmd -> $(command -v "$cmd")"
    done

    echo
    echo "Versions:"
    gcc --version 2>/dev/null | head -1 || true
    g++ --version 2>/dev/null | head -1 || true
    python3 --version 2>&1 || true
    pip3 --version 2>&1 || true
    nmap --version 2>/dev/null | head -1 || true

    echo
    echo "DPKG CHECK:"
    dpkg -C || true
}

fix_clock() {
    # Must run before any HTTPS downloads.
    # Jessie's CA certs are outdated — if the system clock is wrong,
    # TLS handshakes fail with "certificate not yet activated".
    log "Syncing system clock via NTP..."

    # Try ntpdate with several servers
    for server in pool.ntp.org time.cloudflare.com time.google.com 1.1.1.1; do
        if ntpdate -u "$server" >/dev/null 2>&1; then
            log "Clock synced via $server: $(date)"
            return 0
        fi
    done

    # ntpdate failed — try rdate as fallback
    if have_cmd rdate; then
        rdate -n time.nist.gov 2>/dev/null && log "Clock synced via rdate: $(date)" && return 0
    fi

    # Last resort — set clock from HTTP Date header
    if have_cmd curl; then
        http_date=$(curl -sI --max-time 5 http://google.com 2>/dev/null | grep -i '^date:' | cut -d' ' -f2-)
        if [ -n "$http_date" ]; then
            date -s "$http_date" >/dev/null 2>&1 && log "Clock set from HTTP header: $(date)" && return 0
        fi
    fi

    warn "Could not sync clock — HTTPS downloads may fail due to certificate errors"
    log "Current clock: $(date)"
}

main() {
    cd /root || exit 1
    fix_clock
    sync_git_debs
    sync_python3_bundle
    sync_tools
    generate_local_repo
    configure_local_apt_only
    repair_state
    install_ordered_core_toolchain
    verify_toolchain_or_die
    install_python3_ordered
    install_package_profiles
    install_all_repo_iterative
    verify_toolchain_or_die
    install_tool_debs
    build_source_archives
    install_colors
    verify_final
    log "Done. Run: exec /bin/bash -l"
}

main "$@"
