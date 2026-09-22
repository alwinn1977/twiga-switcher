#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/LayoutSwitcher.app"
expected_requirement='designated => identifier "dev.layoutswitcher.prototype"'

"$script_dir/build-app.sh" >/dev/null
actual_requirement=$(codesign -dr - "$app_path" 2>&1 | tail -n 1)

if [[ "$actual_requirement" != "$expected_requirement" ]]; then
  print -u2 -- "Expected stable requirement: $expected_requirement"
  print -u2 -- "Actual requirement:          $actual_requirement"
  exit 1
fi

print -r -- "Stable local signing requirement verified."
