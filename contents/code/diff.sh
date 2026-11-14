#!/usr/bin/env bash
# Git Commit Watcher helper: prints the changes of one commit (read-only).
#
# Input (environment): GCW_REPO, GCW_HASH, GCW_KEY, GCW_TOKEN_FILE (the key and token are needed for a
#   remote URL: its cache has no file contents, and git downloads the changed files of the commit).
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
HASH="${GCW_HASH:-}"
KEY=$(expand "${GCW_KEY:-}")
TOKEN_FILE=$(expand "${GCW_TOKEN_FILE:-}")

[ -n "$REPO" ] || fail "No repository configured."
case "$HASH" in
    "" | *[!0-9a-fA-F]*) fail "Invalid commit id." ;;
esac
command -v git >/dev/null 2>&1 || fail "git is not installed."

TO=()
TOF=()
if command -v timeout >/dev/null 2>&1; then
    TO=(timeout 30)
    TOF=(timeout 180)
fi

# Same location logic as check.sh: a local clone, or our own cache for remote URLs.
if [ -d "$REPO" ]; then
    DIR="$REPO"
else
    AUTH_SOFT=1
    # shellcheck source=auth.sh
    . "$(dirname "$0")/auth.sh"
    DIR=$(cache_dir_of "$REPO")
    [ -d "$DIR/objects" ] || fail "No cached data for this repository yet."
fi

FULL=$(git -C "$DIR" rev-parse --verify --quiet "${HASH}^{commit}" 2>/dev/null) \
    || fail "Commit $HASH is not available locally (try again after the next check)."

# A shallow copy does not have the parent of its oldest commit, and git would show that commit as if
# it added every file of the repository (and download all of them).
SHALLOW=$(cd "$DIR" && git rev-parse --path-format=absolute --git-path shallow 2>/dev/null)
if [ -n "$SHALLOW" ] && [ -f "$SHALLOW" ] && grep -qx "$FULL" "$SHALLOW" \
    && git -C "$DIR" cat-file -p "$FULL" 2>/dev/null | grep -q '^parent '; then
    fail "This is the oldest commit the widget has downloaded, so its changes cannot be shown here. Double-click the commit to see it in the browser."
fi

# A cache without file contents: let git download the changed files first (in one go), so that a
# failure is reported as such instead of ending up in the middle of the diff.
if [ -n "$(git -C "$DIR" config --get extensions.partialClone 2>/dev/null)" ]; then
    ERR=$("${TOF[@]}" git -C "$DIR" show --format= --stat -M "$FULL" 2>&1 >/dev/null) \
        || fail "Downloading the changed files failed: $(printf '%s' "$ERR" | tail -n 3)"
fi

printf 'STATUS=ok\n'
"${TO[@]}" git -C "$DIR" -c core.quotepath=false show --no-color --no-ext-diff \
    --patch-with-stat -M "$FULL" 2>&1 | cut -c1-1500 | head -n 4001
exit 0
