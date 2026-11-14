# Git Commit Watcher helper, sourced by check.sh, diff.sh and openfile.sh: sets up the SSH key and
# the HTTPS token for the git commands that talk to the remote.
#
# Expects: KEY and TOKEN_FILE (expanded paths, may be empty) and a "fail" function.
# AUTH_SOFT=1: a locked key is not an error. diff.sh and openfile.sh only talk to the remote for files
#   that are not downloaded yet; if that is needed, git reports the failure itself.

# Never block waiting for a password or a host-key prompt.
export GIT_TERMINAL_PROMPT=0
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"
if [ -n "$KEY" ]; then
    [ -r "$KEY" ] || fail "SSH key is not readable: $KEY"
    # Is the key protected by a passphrase, and is it unlocked in an ssh-agent?
    AOUT=$(GCW_KEY="$KEY" bash "$(dirname "${BASH_SOURCE[0]}")/agent.sh" status 2>/dev/null)
    KSTATE=$(printf '%s\n' "$AOUT" | sed -n 's/^KEY=//p')
    ASOCK=$(printf '%s\n' "$AOUT" | sed -n 's/^AGENT=//p')
    AFP=$(printf '%s\n' "$AOUT" | sed -n 's/^FP=//p')
    case "$KSTATE" in
        locked)
            if [ -z "${AUTH_SOFT:-}" ]; then
                printf 'STATUS=error\nCODE=locked\nMSG=%s\n' \
                    "The SSH key is protected by a passphrase and is locked. Unlock it to start watching."
                exit 0
            fi
            SSH="$SSH -i '$KEY' -o IdentitiesOnly=yes"
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

# Where the cache repository of a remote URL lives (shared by all its branches).
cache_dir_of() {
    printf '%s/repos/%s' "${XDG_CACHE_HOME:-$HOME/.cache}/gitcommitwatcher" \
        "$(printf '%s' "$1" | sha1sum | cut -c1-12)"
}
