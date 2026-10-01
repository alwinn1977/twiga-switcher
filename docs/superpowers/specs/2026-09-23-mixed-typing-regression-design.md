# Mixed-Language Typing Regression — Design

## Status and purpose

Approved in conversation on 2026-09-23. The goal is to establish whether TwigaSwitcher produces the intended text during sustained typing, rather than merely making correct decisions for isolated words. The user requested two tests of the same long mixed-language sample: one with no manual layout changes and one with manual changes at language boundaries.

## Acceptance criteria

- A reviewable, literal UTF-8 corpus contains at least 20 lines. Every line mixes Russian and English words or computer terms; across the corpus it exercises both correction directions, ordinary words, subject terms, multiword terms, spaces, sentence punctuation, and consecutive language changes.
- The corpus includes at least eight distinct Russian words whose physical-key sequences contain `.` when typed with the English layout, including `rjvgm.nth` → `компьютер`. It also includes words whose wrong-layout input uses `,` or `;`. These characters must be interpreted in word context as layout-dependent keys when appropriate, not universally as sentence punctuation.
- Two integration tests feed the corpus as a sequence of physical keys through the app's real event-normalization, focus-processing, detection, replacement, and layout-selection path. One begins in a declared layout and never manually switches; the other manually selects the intended layout at annotated language boundaries while automatic correction remains enabled.
- In both tests the resulting editor text equals the literal expected corpus byte-for-byte after every line and at the end. Layout checkpoints and the count/direction of corrections are checked independently; a correct final string reached through unintended intermediate corruption is not sufficient.
- Correctly typed words remain unchanged. Synthetic replacement events cannot recursively trigger correction. The tests use isolated rules and bundled dictionaries, never the user's rules or documents.
- `swift test`, the release app build, and the existing lexicon performance benchmark pass after any fixes. A native TextEdit smoke run uses the same sample when reliable UI input and read-back are available; an environmental limitation is reported explicitly rather than counted as a pass.

The guarantee is for this documented corpus and supported editable fields, not arbitrary natural-language text or inherently ambiguous words that the conservative detector intentionally leaves unchanged.

## Options considered

1. Pipeline-only tests are fast but miss physical keycodes, punctuation normalization, focus handling, replacement ordering, and layout selection.
2. TextEdit-only automation exercises the OS path but depends on TCC permissions, foreground focus, and the automation tool's event injection. It is hard to make deterministic in ordinary `swift test` runs.
3. **Chosen: a deterministic full-path test driver plus a separate native smoke run.** This keeps a reliable regression gate while still checking the host integration when the environment permits it.

## Corpus and input model

The expected text is written by hand and committed as a fixture; it is never produced by `LayoutConverter` or by applying the implementation's correction plans to itself. The same expected text is used for both modes. In the manual scenario, the driver selects the layout of each next word before its first key whenever that word's Cyrillic/Latin script differs from the active layout; punctuation inherits the preceding word's layout.

The test driver maps each intended printable key to its physical US/Russian keyboard position with a small independent fixture mapping. It emits a `CGEvent` containing the character actually produced by the current simulated input source. This makes `rjvgm.nth` observable as raw input rather than calling the conversion API directly. Spaces, newlines, punctuation, and modifier transitions use their actual keycodes. The simulator updates its current layout only when TwigaSwitcher selects a source or when the manual scenario explicitly switches it.

The corpus should use supported US/Russian printable keys and realistic vocabulary. It must not be constructed only from words already known to pass; any failing line is preserved as a regression case. New dictionary entries are acceptable only when they are legitimate general or computer terms, not as hidden test overrides.

### Literal expected text

The following 24 lines, including the final newline, are the expected editor contents in **both** scenarios. This text is the independent oracle for the integration tests, not an illustration to be generated later.

```text
компьютер запускает Linux, затем browser показывает страницу проекта.
Редактор открывает Node.js, меню показывает logs, пока editor сохраняет файл.
Разработчик пишет TypeScript, люди читают русский комментарий.
Сервис Docker запускает PostgreSQL, бюджет проекта остается прежним.
Кластер Kubernetes запускает pod, любой разработчик видит статус.
Новый API возвращает JSON, ключ защищает ответ клиента.
Запрос HTTP приходит в backend, мьютекс защищает общий журнал.
Система macOS запускает SwiftUI, плюс проверяет layout после слова.
Команда Git создает commit, потом reviewer читает diff.
Проверка CI запускает tests, когда изменился исходный код.
Файл README описывает setup, русский текст уточняет шаги.
Старый C++ модуль вызывает library, возвращает число.
Платформа .NET собирает build, пользователь смотрит прогресс.
Адрес localhost открывает dashboard, показывает новые данные.
Редактор TextEdit печатает привет, затем hello, потом снова привет.
Страница browser показывает Linux, содержит документацию.
Значение timeout защищает request, когда сеть отвечает медленно.
Модель machine learning изучает данные, однако не хранит ввод.
После update приложение читает config, обновляет словарь.
Параметр cache ускоряет lookup, память остается стабильной.
Меню terminal показывает error, разработчик открывает report.
Ключ API защищает request, когда сеть отвечает медленно.
Второй компьютер проверяет Windows, затем запускает Linux.
Финальная строка содержит Node.js, компьютер, English words.
```

For the no-manual-switch test the initial source is English. Its first physical keys must therefore be `rjvgm.nth`, producing `компьютер` after the first space. The following independent raw-key checkpoints cover the class, not just that example: `vty.` → `меню`, `k.lb` → `люди`, `,.l;tn` → `бюджет`, `k.,jq` → `любой`, `rk.x` → `ключ`, `vm.ntrc` → `мьютекс`, and `gk.c` → `плюс`. Each appears immediately after an English term in the expected text, so the automatic scenario should encounter it while English is active. The manual-switch test selects Russian before the first word and switches to the intended language at each script transition; its expected text is identical.

## Test driver and assertions

The driver lives in the test target. It calls the same `KeyboardMonitor` key-down handling path that the event tap calls, with the real bundled `LexiconService`, an isolated `UserRuleStore`, and a stable safe `FocusSnapshot`. A virtual editor applies unsuppressed original keys and the actual backspace/Unicode operations requested through `ReplacementExecutor`; a simulated input-source manager records layout changes. The virtual editor must not bypass or recompute the production replacement plan.

Each scenario starts with a fresh monitor, editor, rules file, and input-source state. At each completed line it compares the virtual editor with the corresponding literal expected prefix, recording the first divergent key, current layout, source text, and produced text. Additional assertions cover the exact internal-dot case, representative Russian-to-English and English-to-Russian transitions, absence of false corrections in the manual scenario, and synthetic-event immunity. Small unit regressions are added at the failing component boundary before changing production code.

The driver is a test utility, not a production feature or hidden correction mechanism. It should remain fast enough for the normal local test suite. A separate measurement reports sustained input processing time and checks that dictionary loading and file I/O stay outside the per-key path.

## Debugging and fix policy

First run both tests against the current build and record every mismatch. For each distinct cause, trace the emitted key through normalization, buffering, detection, replacement, and layout selection; compare it with a nearby working case. Write the smallest failing regression test for that cause, confirm it fails, implement one focused correction, and rerun the complete corpus. Do not weaken the expected text, add arbitrary per-example exceptions, or mask errors with manual switches in the automatic scenario.

The existing policy of conservative handling for unsafe focus and ambiguous words remains. If a corpus item is intrinsically ambiguous under the existing policy, replace it with a clear, realistic term before implementation and document why; do not silently change the acceptance target after a failure.

## Native verification and limits

After deterministic tests pass, build and launch the signed app and attempt the same two scenarios in a fresh TextEdit document. Read back the editor's text and compare with the committed corpus. Use genuine key events and verify that TextEdit is the foreground editable target; text pasting or AX `setValue` is not an input test. The run must not modify the user's existing documents or rules. If the automation environment cannot reliably deliver events through the global tap, leave the result unverified, state the concrete limitation, and provide the exact manual reproduction procedure.

## Delivery

Commit the corpus, driver, regression tests, and any focused production fixes directly to `main`, following the user's repository preference. Keep the working tree clean and report both scenario results, any native-smoke limitation, test/build/benchmark results, and the first-divergence diagnostic if acceptance is not met.
