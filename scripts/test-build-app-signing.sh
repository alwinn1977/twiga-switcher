#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/Twiga Switcher.app"
expected_requirement='designated => identifier "dev.twigaswitcher.prototype"'
lexicon_bundle="$app_path/Contents/Resources/TwigaSwitcher_LayoutSwitcherLexicon.bundle/Contents/Resources"
base_lexicons="$lexicon_bundle/Lexicons/Base"
computer_terms="$lexicon_bundle/Lexicons/ComputerTerms"

"$script_dir/build-app.sh" >/dev/null
actual_requirement=$(codesign -dr - "$app_path" 2>&1 | tail -n 1)

if [[ "$actual_requirement" != "$expected_requirement" ]]; then
  print -u2 -- "Expected stable requirement: $expected_requirement"
  print -u2 -- "Actual requirement:          $actual_requirement"
  exit 1
fi

for notice in README.md wordfreq-NOTICE.md wordfreq-LICENSE.txt Apache-2.0.txt CC-BY-SA-4.0.txt computer-terms-NOTICE.txt CC0-1.0.txt; do
  if [[ ! -s "$lexicon_bundle/Licenses/$notice" ]]; then
    print -u2 -- "Missing bundled lexicon notice: $notice"
    exit 1
  fi
done

cd "$project_dir"
swift run LexiconCompiler verify \
  --directory "$base_lexicons" \
  --manifest "$base_lexicons/manifest.json" \
  --expect-minimum-score 2500 \
  --lookup en:development=5310 \
  --lookup ru:разработчики=3990

swift run LexiconCompiler verify \
  --directory "$computer_terms" \
  --manifest "$computer_terms/manifest.json" \
  --lookup en:node.js=4800 \
  --lookup en:.net=4000 \
  --lookup ru:машинное\ обучение=4800

print -r -- "Stable local signing and bundled lexicons verified."
