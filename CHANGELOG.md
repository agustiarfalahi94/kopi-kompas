# Changelog

## [0.4.2] — 2026-10-10

### Fixed

- Scoring recovered from Gemini model overload (observed upstream `503`).
  Parsing and scoring now follow the Flash-Lite rolling alias. Full Flash
  repeatedly exhausted the request budget in GitHub live scoring checks;
  Lite passed the same checks. Both model variables remain configurable.
  missing/overloaded/timed-out models trigger bounded discovery of compatible stable
  models in the same family, with up to three generation attempts in total.
- JSON output joins all non-thinking answer parts instead of assuming the
  first part is the answer. Scores record Google's resolved `modelVersion`
  when available, falling back to the requested model if it is absent.
- Removed deprecated sampling parameters from requests for current Gemini
  model compatibility. Quota/authentication errors do not trigger model rotation.
- Unrecorded scoring fields are explicitly `null`, rather than omitted, so
  unknown booleans are distinct from recorded `false`. Existing rubric weights,
  target bands, and historical scores are unchanged.

### Added

- Weekly live parsing/scoring smoke checks in GitHub Actions, also runnable
  manually. These use synthetic coffee data and the deployed Worker; no Gemini
  credential is needed in GitHub.

### Included from develop

- Remembered fields now come from SQLite history, with source markers in the
  form. Score failures offer a working retry button and failure explanation.

### Changed

- Roast Date automatically formats committed input as `YYYY-MM-DD`, inserting
  hyphens after the fourth and sixth digits and limiting input to eight digits.
- Date entry supports compact/ISO paste, cursor and selection editing, and
  backspace across automatic separators. Active keyboard composition is left
  untouched until committed.
- Empty, incomplete, and impossible calendar dates are omitted rather than
  blocking Save or being normalised into another date.
- Clearing an AI-prefilled Roast Date no longer restores the original parsed
  date during Save. Impossible prefilled dates are discarded too.

### Verification

- Regression widget tests exercise the actual shared form used by new/edit
  entries, including leap-year validation and remembered-date preservation.
- Android-device verification is still pending; see
  [device check 37](docs/DEVICE_TESTS.md#roast-date-input).
- The Roast Date APK was built and signature-verified locally on 2026-09-16,
  using the existing ignored Firebase configuration and shared release key.
  GitHub's tag workflow builds the versioned release APKs.

Earlier release history is available in [GitHub Releases](https://github.com/agustiarfalahi94/kopi-kompas/releases).
