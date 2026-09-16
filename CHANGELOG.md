# Changelog

## Unreleased

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
- Local APK packaging is unverified: Flutter's configured Java path is stale;
  using the installed Java 17 directly reaches Flutter compilation, but
  packaging stops because this checkout lacks `google-services.json`.

Earlier release history is available in [GitHub Releases](https://github.com/agustiarfalahi94/kopi-kompas/releases).
