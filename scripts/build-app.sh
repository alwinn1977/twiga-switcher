#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/LayoutSwitcher.app"

cd "$project_dir"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/LayoutSwitcherApp" "$app_path/Contents/MacOS/LayoutSwitcher"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"

app_resource_bundle="$bin_dir/LayoutSwitcher_LayoutSwitcherApp.bundle"
if [[ -d "$app_resource_bundle" ]]; then
  cp -R "$app_resource_bundle" "$app_path/Contents/Resources/"
fi

for bundle_name in LayoutSwitcher_LayoutSwitcherLexicon.bundle; do
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
  --requirements '=designated => identifier "dev.layoutswitcher.prototype"' \
  "$app_path"
print -r -- "$app_path"
