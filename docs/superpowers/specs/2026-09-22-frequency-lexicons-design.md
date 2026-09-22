# Frequency Lexicons and Learning — Design

## Status

Approved in conversation on 2026-09-22. This document defines the next LayoutSwitcher feature increment: fast frequency-based recognition, extensible subject dictionaries, and local user learning.

## Goal

Increase correction coverage for Russian and English while keeping keyboard processing imperceptible, local, conservative, and independent of `NSSpellChecker`. Ship a built-in “Computer Terms” dictionary and let users import, enable, disable, and remove additional subject dictionaries containing words, punctuation-bearing terms, and multiword phrases.

## Success criteria

- Ordinary Russian and English words are recognized from bundled frequency data rather than the current miniature allowlists.
- Lexicon lookup performs no network access, ordinary file reads, or spell-checker calls on the keyboard event path.
- Bundled and imported compiled indexes are accessed with `mmap` and are never materialized as a complete Swift `Set` or dictionary.
- A release benchmark of 10,000 warmed lookups completes within 250 ms on the development Mac; the benchmark also reports median and p99 latency.
- The built-in “Computer Terms” pack recognizes or protects at least `Kubernetes`, `TypeScript`, `Node.js`, `.NET`, `C++`, `PostgreSQL`, `машинное обучение`, and `база данных`.
- Users can import subject dictionaries, toggle them, remove imported packs, and inspect their metadata.
- Users can create “always correct” and “never correct” rules, undo an automatic correction with Command-Z, and remove learned rules.
- All persistent data remains local. No typed-text history is stored.

## Non-goals

- Cloud synchronization, telemetry, or online dictionary updates.
- General spelling correction inside the currently selected layout.
- Statistical language models or sentence-level semantic analysis.
- Terminal, SSH, remote desktop, secure input fields, or any field already excluded by the focus-safety policy.
- Supporting languages other than Russian and English in this increment.

## Data sources and licensing

The base frequency data will be generated from the English and Russian lists in `wordfreq` 3.2.0, pinned by package version and artifact checksum in the generation script. `wordfreq` code is Apache-2.0 and its redistributed frequency data is CC BY-SA 4.0. The generated `.lsidx` files are treated as adapted data under CC BY-SA 4.0, kept separable from the application code, and shipped with the upstream `NOTICE`, attribution, source URL, version, and license text.

Only the generated indexes are application runtime resources. Python and `wordfreq` are build-time tooling and are not runtime dependencies. The generation script must produce deterministic output and a manifest with input and output SHA-256 checksums.

The initial “Computer Terms” pack is maintained as a project-authored, reviewable TSV with its own manifest. Terms copied from a third-party source may be added only when that source and its redistribution terms are recorded in the pack notice.

## Architecture

### Lookup layers

Recognition consults three layers in strict priority order:

1. `UserRuleStore`: exact “always correct” and “never correct” source/candidate pairs.
2. Enabled subject packs, including the built-in “Computer Terms” pack.
3. Bundled English and Russian base frequency indexes.

`LexiconCatalog` owns currently mapped indexes and publishes an immutable lookup snapshot. Import, removal, or enablement changes build a replacement snapshot off the event callback and swap it atomically. A keyboard event therefore sees either the old complete catalog or the new complete catalog, never a partial update.

### Memory-mapped index

Each language is compiled into one `.lsidx` file. The file contains:

- a fixed header with magic bytes, schema version, language code, record count, maximum phrase length, index offset, string-table offset, and checksum;
- fixed-width records containing UTF-8 offset, UTF-8 byte length, signed frequency score, and flags;
- a UTF-8 string table sorted by normalized key.

`MappedLexicon` opens the file read-only, validates every offset and length before publishing it, maps it with `mmap`, and uses binary search over the fixed-width record table. The mapped region is unmapped on deinitialization. Corrupt, truncated, unsupported, or oversized indexes fail closed.

Scores use Zipf frequency multiplied by 1,000 and rounded to an integer. This preserves meaningful precision without floating-point parsing on the input path.

### Normalization

Dictionary keys and input candidates use the same deterministic normalization:

- Unicode NFC;
- locale-independent lowercase;
- collapsed internal whitespace for phrases;
- straight equivalents for curly apostrophes and quotation marks;
- no transliteration and no accent stripping.

The compiler rejects duplicate normalized keys within one language unless their scores are identical; identical duplicates collapse into one record.

## Recognition flow

The input analyzer maintains only a bounded rolling window. It accepts Latin and Cyrillic letters, digits, spaces, and the internal term characters `. + # - _ / \ @`. Sentence terminators still create a decision boundary unless the current text is a prefix of an active dictionary entry. The hard limits are eight whitespace-separated tokens and 128 Unicode scalars; exceeding either limit clears the window without correction.

At a decision boundary the detector:

1. Normalizes the original suffix.
2. Produces its opposite-layout candidate while preserving neutral digits and punctuation and mapping layout-dependent punctuation.
3. Applies an exact user rule if present.
4. Searches enabled subject packs, longest phrase first.
5. Searches the base indexes.
6. Compares confidence and either emits a replacement or passes the event through.

If the current suffix is a prefix of a longer active phrase, the detector may defer until the next token. Once the phrase is disambiguated it can replace the entire buffered suffix in one operation. The rolling window is cleared on focus change, application activation, mouse input, unsafe modifiers, secure input, event-tap interruption, or replacement failure.

### Initial confidence policy

- A “never correct” rule always passes through.
- An “always correct” rule always corrects when the source text maps exactly to the stored candidate and focus is safe.
- A matching enabled subject term adds 1,500 points to that language’s score.
- Without a user rule, the target candidate must score at least 2,500.
- If the original has no score, a qualifying target candidate is corrected.
- If both have scores, the target must exceed the original by at least 1,000 points.
- Ties and low-confidence cases pass through.

These constants are named policy values and covered by boundary tests. They are not user-configurable in this increment.

## Subject dictionary packages

The import format is a directory package with the `.layoutdict` extension:

```text
Computer Terms.layoutdict/
  manifest.json
  entries.tsv
  NOTICE.txt            # optional unless required by the source
```

`manifest.json` schema version 1 contains a stable reverse-DNS identifier, display name, semantic version, description, and attribution metadata. `entries.tsv` is UTF-8 and has three tab-separated columns:

```text
language<TAB>zipf-score-x1000<TAB>term
en<TAB>4200<TAB>Node.js
en<TAB>3900<TAB>C++
ru<TAB>4100<TAB>машинное обучение
```

Blank lines and lines whose first non-whitespace character is `#` are ignored. Valid language values are `en` and `ru`. Scores are integers from 0 through 8,000. A term must contain at least one letter, fit within eight tokens and 128 Unicode scalars, and contain only the supported term characters.

Import limits are 50 MiB of source data, 1,000,000 entries total, and 4 KiB per physical line. The importer validates the complete package in a temporary directory, compiles one index per present language, verifies both generated indexes by reopening them, writes a generated manifest with checksums, and then atomically renames the completed directory into `Application Support/LayoutSwitcher/Dictionaries/<identifier>`. An existing identifier is replaced only by an explicit user-approved update. Invalid imports leave the catalog and existing files unchanged.

Built-in packs use the same manifest and compiled-index reader, but ship already compiled in the application resources. Base dictionaries are always enabled. Subject packs can be toggled; imported packs can also be removed. The application asks for confirmation before deleting an imported pack; canceling leaves its files and catalog state unchanged.

## User learning

`UserRuleStore` persists only normalized source/candidate pairs and the disposition `always` or `never`. It uses an atomically replaced versioned JSON file in `Application Support/LayoutSwitcher`; it does not store surrounding text, application names, timestamps, or a word history. Rules are loaded into a small immutable in-memory map because their expected size is user-scale rather than corpus-scale.

After every automatic replacement, the monitor retains one in-memory `LastCorrection` containing the source, candidate, delimiter, focus identity, and reversal plan. It is invalidated by the next printable input, focus change, mouse click, application change, or after ten seconds.

Command-Z while `LastCorrection` is valid is handled by LayoutSwitcher: it reverses the replacement, restores the prior layout, saves a `never` rule for that exact pair, and consumes the shortcut. Otherwise Command-Z is passed to the foreground application unchanged.

The menu exposes the most recent decision pair while it remains available:

- `Always correct “source” → “candidate”`;
- `Never correct “source” → “candidate”`;
- `Undo last correction and remember` when reversal is still safe.

A native Rules window lists saved pairs, their direction, and disposition. Users can delete selected rules or choose “Forget all user rules”; destructive removal requires confirmation.

## User interface

The menu-bar menu adds `Dictionaries…` and `Rules…`.

The Dictionaries window lists:

- English and Russian base dictionaries as always enabled;
- the built-in “Computer Terms” pack enabled by default;
- imported packs with enable switches;
- name, version, language coverage, entry count, longest phrase, source, and license summary.

It provides `Import…`, `Remove…`, and `Reveal Source Notice` actions as applicable. Import progress and compilation run away from the main thread. Success replaces the catalog snapshot on the main actor. Validation errors identify the package and failing line without exposing unrelated input data.

The Rules window supports inspection and deletion only; rule creation happens from the dynamic menu commands or Command-Z learning flow.

## Failure handling

- If a bundled base index cannot be validated, automatic correction stays paused and the menu displays a diagnostic rather than falling back to the miniature dictionary or `NSSpellChecker`.
- If one optional subject pack fails validation, that pack is disabled and other indexes remain active.
- Failed imports and updates never replace a working installed package.
- Failed rule persistence leaves the current in-memory rule active for the session and shows a diagnostic.
- Replacement and reversal remain guarded by the existing focus identity and secure-field checks.
- No lexicon management work, JSON write, compilation, or normal file I/O runs in the event-tap callback.

## Testing and verification

### Unit tests

- Deterministic compiler output, binary layout, checksum, duplicate handling, and all validation limits.
- Mapped lookup for first/middle/last/missing keys, Unicode normalization, corrupt offsets, truncation, and unsupported versions.
- Confidence thresholds immediately below, at, and above 2,500 and the 1,000-point margin.
- Subject-pack boost, enabled/disabled behavior, and user-rule precedence.
- Longest-phrase selection, prefix deferral, punctuation terms, digits, mixed scripts, window limits, and reset events.
- Rule persistence, malformed JSON recovery, Command-Z validity/invalidation, safe reversal, and ordinary Command-Z pass-through.
- Atomic import/update behavior and rejection of malformed manifests and TSV rows.

### Integration tests

- Build resources contain valid English, Russian, and Computer Terms indexes plus required notices.
- Import, enable, disable, update, and remove a temporary `.layoutdict` package.
- End-to-end correction and layout selection for representative Russian, English, and subject terms.
- Existing focus safety, Codex support, synthetic-event protection, and permission behavior remain unchanged.

### Performance verification

A release-mode benchmark opens the same mapped resources used by the app, performs 10,000 warmed mixed hit/miss lookups, reports median and p99, and fails if total lookup time exceeds 250 ms on the development Mac. A memory check confirms no collection proportional to the full entry count is retained. Import compilation is benchmarked separately and is never part of keyboard latency.

### Manual smoke test

Verify TextEdit, Codex, and a browser text field with common words, both layout directions, punctuation terms, a multiword phrase, Command-Z learning, pack toggling, and one imported test package. Confirm excluded applications and secure fields remain untouched.

## Repository and delivery workflow

Implementation remains on `feature/frequency-lexicons`. Work is test-driven and committed in independently verifiable increments. After the full test suite, packaging checks, signature verification, benchmark, and manual smoke tests pass, the feature branch is merged directly into `main` with a non-fast-forward merge.
