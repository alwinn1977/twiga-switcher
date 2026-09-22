#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
resource_dir="$project_dir/Sources/LayoutSwitcherLexicon/Resources/Lexicons/Base"
wordfreq_version=3.1.1
wordfreq_wheel_sha256=4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473

if [[ ${1:-} == "--check-tools" ]]; then
  command -v python3 >/dev/null || { print -u2 -- "python3 is required"; exit 1; }
  command -v swift >/dev/null || { print -u2 -- "swift is required"; exit 1; }
  python3 -c "import importlib.metadata; assert importlib.metadata.version('wordfreq') == '$wordfreq_version'" 2>/dev/null || {
    print -u2 -- "wordfreq $wordfreq_version is not installed in the current Python; generation will install it in an isolated environment"
    exit 1
  }
  print -r -- "Generation tools are available."
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wheel_dir="$work_dir/wheels"
venv_dir="$work_dir/venv"
tsv_path="$work_dir/base.tsv"
compiled_dir="$work_dir/compiled"
manifest_path="$work_dir/manifest.json"
mkdir -p "$wheel_dir" "$compiled_dir"

if [[ -n ${WORDFREQ_WHEEL:-} ]]; then
  cp "$WORDFREQ_WHEEL" "$wheel_dir/wordfreq-$wordfreq_version-py3-none-any.whl"
else
  python3 -m pip download \
    --disable-pip-version-check \
    --no-deps \
    --only-binary=:all: \
    "wordfreq==$wordfreq_version" \
    --dest "$wheel_dir"
fi

wheel_path="$wheel_dir/wordfreq-$wordfreq_version-py3-none-any.whl"
actual_sha256=$(shasum -a 256 "$wheel_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$wordfreq_wheel_sha256" ]]; then
  print -u2 -- "wordfreq wheel checksum mismatch: expected $wordfreq_wheel_sha256, got $actual_sha256"
  exit 1
fi

python3 -m venv "$venv_dir"
"$venv_dir/bin/python" -m pip install --disable-pip-version-check --quiet "$wheel_path"
"$venv_dir/bin/python" "$script_dir/export-wordfreq.py" --output "$tsv_path"

cd "$project_dir"
swift run -c release LexiconCompiler compile-tsv \
  --input "$tsv_path" \
  --output-directory "$compiled_dir" \
  --manifest "$manifest_path" \
  --source-name wordfreq \
  --source-version "$wordfreq_version" \
  --source-sha256 "$wordfreq_wheel_sha256" \
  --license CC-BY-SA-4.0 \
  --minimum-score 2500

cp "$manifest_path" "$compiled_dir/manifest.json"
replacement_dir="$resource_dir.replacement"
mkdir -p "${resource_dir:h}"
rm -rf "$replacement_dir"
mv "$compiled_dir" "$replacement_dir"
if [[ -d "$resource_dir" ]]; then
  python3 -c 'import ctypes, os, sys; libc = ctypes.CDLL(None, use_errno=True); result = libc.renamex_np(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 2); result == 0 or (_ for _ in ()).throw(OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno())))' "$resource_dir" "$replacement_dir"
  rm -rf "$replacement_dir"
else
  mv "$replacement_dir" "$resource_dir"
fi

print -r -- "$resource_dir"
