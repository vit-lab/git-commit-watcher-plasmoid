#!/usr/bin/env bash
# Git Commit Watcher helper: saves one file as it is in a given commit to the widget's own
# cache folder, so that it can be opened with the default application. Read-only for the
# repository: nothing is written to it, and the working tree is not touched.
#
# Input (environment): GCW_REPO, GCW_BRANCH, GCW_HASH, GCW_PATH (path inside the repository)
# Output: "STATUS=ok" and "FILE=<absolute path of the copy>", or "STATUS=error" / "MSG=<text>".

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
P="${GCW_PATH:-}"

[ -n "$REPO" ] || fail "No repository configured."
case "$HASH" in
    "" | *[!0-9a-fA-F]*) fail "Invalid commit id." ;;
esac
[ -n "$P" ] || fail "No file given."
case "$P" in
    /* | ../* | */../* | */.. | .. | *$'\n'*) fail "Invalid file path." ;;
esac
command -v git >/dev/null 2>&1 || fail "git is not installed."

# Same location logic as diff.sh: a local clone, or our own cache for remote URLs.
if [ -d "$REPO" ]; then
    DIR="$REPO"
else
    HASHED=$(printf '%s|%s' "$REPO" "$BRANCH" | sha1sum | cut -c1-12)
    DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher/$HASHED"
    [ -d "$DIR/objects" ] || fail "No cached data for this repository yet."
fi

git -C "$DIR" cat-file -e "${HASH}^{commit}" 2>/dev/null \
    || fail "Commit $HASH is not available locally (try again after the next check)."

SPEC="$HASH:$P"
TYPE=$(git -C "$DIR" cat-file -t "$SPEC" 2>/dev/null) \
    || fail "The file does not exist in this commit (deleted?): $P"
[ "$TYPE" = "blob" ] || fail "Not a regular file (a folder or a submodule): $P"
SIZE=$(git -C "$DIR" cat-file -s "$SPEC" 2>/dev/null || echo 0)
[ "$SIZE" -le 52428800 ] 2>/dev/null || fail "The file is larger than 50 MB: $P"

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher/files"
SHORT=$(printf '%s' "$HASH" | cut -c1-12)
OUT="$BASE/$SHORT/$P"

# Forget copies older than a week (only the 12-character commit folders made by this script).
[ -d "$BASE" ] && find "$BASE" -mindepth 1 -maxdepth 1 -type d -name '????????????' -mtime +7 \
    -exec rm -rf {} + 2>/dev/null

rm -f "$OUT" 2>/dev/null
mkdir -p "$(dirname "$OUT")" 2>/dev/null || fail "Cannot create the cache folder."
git -C "$DIR" cat-file blob "$SPEC" > "$OUT" 2>/dev/null || { rm -f "$OUT"; fail "Cannot read the file from git."; }
# Read-only on purpose: this is a snapshot of the commit, not a file of the repository.
chmod 444 "$OUT" 2>/dev/null

printf 'STATUS=ok\nFILE=%s\n' "$OUT"
exit 0
