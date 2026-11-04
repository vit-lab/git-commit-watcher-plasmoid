#!/usr/bin/env bash
# Passphrase prompt used by ssh-add (SSH_ASKPASS). Shows a native dialog; the
# passphrase goes straight from the dialog to ssh-add and is never stored.
prompt="${1:-SSH key passphrase}"
title="Git Commit Watcher"

if command -v kdialog >/dev/null 2>&1; then
    exec kdialog --title "$title" --password "$prompt"
elif command -v ksshaskpass >/dev/null 2>&1; then
    exec ksshaskpass "$prompt"
elif command -v zenity >/dev/null 2>&1; then
    exec zenity --password --title "$title"
fi
echo "No passphrase dialog found (install kdialog)" >&2
exit 1
