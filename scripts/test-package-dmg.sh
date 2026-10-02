#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
version=$(plutil -extract CFBundleShortVersionString raw -o - "$script_dir/Info.plist")
architecture=$(uname -m)
dmg_name="TwigaSwitcher-$version-$architecture.dmg"
dmg_path="$project_dir/build/$dmg_name"
public_app="$project_dir/build/public/Twiga Switcher.app"

if [[ ! -f "$script_dir/package-dmg.sh" ]]; then
  print -u2 -- "Expected a DMG packaging command."
  exit 1
fi
"$script_dir/package-dmg.sh"

cd "$project_dir/build"
shasum -a 256 -c "$dmg_name.sha256"
hdiutil verify "$dmg_path"

fixture_dir=$(mktemp -d)
mountpoint="$fixture_dir/mount"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mountpoint" >/dev/null || return
  fi
  rm -rf "$fixture_dir"
}
trap cleanup EXIT
mkdir "$mountpoint"
hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$mountpoint" >/dev/null
mounted=true

mounted_app="$mountpoint/Twiga Switcher.app"
[[ -L "$mountpoint/Applications" && $(readlink "$mountpoint/Applications") == /Applications ]]
[[ -s "$mountpoint/Installation.txt" ]]
[[ -s "$mounted_app/Contents/Resources/LICENSE.txt" ]]
[[ -s "$mounted_app/Contents/Resources/NOTICE.txt" ]]
codesign --verify --deep --strict "$mounted_app"
cmp "$public_app/Contents/MacOS/TwigaSwitcher" "$mounted_app/Contents/MacOS/TwigaSwitcher"

print -r -- "DMG contents, app signature and checksum verified."
