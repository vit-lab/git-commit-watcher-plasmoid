#!/usr/bin/env bash
# Git Commit Watcher helper: fetches a repository and prints its latest commits.
#
# Input (environment): GCW_REPO, GCW_BRANCH, GCW_KEY, GCW_TOKEN_FILE, GCW_LIMIT
#   GCW_MODE=branches: print only the branches ("B<US>name" lines) instead of the commits.
#   GCW_CYCLE: an id of the check round (optional). The widget checks every watched branch of a
#     repository at the same moment; with the same id those checks talk to the remote only once
#     (one fetch of a local clone, one "ls-remote" and one fetch for a remote URL) and share the result.
#   GCW_BRANCHES: all watched branches of this repository (space-separated, optional). The first check
#     of a round fetches the new commits of all of them at once.
#   GCW_PROGRESS_ID: a name for the progress file (optional). While a fetch runs, git's progress is
#     written to $XDG_RUNTIME_DIR/gcw-progress-<id>.txt, and the widget shows it.
#   GCW_REPO is either a path to a local clone or a remote URL (ssh/https).
#   GCW_MODE=stop: stops all running checks (the Stop button of the widget) and prints "STATUS=ok".
#   GCW_MULTI=1: checks every branch in GCW_BRANCHES, one after another in this one process, and prints the
#     result of each after a line "U<US>branch". The widget starts one process per repository this way, not
#     one per branch: with many branches, starting and handling a process for each of them made the panel
#     stall for a second or two.
#
# Every check runs in a session of its own (setsid) and leaves a file $XDG_RUNTIME_DIR/gcw-check-<pid>.run
# while it runs, so that "stop" can end it together with its git, ssh and timeout processes.
#
# Output: KEY=VALUE lines (STATUS, TIP, URL, MSG) followed by one line per commit:
#   C<US>hash<US>short<US>author<US>subject<US>relative-date<US>unix-time
#
# A remote URL gets a cache repository of its own (see cache_dir_of in auth.sh), shared by all its
# branches. It is shallow (the last commits only) and blobless: only commits and folder listings are
# downloaded, and git fetches the files of a commit when its changes are shown (diff.sh).

US=$'\x1f'

# Mode "stop": end every running check, with all its processes (see above).
if [ "${GCW_MODE:-}" = "stop" ]; then
    D="${XDG_RUNTIME_DIR:-}"
    if [ -n "$D" ] && [ -d "$D" ]; then
        for f in "$D"/gcw-check-*.run; do
            [ -f "$f" ] || continue
            p="${f##*/gcw-check-}"
            p="${p%.run}"
            case "$p" in
                "" | *[!0-9]*) rm -f "$f"; continue ;;
            esac
            # Only a process that still is one of our checks (the number may have been reused).
            if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'check\.sh'; then
                pkill -TERM -s "$p" 2>/dev/null || kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
            fi
            rm -f "$f"
        done
    fi
    printf 'STATUS=ok\n'
    exit 0
fi

# Run in a session of our own, so that "stop" can end this check with everything it started.
if [ -z "${GCW_SESSION:-}" ] && command -v setsid >/dev/null 2>&1; then
    export GCW_SESSION=1
    exec setsid -w bash "$0" "$@"
fi
# A check is background work: it must not compete with the desktop for the processor or the disk (a big
# first download, or the removal of old caches, could make the panel stutter). Its git, ssh and rm
# processes inherit this.
if [ -n "${GCW_SESSION:-}" ]; then
    renice -n 10 -p $$ >/dev/null 2>&1
    command -v ionice >/dev/null 2>&1 && ionice -c 2 -n 7 -p $$ >/dev/null 2>&1
fi
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}" ] && [ -n "${GCW_SESSION:-}" ]; then
    RUNFILE="$XDG_RUNTIME_DIR/gcw-check-$$.run"
    : > "$RUNFILE"
    trap 'rm -f "$RUNFILE"' EXIT
    trap 'exit 143' TERM INT HUP
fi

# Mode "several branches" (see GCW_MULTI above). The branches share one "ls-remote" and one fetch through
# the round id; without one, this process makes its own.
if [ "${GCW_MULTI:-}" = "1" ]; then
    [ -n "${GCW_CYCLE:-}" ] || export GCW_CYCLE="m$$"
    set -f
    for b in ${GCW_BRANCHES:-}; do
        printf 'U%s%s\n' "$US" "$b"
        GCW_MULTI="" GCW_BRANCH="$b" bash "$0"
    done
    exit 0
fi

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
case "$LIMIT" in
    "" | *[!0-9]*) LIMIT=50 ;;
esac

[ -n "$REPO" ] || fail "No repository configured."
command -v git >/dev/null 2>&1 || fail "git is not installed."

# Time limits: short for questions to the remote, longer for downloads (the first fetch of a big
# repository can take a while; the widget shows its progress).
TO=()
TOF=()
if command -v timeout >/dev/null 2>&1; then
    TO=(timeout 90)
    TOF=(timeout 600)
fi

# shellcheck source=auth.sh
. "$(dirname "$0")/auth.sh"

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

PROGRESS=""
PID_="${GCW_PROGRESS_ID:-}"
case "$PID_" in
    "" | *[!0-9a-zA-Z_-]*) ;;
    *) [ -n "$RUN" ] && [ -d "$RUN" ] && PROGRESS="$RUN/gcw-progress-$PID_.txt" ;;
esac

# Runs "$@" (a command that talks to the remote) once per round: the first check of the round runs
# it, the others wait for it and get its saved result, also when it failed. $1 names the lock and $2
# the saved result; the output of the command is printed, and the exit status is the one of the
# command. The lock also makes fetches of one repository take turns (git does not like them in
# parallel).
once_per_round() {
    local lockname="$1" name="$2" state lock
    shift 2
    if [ -z "$RUN" ] || [ -z "$HAVE_FLOCK" ]; then
        "$@" 2>&1
        return
    fi
    state="$RUN/gcw-$name.state"
    lock="$RUN/gcw-$lockname.lock"
    (
        flock -w 660 9 || { printf '%s' "Timed out waiting for another check of this repository."; exit 1; }
        if [ -n "$CYCLE" ]; then
            case "$(head -n1 "$state" 2>/dev/null)" in
                "$CYCLE ok") tail -n +2 "$state"; exit 0 ;;
                "$CYCLE failed") tail -n +2 "$state"; exit 1 ;;
            esac
        fi
        out=$("$@" 2>&1)
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

# Runs "git fetch" in the repository $1 with the other arguments. With a progress file, git's
# progress goes there while it runs (the widget shows it), and on failure git's messages are printed.
net_fetch() {
    local dir="$1" rc
    shift
    if [ -z "$PROGRESS" ]; then
        "${TOF[@]}" git -C "$dir" fetch --quiet "$@" 2>&1
        return
    fi
    "${TOF[@]}" git -C "$dir" fetch --progress "$@" >/dev/null 2>"$PROGRESS"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        tr '\r' '\n' < "$PROGRESS" | grep -v '^[[:space:]]*$' \
            | grep -Ev '[0-9]+% \(|^remote: (Enumerating|Counting|Compressing|Total)|^From |^ [*+=!-] ' | tail -n 4
        [ "$rc" -eq 124 ] && printf '%s\n' "The download took longer than 10 minutes."
    fi
    rm -f "$PROGRESS"
    return "$rc"
}

# Fetches the local clone $DIR ("$@": the remote, or nothing for the default one).
fetch_clone() {
    once_per_round "$(printf '%s' "$DIR" | sha1sum | cut -c1-12)" "$(state_name "fetch|$DIR|$*")" \
        net_fetch "$DIR" --no-tags "$@"
}

# Prints the branch tips of the remote URL $REPO: "<commit>\trefs/heads/<branch>" lines.
remote_heads() {
    local name
    name=$(state_name "heads|$REPO")
    once_per_round "$name" "$name" "${TO[@]}" git ls-remote --heads "$REPO"
}

# Creates the cache repository $DIR for the remote URL $REPO, or fixes its settings.
prepare_cache() {
    mkdir -p "$DIR" || return 1
    if [ ! -f "$DIR/HEAD" ]; then
        git init --bare --quiet "$DIR" || return 1
    fi
    if [ "$(git -C "$DIR" config --get extensions.partialClone)" != "origin" ] \
        || [ "$(git -C "$DIR" config --get remote.origin.url)" != "$REPO" ]; then
        git -C "$DIR" config core.repositoryformatversion 1 \
            && git -C "$DIR" config extensions.partialClone origin \
            && git -C "$DIR" config remote.origin.url "$REPO" \
            && git -C "$DIR" config remote.origin.promisor true \
            && git -C "$DIR" config remote.origin.partialclonefilter blob:none \
            || return 1
    fi
    touch "$DIR/gcw-used" 2>/dev/null
    return 0
}

# The number of commits per branch that the cache repository is known to hold (file gcw-depth; a cache
# made before this file existed holds the 50 + 1 commits that were downloaded then).
cache_depth() {
    local d
    d=$(head -n1 "$DIR/gcw-depth" 2>/dev/null)
    case "$d" in
        "" | *[!0-9]*) d=51 ;;
    esac
    printf '%s' "$d"
}

# Fetches the given refspecs into the cache repository: the last LIMIT+1 commits (the extra one is
# the parent of the oldest listed commit, so that its changes can be shown), without file contents.
# A fetch with a smaller number than before may shorten what the cache holds, so the number is lowered.
fetch_cache() {
    net_fetch "$DIR" --no-tags --depth="$((LIMIT + 1))" --filter=blob:none origin "$@" || return 1
    if [ "$((LIMIT + 1))" -lt "$(cache_depth)" ] || [ ! -f "$DIR/gcw-depth" ]; then
        printf '%s\n' "$((LIMIT + 1))" > "$DIR/gcw-depth" 2>/dev/null
    fi
    return 0
}

# The first check of a round: fetches every watched branch whose tip on the remote ($HEADS) is not
# in the cache yet, in one go. When more commits per branch are wanted than the cache holds (the setting
# was raised), all watched branches are fetched again, which only downloads the older commits.
fetch_watched() {
    local specs=() b tip have deepen=""
    [ "$(cache_depth)" -lt "$((LIMIT + 1))" ] && deepen=1
    for b in $BRANCHES; do
        git check-ref-format "refs/heads/$b" 2>/dev/null || continue
        tip=$(printf '%s\n' "$HEADS" | awk -v ref="refs/heads/$b" '$2 == ref { print $1; exit }')
        [ -n "$tip" ] || continue
        have=$(git -C "$DIR" rev-parse --verify --quiet "refs/gcw/tips/$b^{commit}")
        if [ -n "$deepen" ] || [ "$tip" != "$have" ]; then
            specs+=("+refs/heads/$b:refs/gcw/tips/$b")
        fi
    done
    [ "${#specs[@]}" -gt 0 ] || return 0
    fetch_cache "${specs[@]}" || return 1
    if [ -n "$deepen" ]; then
        printf '%s\n' "$((LIMIT + 1))" > "$DIR/gcw-depth" 2>/dev/null
    fi
    return 0
}

# Removes caches that are no longer used: the per-branch caches of version 1.3 and older (folders with
# 12-character names directly in the cache folder) and cache repositories unused for 30 days.
cleanup_caches() {
    local base="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher"
    [ -d "$base" ] || return 0
    local idle=()
    command -v ionice >/dev/null 2>&1 && idle=(ionice -c 3)     # deleting many files is heavy on the disk
    find "$base" -mindepth 1 -maxdepth 1 -type d -name '????????????' -exec test -f '{}/HEAD' ';' \
        -exec "${idle[@]}" rm -rf '{}' + 2>/dev/null
    find "$base/repos" -mindepth 2 -maxdepth 2 -name gcw-used -mtime +30 -printf '%h\0' 2>/dev/null \
        | xargs -0 -r "${idle[@]}" rm -rf
    # The history copies of the search in the whole history (search.sh), unused for 30 days.
    find "$base/history" -mindepth 2 -maxdepth 2 -name gcw-used -mtime +30 -printf '%h\0' 2>/dev/null \
        | xargs -0 -r "${idle[@]}" rm -rf
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
    # --- Remote URL: the cache repository of this URL, shared by its branches ---
    DIR=$(cache_dir_of "$REPO")
    LOCKNAME=$(printf '%s' "$DIR" | sha1sum | cut -c1-12)
    if [ -n "$RUN" ] && [ -n "$HAVE_FLOCK" ]; then
        ( flock -n 8 && cleanup_caches ) 8>"$RUN/gcw-cleanup.lock"
    else
        cleanup_caches
    fi
    OUT=$(once_per_round "$LOCKNAME" "$(state_name "prepare|$DIR")" prepare_cache) \
        || fail "Cannot create the cache repository $DIR: $OUT"
    if [ -n "$BRANCH" ]; then
        git check-ref-format "refs/heads/$BRANCH" 2>/dev/null || fail "Invalid branch name: $BRANCH"
        REF="refs/heads/$BRANCH"
        TIPREF="refs/gcw/tips/$BRANCH"
    else
        REF="HEAD"
        TIPREF="refs/gcw/head"
    fi
    if [ -n "$BRANCH" ] && [ -n "$CYCLE" ]; then
        # In a round, ask the remote once for the tips of all branches, and let the first check fetch
        # the new commits of all watched branches.
        HEADS=$(remote_heads) || fail "git ls-remote failed: $HEADS"
        printf '%s\n' "$HEADS" | awk -v ref="$REF" '$2 == ref { found = 1 } END { exit !found }' \
            || fail "Branch not found: $BRANCH"
        BRANCHES="$BRANCH ${GCW_BRANCHES:-}"
        OUT=$(once_per_round "$LOCKNAME" "$(state_name "fetch|$REPO")" fetch_watched) \
            || fail "git fetch failed: $OUT"
    else
        OUT=$(once_per_round "$LOCKNAME" "$(state_name "fetch|$REPO|$REF")" fetch_cache "+$REF:$TIPREF") \
            || fail "git fetch failed: $OUT"
    fi
    URL="$REPO"
fi

HASH=$(git -C "$DIR" rev-parse --verify --quiet "${TIPREF}^{commit}") \
    || fail "Branch not found: ${TIPREF#refs/remotes/origin/}"

printf 'STATUS=ok\nTIP=%s\nURL=%s\n' "$HASH" "$URL"
git -C "$DIR" log -n "$LIMIT" --format="C${US}%H${US}%h${US}%an${US}%s${US}%cr${US}%ct" "$HASH"
