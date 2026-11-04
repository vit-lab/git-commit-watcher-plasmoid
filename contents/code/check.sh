#!/usr/bin/env bash
# Git Commit Watcher helper: fetches a repository and prints its latest commits.
#
# Input (environment): GCW_REPO, GCW_BRANCH, GCW_KEY, GCW_TOKEN_FILE, GCW_LIMIT
#   GCW_REPO is either a path to a local clone or a remote URL (ssh/https).
#
# Output: KEY=VALUE lines (STATUS, TIP, URL, MSG) followed by one line per commit:
#   C<US>hash<US>short<US>author<US>subject<US>relative-date<US>unix-time

US=$'\x1f'

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
KEY=$(expand "${GCW_KEY:-}")
TOKEN_FILE=$(expand "${GCW_TOKEN_FILE:-}")
LIMIT="${GCW_LIMIT:-50}"

[ -n "$REPO" ] || fail "No repository configured."
command -v git >/dev/null 2>&1 || fail "git is not installed."

TO=()
command -v timeout >/dev/null 2>&1 && TO=(timeout 90)

# Never block waiting for a password or a host-key prompt.
export GIT_TERMINAL_PROMPT=0
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"
if [ -n "$KEY" ]; then
    [ -r "$KEY" ] || fail "SSH key is not readable: $KEY"
    # Is the key protected by a passphrase, and is it unlocked in an ssh-agent?
    AOUT=$(GCW_KEY="$KEY" bash "$(dirname "$0")/agent.sh" status 2>/dev/null)
    KSTATE=$(printf '%s\n' "$AOUT" | sed -n 's/^KEY=//p')
    ASOCK=$(printf '%s\n' "$AOUT" | sed -n 's/^AGENT=//p')
    AFP=$(printf '%s\n' "$AOUT" | sed -n 's/^FP=//p')
    case "$KSTATE" in
        locked)
            printf 'STATUS=error\nCODE=locked\nMSG=%s\n' \
                "The SSH key is protected by a passphrase and is locked. Unlock it to start watching."
            exit 0
            ;;
        unlocked)
            export SSH_AUTH_SOCK="$ASOCK"
            # The agent may hold several keys (other repositories, your own keys): offer only this
            # one. That needs its public part; if it is unknown, let the agent offer its keys.
            [ -n "$AFP" ] && SSH="$SSH -i '$KEY' -o IdentitiesOnly=yes"
            ;;
        *)
            SSH="$SSH -i '$KEY' -o IdentitiesOnly=yes"
            ;;
    esac
fi
export GIT_SSH_COMMAND="$SSH"

# Optional HTTPS token, passed through the environment so it never shows up in `ps`.
if [ -n "$TOKEN_FILE" ]; then
    [ -r "$TOKEN_FILE" ] || fail "Token file is not readable: $TOKEN_FILE"
    TOKEN=$(head -n1 "$TOKEN_FILE" | tr -d '\r\n ')
    AUTH=$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="http.extraHeader"
    export GIT_CONFIG_VALUE_0="Authorization: Basic $AUTH"
fi

run_git() { "${TO[@]}" git -C "$DIR" "$@" 2>&1; }

URL=""
if [ -d "$REPO" ]; then
    # --- Local clone: fetch and compare against the remote-tracking branch ---
    DIR="$REPO"
    OUT=$(run_git rev-parse --git-dir) || fail "Not a git repository: $REPO"
    if [ -n "$BRANCH" ]; then
        OUT=$(run_git fetch --quiet --no-tags origin) || fail "git fetch failed: $OUT"
        TIPREF="refs/remotes/origin/$BRANCH"
    else
        OUT=$(run_git fetch --quiet --no-tags) || fail "git fetch failed: $OUT"
        TIPREF=$(run_git rev-parse --symbolic-full-name '@{upstream}') \
            || fail "The current branch has no upstream branch. Set a branch name in the widget settings."
    fi
    URL=$(git -C "$DIR" remote get-url origin 2>/dev/null)
else
    # --- Remote URL: keep a small shallow cache repository of our own ---
    HASHED=$(printf '%s|%s' "$REPO" "$BRANCH" | sha1sum | cut -c1-12)
    DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher/$HASHED"
    mkdir -p "$DIR" || fail "Cannot create cache directory $DIR"
    [ -d "$DIR/objects" ] || git init --bare --quiet "$DIR" || fail "Cannot initialise cache repository"
    REF="HEAD"
    [ -n "$BRANCH" ] && REF="refs/heads/$BRANCH"
    OUT=$(run_git fetch --quiet --no-tags --depth="$LIMIT" "$REPO" "+$REF:refs/gcw/tip") \
        || fail "git fetch failed: $OUT"
    TIPREF="refs/gcw/tip"
    URL="$REPO"
fi

HASH=$(git -C "$DIR" rev-parse --verify --quiet "${TIPREF}^{commit}") \
    || fail "Branch not found: ${TIPREF#refs/remotes/origin/}"

printf 'STATUS=ok\nTIP=%s\nURL=%s\n' "$HASH" "$URL"
git -C "$DIR" log -n "$LIMIT" --format="C${US}%H${US}%h${US}%an${US}%s${US}%cr${US}%ct" "$HASH"
