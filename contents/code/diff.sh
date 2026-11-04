#!/usr/bin/env bash
# Git Commit Watcher helper: prints the changes of one commit (read-only).
#
# Input (environment): GCW_REPO, GCW_BRANCH, GCW_HASH
# Output: "STATUS=ok" followed by the plain `git show` text (at most 4001 lines),
#         or "STATUS=error" / "MSG=<text>".

fail() {
    local msg
    msg=$(printf '%s' "$1" | tr '\n\r' '  ' | cut -c1-400)
    printf 'STATUS=error\nMSG=%s\n' "$msg"
    exit 0
}

expand() {
    case "$1" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s' "$HOME/${1#"~/"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

REPO=$(expand "${GCW_REPO:-}")
BRANCH="${GCW_BRANCH:-}"
HASH="${GCW_HASH:-}"

[ -n "$REPO" ] || fail "No repository configured."
case "$HASH" in
    "" | *[!0-9a-fA-F]*) fail "Invalid commit id." ;;
esac
command -v git >/dev/null 2>&1 || fail "git is not installed."

# Same location logic as check.sh: a local clone, or our own cache for remote URLs.
if [ -d "$REPO" ]; then
    DIR="$REPO"
else
    HASHED=$(printf '%s|%s' "$REPO" "$BRANCH" | sha1sum | cut -c1-12)
    DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher/$HASHED"
    [ -d "$DIR/objects" ] || fail "No cached data for this repository yet."
fi

git -C "$DIR" cat-file -e "${HASH}^{commit}" 2>/dev/null \
    || fail "Commit $HASH is not available locally (try again after the next check)."

TO=()
command -v timeout >/dev/null 2>&1 && TO=(timeout 30)

printf 'STATUS=ok\n'
"${TO[@]}" git -C "$DIR" -c core.quotepath=false show --no-color --no-ext-diff \
    --patch-with-stat -M "$HASH" 2>&1 | cut -c1-1500 | head -n 4001
exit 0
