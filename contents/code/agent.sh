#!/usr/bin/env bash
# Git Commit Watcher: manages a private ssh-agent that holds a passphrase-protected key.
#
# Usage: agent.sh status|unlock|lock
# Input (environment): GCW_KEY, GCW_LIFETIME (seconds; 0 = until logout)
# Output: STATUS=ok|error, KEY=none|missing|plain|locked|unlocked, AGENT=<socket>, OWN=1|0, MSG=<text>
#   plain    = key has no passphrase, nothing to unlock
#   locked   = key is encrypted and not loaded in any usable agent
#   unlocked = key is loaded (OWN=1: widget's private agent, OWN=0: your own agent)

DIR=$(cd "$(dirname "$0")" && pwd)
RUN="${XDG_RUNTIME_DIR:-/tmp}"
SOCK="$RUN/gcw-agent-$(id -u).sock"
ORIG_SOCK="${SSH_AUTH_SOCK:-}"

expand() {
    case "$1" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s' "$HOME/${1#"~/"}" ;;
        *) printf '%s' "$1" ;;
    esac
}
KEY=$(expand "${GCW_KEY:-}")

fail() {
    local msg
    msg=$(printf '%s' "$1" | tr '\n\r' '  ' | cut -c1-400)
    printf 'STATUS=error\nMSG=%s\n' "$msg"
    exit 0
}

# Exit code of `ssh-add -l`: 0 = has keys, 1 = agent empty, 2 = cannot connect.
agent_rc() {
    [ -n "$1" ] || return 2
    SSH_AUTH_SOCK="$1" ssh-add -l >/dev/null 2>&1
}

fingerprint() {
    local f fp
    for f in "$KEY.pub" "$KEY"; do
        [ -r "$f" ] || continue
        fp=$(ssh-keygen -lf "$f" </dev/null 2>/dev/null | awk 'NR==1{print $2}')
        if [ -n "$fp" ]; then
            printf '%s' "$fp"
            return
        fi
    done
}

# $1 = socket, $2 = "any" to accept any loaded key when the fingerprint is unknown
in_agent() {
    local list
    list=$(SSH_AUTH_SOCK="$1" ssh-add -l 2>/dev/null) || return 1
    if [ -n "$FP" ]; then
        printf '%s\n' "$list" | grep -qF "$FP"
        return
    fi
    [ "${2:-}" = "any" ]
}

is_encrypted() {
    local out
    out=$(ssh-keygen -y -P "" -f "$KEY" </dev/null 2>&1) && return 1
    printf '%s' "$out" | grep -qiE 'passphrase|incorrect'
}

KSTATE=none
ASOCK=""
OWN=0

compute_state() {
    KSTATE=none; ASOCK=""; OWN=0
    [ -n "$KEY" ] || return
    if [ ! -r "$KEY" ]; then KSTATE=missing; return; fi
    FP=$(fingerprint)
    if ! is_encrypted; then KSTATE=plain; return; fi
    if in_agent "$SOCK" any; then KSTATE=unlocked; ASOCK="$SOCK"; OWN=1; return; fi
    if [ -n "$FP" ] && [ -n "$ORIG_SOCK" ] && in_agent "$ORIG_SOCK"; then
        KSTATE=unlocked; ASOCK="$ORIG_SOCK"; OWN=0; return
    fi
    KSTATE=locked
}

report() {
    # FP is empty when the public part of the key cannot be read without the passphrase.
    printf 'STATUS=ok\nKEY=%s\nAGENT=%s\nOWN=%s\nFP=%s\n' "$KSTATE" "$ASOCK" "$OWN" "${FP:-}"
}

start_agent() {
    agent_rc "$SOCK"
    [ $? -le 1 ] && return 0
    rm -f "$SOCK"
    ssh-agent -a "$SOCK" >/dev/null 2>&1
}

do_unlock() {
    local out wrap args=()
    [ -n "$KEY" ] || fail "No SSH key configured."
    [ -r "$KEY" ] || fail "SSH key is not readable: $KEY"
    command -v ssh-add >/dev/null 2>&1 || fail "ssh-add is not installed."
    start_agent || fail "Could not start ssh-agent."

    # ssh-add needs an executable askpass program; create a tiny launcher.
    wrap="$RUN/gcw-askpass-$(id -u).sh"
    printf "#!/bin/sh\nexec bash '%s' \"\$@\"\n" "$DIR/askpass.sh" > "$wrap" && chmod 700 "$wrap"

    if [ "${GCW_LIFETIME:-0}" -gt 0 ] 2>/dev/null; then
        args=(-t "$GCW_LIFETIME")
    fi
    out=$(SSH_AUTH_SOCK="$SOCK" SSH_ASKPASS="$wrap" SSH_ASKPASS_REQUIRE=force \
          ssh-add "${args[@]}" "$KEY" </dev/null 2>&1) \
        || fail "Could not unlock the key (cancelled or wrong passphrase). $out"
    compute_state
    report
}

do_lock() {
    SSH_AUTH_SOCK="$SOCK" ssh-add -D >/dev/null 2>&1
    pkill -u "$(id -u)" -f -- "ssh-agent -a $SOCK" >/dev/null 2>&1
    rm -f "$SOCK"
    compute_state
    report
}

case "${1:-status}" in
    status) compute_state; report ;;
    unlock) do_unlock ;;
    lock) do_lock ;;
    *) fail "Unknown action: $1" ;;
esac
