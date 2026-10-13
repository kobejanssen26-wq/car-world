#!/bin/sh
# Runs pure-Luau unit tests (no Roblox needed). Needs the `luau` CLI on PATH or LUAU=/path/to/luau.
# Shared modules use Roblox-style requires; rewrite them to relative requires in a temp dir.
set -e
LUAU=${LUAU:-luau}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
mkdir -p "$TMP/shared"
for f in "$HERE"/../src/shared/*.luau; do
  sed -E 's#require\(script\.Parent\.([A-Za-z]+)\)#require("./\1")#g' "$f" > "$TMP/shared/$(basename "$f")"
done
# site list for world tests, extracted from the server data file so the test cannot drift from it
{ echo "return {"; sed -nE 's/.*id = "([a-z_]+)", name = "[^"]+", kind = "([A-Za-z]+)", x = (-?[0-9]+), z = (-?[0-9]+).*/{ id = "\1", kind = "\2", x = \3, z = \4 },/p' "$HERE/../src/server/Sites.luau"; echo "}"; } > "$TMP/sites_data.luau"
cp "$HERE"/*_test.luau "$TMP/"
cd "$TMP"
for t in *_test.luau; do echo "== $t"; "$LUAU" "$t"; done
rm -rf "$TMP"
