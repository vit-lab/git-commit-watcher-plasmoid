#!/usr/bin/env bash
# Git Commit Watcher helper: searches the whole history of the watched branches of one repository
# ("All history" next to the search field of the widget). Read-only for a local clone.
#
# Input (environment): GCW_REPO, GCW_BRANCHES (space-separated; empty = the upstream branch of a local
#   clone, or the default branch of a remote URL), GCW_KEY, GCW_TOKEN_FILE,
#   GCW_QUERY (the search text), GCW_MAX (the most commits printed, 200 by default).
# Output: "STATUS=ok", one line per found commit (newest first), then "MORE=1" if there are more than
#   GCW_MAX, else "MORE=0":
#     C<US>hash<US>short<US>author<US>subject<US>relative-date<US>unix-time<US>branch
#   or "STATUS=error" / "MSG=<text>" (and "CODE=locked" for a locked SSH key).
#
# A commit matches like in the list of the widget (Helpers.filterCommits): every word of the text is in
# its subject or its author (upper and lower case are the same), or is the beginning of its hash (4 or
# more characters).
#
# A local clone has its history already. For a remote URL the checks keep only the last commits (see
# check.sh), so the search has a second copy of its own, in ~/.cache/gitcommitwatcher/history/: all the
# commits of the watched branches, but no folder listings and no file contents ("tree:0"). The first
# search downloads it (a few MB to some tens of MB for a big repository), later searches only what is new.

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

# Background work, like a check: do not compete with the desktop.
renice -n 10 -p $$ >/dev/null 2>&1
command -v ionice >/dev/null 2>&1 && ionice -c 2 -n 7 -p $$ >/dev/null 2>&1

REPO=$(expand "${GCW_REPO:-}")
KEY=$(expand "${GCW_KEY:-}")
TOKEN_FILE=$(expand "${GCW_TOKEN_FILE:-}")
BRANCHES="${GCW_BRANCHES:-}"
MAX="${GCW_MAX:-200}"
case "$MAX" in
    "" | *[!0-9]*) MAX=200 ;;
esac

[ -n "$REPO" ] || fail "No repository configured."
[ -n "$(printf '%s' "${GCW_QUERY:-}" | tr -d '[:space:]')" ] || fail "Nothing to search for."
command -v git >/dev/null 2>&1 || fail "git is not installed."

TO=()
TOF=()
if command -v timeout >/dev/null 2>&1; then
    TO=(timeout 90)
    TOF=(timeout 600)
fi

REFS=()
set -f                                  # branch names are split at spaces, never expanded as patterns
if [ -d "$REPO" ]; then
    # --- Local clone: the history is there (the checks keep it up to date) ---
    DIR="$REPO"
    git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || fail "Not a git repository: $REPO"
    PREFIX="refs/remotes/origin/"
    for b in $BRANCHES; do
        git -C "$DIR" rev-parse --verify --quiet "refs/remotes/origin/$b^{commit}" >/dev/null \
            && REFS+=("refs/remotes/origin/$b")
    done
    if [ "${#REFS[@]}" -eq 0 ]; then
        PREFIX=""
        if git -C "$DIR" rev-parse --verify --quiet '@{upstream}^{commit}' >/dev/null 2>&1; then
            REFS=('@{upstream}')
        else
            REFS=(HEAD)
        fi
    fi
else
    # --- Remote URL: the history copy of this URL ---
    # shellcheck source=auth.sh
    . "$(dirname "$0")/auth.sh"
    DIR="${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher/history/$(printf '%s' "$REPO" | sha1sum | cut -c1-12)"
    mkdir -p "$DIR" || fail "Cannot create the folder $DIR"
    if [ ! -f "$DIR/HEAD" ]; then
        git init --bare --quiet "$DIR" || fail "Cannot create the history copy $DIR"
    fi
    if [ "$(git -C "$DIR" config --get remote.origin.url)" != "$REPO" ] \
        || [ "$(git -C "$DIR" config --get remote.origin.partialclonefilter)" != "tree:0" ]; then
        git -C "$DIR" config core.repositoryformatversion 1 \
            && git -C "$DIR" config extensions.partialClone origin \
            && git -C "$DIR" config remote.origin.url "$REPO" \
            && git -C "$DIR" config remote.origin.promisor true \
            && git -C "$DIR" config remote.origin.partialclonefilter tree:0 \
            || fail "Cannot set up the history copy $DIR"
    fi
    touch "$DIR/gcw-used" 2>/dev/null

    # Which of the wanted branches the remote has, and which of them are not up to date here.
    PREFIX="refs/gcw/tips/"
    SPECS=()
    if [ -n "$BRANCHES" ]; then
        HEADS=$("${TO[@]}" git ls-remote --heads "$REPO" 2>&1) || fail "git ls-remote failed: $HEADS"
        for b in $BRANCHES; do
            git check-ref-format "refs/heads/$b" 2>/dev/null || continue
            tip=$(printf '%s\n' "$HEADS" | awk -v ref="refs/heads/$b" '$2 == ref { print $1; exit }')
            [ -n "$tip" ] || continue
            REFS+=("refs/gcw/tips/$b")
            have=$(git -C "$DIR" rev-parse --verify --quiet "refs/gcw/tips/$b^{commit}")
            [ "$tip" = "$have" ] || SPECS+=("+refs/heads/$b:refs/gcw/tips/$b")
        done
        [ "${#REFS[@]}" -gt 0 ] || fail "None of the watched branches was found in the repository."
    else
        PREFIX=""
        REFS=("refs/gcw/head")
        SPECS=("+HEAD:refs/gcw/head")
    fi
    if [ "${#SPECS[@]}" -gt 0 ]; then
        fetch_history() {
            "${TOF[@]}" git -C "$DIR" fetch --quiet --no-tags --filter=tree:0 origin "${SPECS[@]}" 2>&1
        }
        # Two searches of the same repository take turns.
        if command -v flock >/dev/null 2>&1; then
            OUT=$( ( flock -w 660 9 || { printf 'Timed out waiting for another search of this repository.'; exit 1; }
                     fetch_history ) 9>"$DIR/gcw-search.lock" ) \
                || fail "Downloading the history failed: $(printf '%s' "$OUT" | tail -n 3)"
        else
            OUT=$(fetch_history) || fail "Downloading the history failed: $(printf '%s' "$OUT" | tail -n 3)"
        fi
    fi
fi
set +f

printf 'STATUS=ok\n'
export GCW_QUERY
"${TO[@]}" git -C "$DIR" log --no-color --source \
    --format="C${US}%H${US}%h${US}%an${US}%s${US}%cr${US}%ct${US}%S" "${REFS[@]}" -- 2>/dev/null \
    | awk -F"$US" -v OFS="$US" -v max="$MAX" -v prefix="$PREFIX" '
        BEGIN {
            n = split(tolower(ENVIRON["GCW_QUERY"]), raw, /[ \t\r\n]+/)
            nw = 0
            for (i = 1; i <= n; ++i) {
                if (raw[i] != "") {
                    w[++nw] = raw[i]
                    # a possible beginning of a hash: 4 to 40 characters, all of them 0-9 or a-f
                    hex[nw] = (length(raw[i]) >= 4 && length(raw[i]) <= 40 && raw[i] !~ /[^0-9a-f]/)
                }
            }
            found = 0
            more = 0
        }
        $1 == "C" {
            text = tolower($5 "\n" $4)
            for (i = 1; i <= nw; ++i) {
                if (index(text, w[i]) == 0 && !(hex[i] && index($2, w[i]) == 1)) {
                    next
                }
            }
            if (found >= max) {
                more = 1
                exit
            }
            ++found
            if (prefix != "" && index($8, prefix) == 1) {
                $8 = substr($8, length(prefix) + 1)
            } else {
                $8 = ""
            }
            print
        }
        END { print "MORE=" more }
    '
exit 0
