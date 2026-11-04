#!/usr/bin/env bash
# Builds dist/git-commit-watcher-<version>.plasmoid from the files of this repository.
# Only the Plasma package itself goes into the archive (metadata.json, contents/, LICENSE).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION=$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' metadata.json | head -n1)
[ -n "$VERSION" ] || { echo "Cannot read the version from metadata.json" >&2; exit 1; }

OUT="dist/git-commit-watcher-${VERSION}.plasmoid"
FILES=(metadata.json contents LICENSE)

for f in "${FILES[@]}"; do
    [ -e "$f" ] || { echo "Missing: $f" >&2; exit 1; }
done

mkdir -p dist
rm -f "$OUT"

if command -v zip >/dev/null 2>&1; then
    zip -q -r -X "$OUT" "${FILES[@]}"
elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -c "$OUT" "${FILES[@]}"
else
    echo "Need 'zip' or 'python3' to build the package." >&2
    exit 1
fi

echo "Built $OUT"
echo "Install: kpackagetool6 -t Plasma/Applet -i $OUT"
