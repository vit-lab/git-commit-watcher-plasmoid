#!/usr/bin/env bash
# Git Commit Watcher helper: fetches a repository and prints its latest commits.
#
# Input (environment): GCW_REPO, GCW_BRANCH, GCW_KEY, GCW_TOKEN_FILE, GCW_LIMIT
#   GCW_MODE=branches: print only the branches ("B<US>name" lines) instead of the commits.
#   GCW_CYCLE: an id of the check round (optional). The widget checks every watched branch of a
#     repository at the same moment; with the same id those checks talk to the remote only once
#     (one fetch of a local clone, one "ls-remote" of a remote URL) and share the result.
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

# Sharing between the checks of one round needs flock and a private directory for the small state
# files (the runtime directory of the user); without them every check works on its own.
RUN="${XDG_RUNTIME_DIR:-}"
CYCLE="${GCW_CYCLE:-}"
case "$CYCLE" in
    *[!0-9a-zA-Z-]*) CYCLE="" ;;
esac
HAVE_FLOCK=""
command -v flock >/dev/null 2>&1 && HAVE_FLOCK=1
if [ -z "$RUN" ] || [ ! -d "$RUN" ] || [ -z "$HAVE_FLOCK" ]; then
    CYCLE=""
fi

# Runs "$@" (a git command that talks to the remote) once per round: the first check of the round
# runs it, the others wait for it and get its saved result, also when it failed. $1 names the lock
# and $2 the saved result; the output of the command is printed, and the exit status is the one of
# the command. The lock also makes fetches of one clone take turns (git does not like them in
# parallel).
once_per_round() {
    local lockname="$1" name="$2" state lock
    shift 2
    if [ -z "$RUN" ] || [ -z "$HAVE_FLOCK" ]; then
        "${TO[@]}" "$@" 2>&1
        return
    fi
    state="$RUN/gcw-$name.state"
    lock="$RUN/gcw-$lockname.lock"
    (
        flock -w 120 9 || { printf '%s' "Timed out waiting for another check of this repository."; exit 1; }
        if [ -n "$CYCLE" ]; then
            case "$(head -n1 "$state" 2>/dev/null)" in
                "$CYCLE ok") tail -n +2 "$state"; exit 0 ;;
                "$CYCLE failed") tail -n +2 "$state"; exit 1 ;;
            esac
        fi
        out=$("${TO[@]}" "$@" 2>&1)
        rc=$?
        if [ -n "$CYCLE" ]; then
            if [ "$rc" -eq 0 ]; then
                printf '%s ok\n%s\n' "$CYCLE" "$out" > "$state"
            else
                printf '%s failed\n%s\n' "$CYCLE" "$out" > "$state"
            fi
        fi
        printf '%s\n' "$out"
        exit "$rc"
    ) 9>"$lock"
}

# A short name for the state files: what is asked, and with which credentials.
state_name() {
    printf '%s|%s|%s' "$1" "$KEY" "$TOKEN_FILE" | sha1sum | cut -c1-16
}

# Fetches the local clone $DIR ("$@": the remote, or nothing for the default one).
fetch_clone() {
    once_per_round "$(printf '%s' "$DIR" | sha1sum | cut -c1-12)" "$(state_name "fetch|$DIR|$*")" \
        git -C "$DIR" fetch --quiet --no-tags "$@"
}

# Prints the branch tips of the remote URL $REPO: "<commit>\trefs/heads/<branch>" lines.
remote_heads() {
    local name
    name=$(state_name "heads|$REPO")
    once_per_round "$name" "$name" git ls-remote --heads "$REPO"
}

# Mode "branches": only list the branches of the repository (for the ALL / pattern setting).
if [ "${GCW_MODE:-}" = "branches" ]; then
    if [ -d "$REPO" ]; then
        DIR="$REPO"
        OUT=$(run_git rev-parse --git-dir) || fail "Not a git repository: $REPO"
        OUT=$(fetch_clone origin) || fail "git fetch failed: $OUT"
        LIST=$(git -C "$DIR" for-each-ref --format='%(refname)' refs/remotes/origin 2>/dev/null \
            | sed 's#^refs/remotes/origin/##' | grep -v '^HEAD$')
    else
        OUT=$(remote_heads) || fail "git ls-remote failed: $OUT"
        LIST=$(printf '%s\n' "$OUT" | awk '{print $2}' | sed 's#^refs/heads/##')
    fi
    printf 'STATUS=ok\n'
    printf '%s\n' "$LIST" | while IFS= read -r b; do
        [ -n "$b" ] && printf 'B%s%s\n' "$US" "$b"
    done
    exit 0
fi

URL=""
if [ -d "$REPO" ]; then
    # --- Local clone: fetch and compare against the remote-tracking branch ---
    DIR="$REPO"
    OUT=$(run_git rev-parse --git-dir) || fail "Not a git repository: $REPO"
    if [ -n "$BRANCH" ]; then
        OUT=$(fetch_clone origin) || fail "git fetch failed: $OUT"
        TIPREF="refs/remotes/origin/$BRANCH"
    else
        OUT=$(fetch_clone) || fail "git fetch failed: $OUT"
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
    # In a round, ask the remote once for the tips of all branches; a branch whose tip is already in
    # the cache needs no fetch of its own.
    REMOTE_TIP=""
    if [ -n "$BRANCH" ] && [ -n "$CYCLE" ]; then
        OUT=$(remote_heads) || fail "git ls-remote failed: $OUT"
        REMOTE_TIP=$(printf '%s\n' "$OUT" | awk -v ref="$REF" '$2 == ref { print $1; exit }')
        [ -n "$REMOTE_TIP" ] || fail "Branch not found: $BRANCH"
    fi
    LOCAL_TIP=$(git -C "$DIR" rev-parse --verify --quiet "refs/gcw/tip^{commit}")
    if [ -z "$REMOTE_TIP" ] || [ "$REMOTE_TIP" != "$LOCAL_TIP" ]; then
        OUT=$(run_git fetch --quiet --no-tags --depth="$LIMIT" "$REPO" "+$REF:refs/gcw/tip") \
            || fail "git fetch failed: $OUT"
    fi
    TIPREF="refs/gcw/tip"
    URL="$REPO"
fi

HASH=$(git -C "$DIR" rev-parse --verify --quiet "${TIPREF}^{commit}") \
    || fail "Branch not found: ${TIPREF#refs/remotes/origin/}"

printf 'STATUS=ok\nTIP=%s\nURL=%s\n' "$HASH" "$URL"
git -C "$DIR" log -n "$LIMIT" --format="C${US}%H${US}%h${US}%an${US}%s${US}%cr${US}%ct" "$HASH"
