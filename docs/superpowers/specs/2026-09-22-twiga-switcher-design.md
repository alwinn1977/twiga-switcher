# TwigaSwitcher Prototype Design

## Purpose

TwigaSwitcher is a local, native macOS menu-bar application that automatically repairs words typed in the wrong Russian or English keyboard layout. The prototype must demonstrate reliable `ghbdtn → привет` and `руддщ → hello` correction in ordinary text fields without sending or persisting typed text.

The first version prioritizes avoiding false corrections over correcting every possible word. If the language decision is uncertain, the application leaves the text unchanged.

## Scope

### Included

- A native Swift/AppKit menu-bar application for macOS 14 or later.
- Global keyboard observation through `CGEventTap`.
- Automatic correction when a word is completed with Space, Return, or a supported punctuation mark.
- Bidirectional US-English and Russian keyboard-layout conversion.
- Case preservation for lowercase, title case, and uppercase words.
- Conservative language detection using a small bundled lexicon, macOS spelling services, and a built-in allowlist for common technical terms.
- Switching the active input source to match a successful correction.
- A menu-bar control that shows running, disabled, or permission-required state and lets the user enable or disable correction or quit.
- Permission guidance for Accessibility and Input Monitoring.
- Protection against recursive processing of the application's own synthetic events.
- Best-effort secure-field detection through Accessibility metadata.
- Built-in exclusion of terminal and remote-desktop applications.

### Not included

- Double Shift or other configurable hotkeys.
- Selected-text conversion.
- User-editable word or application exceptions.
- Typo correction within the intended layout.
- Machine learning, telemetry, cloud services, or input history.
- Distribution signing, notarization, App Store packaging, or automatic updates.
- Support for nonstandard Dvorak/phonetic/custom layouts, more than two languages, Terminal/SSH, remote desktops, or fields whose safety cannot be established.

## Acceptance Criteria

With US and Russian input sources installed and the required macOS permissions granted:

1. Typing `ghbdtn ` in a supported field produces `привет ` and selects the Russian input source.
2. Typing `руддщ ` produces `hello ` and selects the US input source.
3. Typing `Ghbdtn`, `GHBDTN`, `Руддщ`, or `РУДДЩ` preserves title or uppercase form after correction.
4. Valid English and Russian words, including `docker`, remain unchanged.
5. Commands, navigation, mouse clicks, focus changes, and app changes cannot cause an earlier word to be modified.
6. No correction is attempted in known terminal or remote-desktop applications or in a field identified as secure or unsafe.
7. Synthetic replacement events are never added back to the captured word buffer.
8. TextEdit and Notes work in manual smoke tests. Safari, Chrome, and Visual Studio Code ordinary text inputs work when Accessibility exposes a safe editable field.
9. The application stores only preferences; it neither stores nor transmits typed text.

## Technical Constraints

- Swift 6 language mode and Swift Package Manager.
- macOS 14.0 deployment target.
- Apple frameworks only: SwiftUI, AppKit, CoreGraphics, ApplicationServices, Carbon, and Foundation.
- No package dependencies, background server, privileged helper, or network entitlement.
- The repository produces a testable Swift package and a local `.app` bundle through a packaging script.

## Architecture

### Application shell

`TwigaSwitcherApp` owns a single `AppController` and renders a SwiftUI `MenuBarExtra`. `AppController` translates permission and monitor state into a small observable menu model. The application is an agent app (`LSUIElement = true`) and does not appear in the Dock.

The menu contains:

- Current state: Active, Paused, or Permissions Required.
- An Enable Automatic Correction toggle.
- Request Required Permissions when a system prompt can still be shown.
- Open Privacy Settings when permissions are missing.
- Quit TwigaSwitcher.

### KeyboardMonitor

`KeyboardMonitor` owns a session-level `CGEventTap`. It observes key-down, modifier-change, and mouse-down events. It normalizes relevant keyboard data into `InputEvent` values and asks `InputPipeline` whether to pass or suppress the original event.

The monitor tags posted events with a fixed private `eventSourceUserData` marker. Events with that marker are passed through without entering the pipeline. If macOS disables the event tap, the monitor re-enables it once; repeated failure changes the app state to disabled rather than spinning.

### WordBuffer

`WordBuffer` stores only the in-progress word and the number of physical key presses that created it. It accepts letters in one script at a time. It clears on:

- Command, Control, or Option-modified input;
- arrows, Escape, Delete across an empty buffer, function keys, or unsupported keys;
- mouse-down;
- workspace application activation;
- application deactivation or monitor restart.

Space, Return, and supported punctuation finish the current word. Mixed-script strings, digits, emoji, dead-key sequences, or characters that cannot be mapped cause the buffer to clear without correction.

### LayoutConverter

`LayoutConverter` is a pure component backed by explicit US-QWERTY/Russian key-position maps. It converts Latin to Cyrillic and Cyrillic to Latin and preserves three recognized case shapes: lowercase, title case, and uppercase. It returns no result for unsupported or mixed-script text.

### LanguageDetector

`LanguageDetector` receives the original word and its converted candidate. Its lexicon dependency has a small protocol so tests can use deterministic accepted-word sets.

The production lexicon combines:

1. A bundled minimal RU/EN dictionary that guarantees the documented demo words and a representative smoke-test vocabulary.
2. `NSSpellChecker` using explicit `ru` and `en_US` language identifiers.
3. A small immutable technical-word allowlist, including `docker`, `swift`, `xcode`, `github`, `json`, `http`, and `ssh`.

A correction is allowed only when all of these are true:

- the original consists entirely of letters from one supported script;
- the original is not accepted in its apparent language and is not allowlisted;
- the converted candidate is accepted in the opposite language;
- the focused-field safety check returns safe.

Any unavailable dictionary, contradictory result, or unknown state produces no correction.

### FocusSafetyGuard

`FocusSafetyGuard` uses Accessibility only to inspect the focused UI element; it does not read or replace its text. It classifies the focus as safe, unsafe, or unknown. Secure text fields, noneditable controls, and unknown focus are skipped.

The active application bundle identifier is checked against built-in exclusions for Apple Terminal, iTerm2, Apple Screen Sharing, Microsoft Remote Desktop, and common VNC clients. This also intentionally disables the prototype for SSH sessions by excluding terminal applications entirely.

### CorrectionEngine

On a terminating event, `CorrectionEngine` obtains a `CorrectionDecision`. When the result is no-change, the original terminating event passes through untouched. When correction is approved:

1. The original terminating event is suppressed.
2. One synthetic Backspace pair is posted for each captured physical key press.
3. The corrected word is posted as Unicode text through `CGEventKeyboardSetUnicodeString`.
4. The original delimiter is posted with its original relevant modifiers.
5. `InputSourceManager` selects the installed Russian or US source matching the correction.
6. The word buffer is cleared.

If posting or input-source selection fails, the buffer is cleared and the app records a non-sensitive diagnostic status. It never retries a text replacement because a retry could duplicate or destroy user text.

### InputSourceManager

`InputSourceManager` queries enabled keyboard sources with Text Input Source Services. It prefers `com.apple.keylayout.US` and `com.apple.keylayout.Russian`, then falls back to an enabled source whose declared languages include `en` or `ru`. Failure to find a suitable source does not undo an already completed text correction; the menu reports that the matching layout is unavailable.

### Permissions

`PermissionManager` checks:

- Accessibility trust with `AXIsProcessTrustedWithOptions`;
- Input Monitoring with `CGPreflightListenEventAccess` and, after an explicit menu action, `CGRequestListenEventAccess`.

The app can open the appropriate Privacy & Security pane. Until both permissions are present, the monitor remains stopped and the menu displays Permissions Required.

## Data Flow

```text
CGEventTap
  → KeyboardMonitor
  → InputEvent
  → WordBuffer
  → word boundary
  → LayoutConverter
  → LanguageDetector + FocusSafetyGuard
  → CorrectionDecision
      ├─ no change: pass delimiter through
      └─ correct: suppress delimiter
                  → post Backspaces + Unicode word + delimiter
                  → select matching input source
```

Application activation, pointer input, and unsafe keyboard actions clear `WordBuffer` independently of the correction path.

## Error Handling and Privacy

- Permission failures are represented in menu state and never crash the app.
- Event-tap creation and disablement failures stop monitoring cleanly.
- Accessibility lookup failures are treated as unsafe.
- Missing input sources are reported without repeated switching attempts.
- Replacement events carry a private marker and are ignored by capture logic.
- Only an in-memory current-word buffer is retained, and it is cleared aggressively.
- Preferences contain only the enabled flag. No captured word, correction history, clipboard data, or application content is logged or persisted.

## Testing Strategy

### Automated tests

- Complete US/Russian layout-map pairs and round trips.
- Lowercase, title-case, and uppercase preservation.
- Rejection of mixed scripts, digits, unsupported characters, and empty input.
- Word accumulation, boundary recognition, Backspace behavior, and every reset condition.
- Conservative correction decisions with deterministic fake lexicons.
- Allowlisted technical words and ambiguous words remain unchanged.
- Unsafe and unknown focused-field states remain unchanged.
- Synthetic event markers bypass processing.
- Correct replacement plans preserve delimiter and physical deletion count.
- Missing input sources and monitor-disable transitions produce stable app states.

System framework calls are placed behind small protocols. Tests exercise the real conversion, buffering, decision, and replacement-plan logic without generating global keyboard input.

### Manual smoke test

Build and launch the generated `.app`, grant Accessibility and Input Monitoring, and verify:

1. Both correction directions and case preservation in TextEdit.
2. Both correction directions in Notes.
3. Ordinary text inputs in Safari and Chrome.
4. An ordinary editor field in Visual Studio Code.
5. No change for `docker`, valid Russian words, keyboard shortcuts, arrow navigation, or mouse focus changes.
6. No correction in Terminal/iTerm or a secure password field.
7. Pause/resume, permission status, and Quit from the menu bar.

## Repository Shape

```text
TwigaSwitcher/
├─ Package.swift
├─ Sources/
│  ├─ TwigaSwitcherCore/
│  │  ├─ Input/
│  │  ├─ Conversion/
│  │  ├─ Detection/
│  │  └─ Correction/
│  └─ TwigaSwitcherApp/
│     ├─ Application/
│     ├─ SystemIntegration/
│     └─ Resources/
├─ Tests/TwigaSwitcherCoreTests/
├─ scripts/build-app.sh
└─ docs/superpowers/
```

Pure decision logic lives in `TwigaSwitcherCore`; macOS APIs and the menu application live in `TwigaSwitcherApp`. The separation keeps the behavior deterministic under tests and confines global-input privileges to the executable target.
