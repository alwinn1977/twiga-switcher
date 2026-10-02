#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
if (( $# != 0 )); then
  print -u2 -- "Usage: $0"
  exit 2
fi

"$script_dir/build-app.sh" --public
app_path="$project_dir/build/public/Twiga Switcher.app"
version=$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")
architecture=$(lipo -archs "$app_path/Contents/MacOS/TwigaSwitcher")
dmg_name="TwigaSwitcher-$version-${architecture// /-}.dmg"
dmg_path="$project_dir/build/$dmg_name"

staging_directory=$(mktemp -d)
trap 'rm -rf "$staging_directory"' EXIT
ditto "$app_path" "$staging_directory/Twiga Switcher.app"
ln -s /Applications "$staging_directory/Applications"
cp "$script_dir/DMG-Installation.txt" "$staging_directory/Installation.txt"

hdiutil create \
  -volname "Twiga Switcher" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  -fs HFS+ \
  -ov "$dmg_path"
hdiutil verify "$dmg_path"

cd "$project_dir/build"
shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
print -r -- "$dmg_path"
print -r -- "$dmg_path.sha256"
