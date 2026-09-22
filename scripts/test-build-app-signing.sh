#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/LayoutSwitcher.app"
expected_requirement='designated => identifier "dev.layoutswitcher.prototype"'
lexicon_bundle="$app_path/Contents/Resources/LayoutSwitcher_LayoutSwitcherLexicon.bundle/Contents/Resources"

"$script_dir/build-app.sh" >/dev/null
actual_requirement=$(codesign -dr - "$app_path" 2>&1 | tail -n 1)

if [[ "$actual_requirement" != "$expected_requirement" ]]; then
  print -u2 -- "Expected stable requirement: $expected_requirement"
  print -u2 -- "Actual requirement:          $actual_requirement"
  exit 1
fi

for notice in wordfreq-NOTICE.md CC-BY-SA-4.0.txt; do
  if [[ ! -s "$lexicon_bundle/$notice" ]]; then
    print -u2 -- "Missing bundled lexicon notice: $notice"
    exit 1
  fi
done

cd "$project_dir"
swift run LexiconCompiler verify \
  --directory "$lexicon_bundle" \
  --manifest "$lexicon_bundle/manifest.json" \
  --expect-minimum-score 2500 \
  --lookup en:development=5310 \
  --lookup ru:разработчики=3990

print -r -- "Stable local signing and bundled lexicons verified."
