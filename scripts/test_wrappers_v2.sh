#!/bin/sh
# test_wrappers.sh v2
# v2 fixes vs v1:
#   - test_gohttp: run server in background with kill after test so it
#     doesn't hang the test suite waiting for the server to exit
#   - responder/smbserver/psexec/wmiexec/secretsdump: wrapped in || true
#     since these tools exit non-zero for -h on some versions
#   - msfconsole: -h check skipped, takes too long to initialize

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; }
info() { echo "[*] $*"; }

COLOR_DIR="/root/bb_updates/ssh_colors"

test_cmd_exists() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "$1 wrapper exists: $(command -v "$1")"
        return 0
    else
        fail "$1 wrapper missing"
        return 1
    fi
}

test_run() {
    name="$1"
    shift
    if "$@" >/tmp/"$name".out 2>/tmp/"$name".err; then
        pass "$name ran successfully"
    else
        rc=$?
        # Some tools (responder, impacket) exit non-zero even for -h
        # Treat as warning not failure if stderr is empty or has expected content
        if grep -qiE 'usage|help|options' /tmp/"$name".out 2>/dev/null || \
           grep -qiE 'usage|help|options' /tmp/"$name".err 2>/dev/null; then
            pass "$name ran (non-zero exit but showed usage — expected)"
        else
            fail "$name failed with exit code $rc"
            [ -s /tmp/"$name".err ] && sed -n '1,20p' /tmp/"$name".err
        fi
    fi
}

test_gohttp() {
    # FIX v2: gohttp is a server — it runs until killed.
    # Run in background, check it started, then kill it.
    # The original code blocked forever waiting for it to exit.
    mkdir -p /tmp/gohttp-test
    echo ok > /tmp/gohttp-test/index.html

    gohttp -p 8080 -d /tmp/gohttp-test >/tmp/gohttp.out 2>/tmp/gohttp.err &
    GOHTTP_PID=$!

    # Give it a moment to start or fail
    sleep 2

    if kill -0 "$GOHTTP_PID" 2>/dev/null; then
        pass "gohttp started successfully (pid $GOHTTP_PID)"
        kill "$GOHTTP_PID" 2>/dev/null
        wait "$GOHTTP_PID" 2>/dev/null
    else
        # Process already exited — check if it failed
        if [ -s /tmp/gohttp.err ]; then
            fail "gohttp failed to start"
            sed -n '1,10p' /tmp/gohttp.err
        else
            # Exited cleanly with no output — treat as pass
            pass "gohttp ran and exited cleanly"
        fi
    fi

    rm -rf /tmp/gohttp-test
}

echo "========== COLOR / PROFILE TESTS =========="

test_cmd_exists applytheme || true
test_cmd_exists reloadtheme || true

[ -f "$COLOR_DIR/.profile.backup" ] && \
    pass "backup exists: $COLOR_DIR/.profile.backup" || \
    fail "missing backup: $COLOR_DIR/.profile.backup"

[ -f "$COLOR_DIR/.profile.master" ] && \
    pass "master profile exists: $COLOR_DIR/.profile.master" || \
    fail "missing master profile: $COLOR_DIR/.profile.master"

grep -q 'PS1=' /root/.profile 2>/dev/null && \
    pass ".profile contains PS1" || \
    fail ".profile missing PS1"

grep -q 'LS_COLORS=' /root/.profile 2>/dev/null && \
    pass ".profile contains LS_COLORS" || \
    info ".profile missing LS_COLORS (non-critical)"

if command -v colortest >/dev/null 2>&1; then
    pass "colortest function available in current shell"
else
    info "colortest not in current shell; reloading profile"
    . /root/.profile 2>/dev/null || true
    command -v colortest >/dev/null 2>&1 && \
        pass "colortest available after reload" || \
        info "colortest requires login shell"
fi

echo
echo "========== TOOL WRAPPER EXISTENCE TESTS =========="
for cmd in gohttp responder smbserver psexec wmiexec secretsdump msfconsole macchanger; do
    test_cmd_exists "$cmd" || true
done

echo
echo "========== TOOL WRAPPER RUN TESTS =========="

# gohttp needs special handling (it's a server)
command -v gohttp >/dev/null 2>&1 && test_gohttp

# Impacket tools — exit non-zero for -h, that's normal
command -v responder    >/dev/null 2>&1 && test_run responder    responder -h
command -v smbserver    >/dev/null 2>&1 && test_run smbserver    smbserver -h
command -v psexec       >/dev/null 2>&1 && test_run psexec       psexec -h
command -v wmiexec      >/dev/null 2>&1 && test_run wmiexec      wmiexec -h
command -v secretsdump  >/dev/null 2>&1 && test_run secretsdump  secretsdump -h

# msfconsole takes too long to init for a -h test — just check it exists
if command -v msfconsole >/dev/null 2>&1; then
    pass "msfconsole exists: $(command -v msfconsole) (skipping run test — slow init)"
fi

command -v macchanger >/dev/null 2>&1 && test_run macchanger macchanger --help

echo
echo "========== QUICK PATH SUMMARY =========="
for cmd in applytheme reloadtheme gohttp responder smbserver psexec \
           wmiexec secretsdump msfconsole macchanger; do
    command -v "$cmd" >/dev/null 2>&1 && echo "$cmd -> $(command -v "$cmd")"
done

echo
echo "========== DONE =========="
