#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
cd "$root"

swift build -c release --product LexiconBenchmark
bin_dir=$(swift build -c release --show-bin-path)
benchmark="$bin_dir/LexiconBenchmark"
en_index="$root/Sources/LayoutSwitcherLexicon/Resources/Lexicons/Base/en.lsidx"
ru_index="$root/Sources/LayoutSwitcherLexicon/Resources/Lexicons/Base/ru.lsidx"

if [[ "${1:-}" == "--self-test" ]]; then
  if "$benchmark" "$en_index" "$ru_index" --lookups 10000 --budget-ms 0; then
    print -u2 "benchmark self-test expected the zero-millisecond budget to fail"
    exit 1
  fi
fi

"$benchmark" "$en_index" "$ru_index" --lookups 10000 --budget-ms 250
