#!/usr/bin/env bash
# Copies what the public repository (1ajh/srle-studio) holds into a checkout
# of it: public-repo/ (README, licenses, issue templates, the transcription
# workflow), the logo and, the first time, bases/. Review and commit there.
#
#   git clone https://github.com/1ajh/srle-studio ../srle-studio
#   tool/publish_public_repo.sh ../srle-studio           # first time, or docs
#   tool/publish_public_repo.sh ../srle-studio --bases   # also replace bases/
#
# Approved transcriptions are merged in the public repository, so its bases/
# can be newer than this one's: --bases replaces them, so pull them back here
# first. Release builds take bases/ from the public repository either way.
set -euo pipefail

dest="${1:?usage: tool/publish_public_repo.sh <checkout of 1ajh/srle-studio> [--bases]}"
here="$(cd "$(dirname "$0")/.." && pwd)"

[ -d "$dest/.git" ] || { echo "$dest is not a git checkout" >&2; exit 1; }
[ "$(cd "$dest" && pwd)" != "$here" ] || { echo "Give the public repository's checkout, not this one" >&2; exit 1; }

cp -R "$here/public-repo/." "$dest/"
cp "$here/assets/branding/logo_256.png" "$dest/logo.png"

if [ ! -f "$dest/bases/catalog.json" ] || [ "${2:-}" = "--bases" ]; then
  rm -rf "$dest/bases"
  cp -R "$here/bases" "$dest/bases"
else
  echo "Kept $dest/bases (pass --bases to replace it)"
fi

echo "Copied into $dest:"
git -C "$dest" status --short
