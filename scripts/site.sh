#!/bin/bash
# Builds the GitHub Pages site into build/site (or the folder given as $1).
# The page reads the real pet packs and art, so they are copied in rather than committed twice.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build/site}"
rm -rf "$out"
mkdir -p "$out/art"
cp -R site/. "$out/"
cp Resources/Art/*.png "$out/art/"
for pack in Pets/*/; do
  id="$(basename "$pack")"
  mkdir -p "$out/pets/$id"
  cp "$pack"pet.json "$pack"*.png "$out/pets/$id/"
done
echo "Site built in $out"
