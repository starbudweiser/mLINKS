#!/bin/bash
# Publie une version : compile, notarise (Developer ID) puis crée la release GitHub avec mLINKS.zip,
# que la mise à jour automatique de l'appli va chercher.
# Usage : scripts/release.sh <version>   (ex. 1.2 ; le tag devient v1.2)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage : scripts/release.sh <version>}"
NOTARIZE=/Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh
DIST="$(mktemp -d)"

swift test
VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
DIST="$DIST" "$NOTARIZE" mLINKS.app
gh release create "v$VERSION" "$DIST/mLINKS.zip" --title "mLINKS $VERSION" --generate-notes
rm -rf "$DIST"
