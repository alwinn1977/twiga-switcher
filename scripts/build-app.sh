#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
build_directory="$project_dir/build"
public_build=false
if [[ "${1:-}" == "--public" && $# == 1 ]]; then
  public_build=true
  build_directory="$build_directory/public"
elif (( $# != 0 )); then
  print -u2 -- "Usage: $0 [--public]"
  exit 2
fi
app_path="$build_directory/Twiga Switcher.app"

cd "$project_dir"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/TwigaSwitcherApp" "$app_path/Contents/MacOS/TwigaSwitcher"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/LICENSE" "$app_path/Contents/Resources/LICENSE.txt"
cp "$project_dir/NOTICE" "$app_path/Contents/Resources/NOTICE.txt"

icon_source="$project_dir/Resources/AppIcon.png"
iconset="$build_directory/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$icon_source" --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
  double_size=$((icon_size * 2))
  sips -z "$double_size" "$double_size" "$icon_source" --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

for bundle_name in TwigaSwitcher_TwigaSwitcherApp.bundle TwigaSwitcher_TwigaSwitcherLexicon.bundle; do
  resource_bundle="$bin_dir/$bundle_name"
  if [[ ! -d "$resource_bundle" ]]; then
      print -u2 -- "Missing required SwiftPM resource bundle: $resource_bundle"
      exit 1
  fi
  cp -R "$resource_bundle" "$app_path/Contents/Resources/"
done

plutil -lint "$app_path/Contents/Info.plist"
signing_arguments=(--force --deep --sign -)
if [[ "$public_build" == false ]]; then
  signing_arguments+=(--requirements '=designated => identifier "dev.twigaswitcher.prototype"')
fi
codesign "${signing_arguments[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"

# Finder may have cached the bundle while its executable and icon were being
# replaced. Register the completed bundle and notify it after all files exist.
if [[ "$public_build" == false ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
fi
touch "$app_path"
print -r -- "$app_path"
