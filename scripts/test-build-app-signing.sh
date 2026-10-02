#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/build/Twiga Switcher.app"
expected_requirement='designated => identifier "dev.twigaswitcher.prototype"'
build_arguments=()
if [[ "${1:-}" == "--public" && $# == 1 ]]; then
  build_arguments=(--public)
  app_path="$project_dir/build/public/Twiga Switcher.app"
elif (( $# != 0 )); then
  print -u2 -- "Usage: $0 [--public]"
  exit 2
fi
lexicon_bundle="$app_path/Contents/Resources/TwigaSwitcher_TwigaSwitcherLexicon.bundle/Contents/Resources"
base_lexicons="$lexicon_bundle/Lexicons/Base"
computer_terms="$lexicon_bundle/Lexicons/ComputerTerms"
app_resources="$app_path/Contents/Resources/TwigaSwitcher_TwigaSwitcherApp.bundle/Contents/Resources"
configuration="$app_resources/Configuration"

"$script_dir/build-app.sh" "${build_arguments[@]}" >/dev/null
if [[ ! -d "$app_path" ]]; then
  print -u2 -- "Expected the built app at $app_path"
  exit 1
fi
codesign --verify --deep --strict "$app_path"
actual_requirement=$(codesign -dr - "$app_path" 2>&1 | sed -nE 's/^#?[[:space:]]*designated => /designated => /p')

if (( ${#build_arguments} != 0 )); then
  fixture_dir=$(mktemp -d)
  trap 'rm -rf "$fixture_dir"' EXIT
  impostor="$fixture_dir/impostor"
  cp /usr/bin/true "$impostor"
  codesign --force --sign - --identifier dev.twigaswitcher.prototype "$impostor"
  public_requirement=${actual_requirement#'designated => '}
  [[ -n "$public_requirement" ]]
  codesign --verify --strict --test-requirement "=$public_requirement" "$app_path"
  if codesign --verify --strict --test-requirement "=$public_requirement" "$impostor" >/dev/null 2>&1; then
    print -u2 -- "Public signing must reject different code with the same identifier."
    exit 1
  fi
elif [[ "$actual_requirement" != "$expected_requirement" ]]; then
  print -u2 -- "Expected stable requirement: $expected_requirement"
  print -u2 -- "Actual requirement:          $actual_requirement"
  exit 1
fi

for name in Applications KeyboardLayouts; do
  if [[ ! -s "$configuration/$name.json" ]]; then
    print -u2 -- "Missing bundled configuration: $name.json"
    exit 1
  fi
done
swift -e '
import Foundation
for path in CommandLine.arguments.dropFirst() {
    _ = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
}
' "$configuration/Applications.json" "$configuration/KeyboardLayouts.json"

for language in en ru; do
  strings="$app_resources/$language.lproj/Localizable.strings"
  if [[ ! -s "$strings" ]]; then
    print -u2 -- "Missing bundled localization: $language"
    exit 1
  fi
  plutil -lint "$strings"
done

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

print -r -- "Signing, bundled configuration, localizations and lexicons verified."
