#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

input_one="$fixture_dir/one.tsv"
input_two="$fixture_dir/two.tsv"
output_one="$fixture_dir/output-one"
output_two="$fixture_dir/output-two"
manifest_one="$fixture_dir/manifest-one.json"
manifest_two="$fixture_dir/manifest-two.json"

print -r -- $'en\t5200\tHello\nru\t5100\tпривет\nen\t4100\tworld' > "$input_one"
print -r -- $'en\t4100\tworld\nen\t5200\tHello\nru\t5100\tпривет' > "$input_two"

cd "$project_dir"
swift run LexiconCompiler compile-tsv \
  --input "$input_one" \
  --output-directory "$output_one" \
  --manifest "$manifest_one" \
  --source-name fixture \
  --source-version 1 \
  --source-sha256 fixture-sha256 \
  --license Fixture \
  --minimum-score 2500
swift run LexiconCompiler compile-tsv \
  --input "$input_two" \
  --output-directory "$output_two" \
  --manifest "$manifest_two" \
  --source-name fixture \
  --source-version 1 \
  --source-sha256 fixture-sha256 \
  --license Fixture \
  --minimum-score 2500

cmp "$output_one/en.lsidx" "$output_two/en.lsidx"
cmp "$output_one/ru.lsidx" "$output_two/ru.lsidx"
cmp "$manifest_one" "$manifest_two"
[[ $(plutil -extract minimumScore raw -o - "$manifest_one") == 2500 ]]

swift run LexiconCompiler verify \
  --directory "$output_one" \
  --manifest "$manifest_one" \
  --expect-count en:2 \
  --expect-count ru:1 \
  --lookup en:hello=5200 \
  --lookup ru:привет=5100

print -r -- "Lexicon generation fixture verified."
