# Vendored `fluid_glass` 0.6.1 — local deltas

This directory is a copy of the published package `fluid_glass 0.6.1`
(<https://pub.dev/packages/fluid_glass>, by TIANLI0), wired in through
`dependency_overrides` in the project's `pubspec.yaml`. Only `lib/`,
`shaders/`, `pubspec.yaml` and the licence files are copied; upstream's
`doc/`, `example/` and `test/` are dropped.

Upstream has no knob for the blur radius of `LiquidBottomTabs` — the value is
hard-coded inside the widget. The app needs the bottom bar to be exactly as
foggy as the `LiquidButton` next to it, so the copy is patched in place.

Upstream also has no way to hand a `LiquidButton` or a `LiquidBottomTabs` its
own `Highlight`, so either rim is always `Highlight.standard`. The app wants a
softer rim on both, so both widgets gained an optional `highlight` parameter
(null keeps the upstream default).

## Deltas (all under `lib/src/components/`)

| File | Location | Upstream | Here | Why |
| --- | --- | --- | --- | --- |
| `liquid_bottom_tabs.dart` | Panel effect chain (`_LiquidBottomTabsState.build`) | `..blur(8)` | `..blur(2)` | Same Gaussian radius as `LiquidButton`'s `..blur(2)`. |
| `liquid_bottom_tabs.dart` | `_AccentGlassBackdrop.blurRadius` | `8.0` | `2.0` | The accent copy behind the selection pill has to use the same fog level as the panel, or the pill reads as a different kind of glass. |
| `liquid_bottom_tabs.dart` | constructor + panel `DrawBackdrop` | — | `HighlightGetter? highlight`, defaulting to a top-level `_standardRim` tear-off | Lets the app pass `Highlight.standard.copyWith(blurRadius: …)` for the panel's rim. The tear-off, not a per-build closure, keeps the getter identity stable so `DrawBackdrop` does not take the "highlight changed" path every build. |
| `liquid_button.dart` | constructor + `DrawBackdrop` | — | same | Same, for the button's rim. |

Nothing else differs. The lens radii (`lens(24, 24)` on the panel,
`lens(12, 24)` on the button) and the vibrancy pass are untouched: this fork
matches the *blur*, not the refraction. The selection pill's own press
highlight still uses `Highlight.standard` — its alpha is the press progress,
so it is invisible at rest.

## Updating

1. Copy the new upstream `lib/` + `shaders/` + `pubspec.yaml` over this
   directory (bump `version:` in `pubspec.yaml` and this file's title).
2. Re-apply the four edits above; all are marked `PATCH(songquery)` in the
   source.
3. `flutter pub get`, then `flutter test test/glass_library_test.dart` — it
   asserts the vendored copy still has the patches.
