#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/LayoutSwitcher.app"

cd "$project_dir"
bin_dir=$(swift build -c release --show-bin-path)

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/LayoutSwitcherApp" "$app_path/Contents/MacOS/LayoutSwitcher"
cp "$script_dir/Info.plist" "$app_path/Contents/Info.plist"

resource_bundle="$bin_dir/LayoutSwitcher_LayoutSwitcherApp.bundle"
if [[ -d "$resource_bundle" ]]; then
  cp -R "$resource_bundle" "$app_path/Contents/Resources/"
fi

plutil -lint "$app_path/Contents/Info.plist"
codesign --force --deep --sign - "$app_path"
print -r -- "$app_path"
