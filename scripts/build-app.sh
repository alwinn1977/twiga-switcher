#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/Twiga Switcher.app"

cd "$project_dir"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/TwigaSwitcherApp" "$app_path/Contents/MacOS/TwigaSwitcher"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"

icon_source="$project_dir/Resources/AppIcon.png"
iconset="$project_dir/build/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$icon_source" --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
  double_size=$((icon_size * 2))
  sips -z "$double_size" "$double_size" "$icon_source" --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
rm -rf "$iconset"

app_resource_bundle="$bin_dir/TwigaSwitcher_TwigaSwitcherApp.bundle"
if [[ -d "$app_resource_bundle" ]]; then
  cp -R "$app_resource_bundle" "$app_path/Contents/Resources/"
fi

for bundle_name in TwigaSwitcher_TwigaSwitcherLexicon.bundle; do
  resource_bundle="$bin_dir/$bundle_name"
  if [[ ! -d "$resource_bundle" ]]; then
      print -u2 -- "Missing required SwiftPM resource bundle: $resource_bundle"
      exit 1
  fi
  cp -R "$resource_bundle" "$app_path/Contents/Resources/"
done

plutil -lint "$app_path/Contents/Info.plist"
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "dev.twigaswitcher.prototype"' \
  "$app_path"

# Finder may have cached the bundle while its executable and icon were being
# replaced. Register the completed bundle and notify it after all files exist.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
touch "$app_path"
print -r -- "$app_path"
