#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
source_pack="$project_dir/Dictionaries/Computer Terms.layoutdict"
output_dir="$project_dir/Sources/TwigaSwitcherLexicon/Resources/Lexicons/ComputerTerms"
source_version=$(plutil -extract version raw -o - "$source_pack/manifest.json")

cd "$project_dir"
swift run -c release LexiconCompiler compile-tsv \
  --input "$source_pack/entries.tsv" \
  --output-directory "$output_dir" \
  --manifest "$output_dir/manifest.json" \
  --source-name dev.twigaswitcher.dictionary.computer-terms \
  --source-version "$source_version" \
  --source-sha256 project-authored \
  --license CC0-1.0 --minimum-score 0 --subject-terms

swift run -c release LexiconCompiler verify \
  --directory "$output_dir" --manifest "$output_dir/manifest.json" \
  --expect-minimum-score 0
