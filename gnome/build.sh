#!/usr/bin/env bash
# Copyright (C) 2026 NventaTech — GPL-3.0-or-later
# cctop - packs the GNOME Shell extension as a zip ready for
# `gnome-extensions install` or extensions.gnome.org.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
version=$(python3 -c 'import json;print(json.load(open("'"$here"'/metadata.json"))["version-name"])')
out="$root/dist/cctop-gnome-$version.zip"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/pkg" "$root/dist"
cp "$here"/metadata.json "$here"/extension.js "$here"/prefs.js "$here"/stylesheet.css "$tmp/pkg/"
cp -r "$here/lib" "$tmp/pkg/lib"
mkdir -p "$tmp/pkg/schemas" "$tmp/pkg/code" "$tmp/pkg/icons" "$tmp/pkg/images"
cp "$here"/schemas/*.gschema.xml "$tmp/pkg/schemas/"
cp -L "$here"/code/fetch.sh "$here"/code/export.sh "$here"/code/summary.sh "$tmp/pkg/code/"
cp -L "$here"/icons/*.svg "$tmp/pkg/icons/"
cp -L "$here"/images/donate-qr.png "$tmp/pkg/images/"

rm -f "$out"
(cd "$tmp/pkg" && zip -qr "$out" .)
echo "$out"
