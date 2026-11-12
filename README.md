# Complexity Ladder

An Android and Linux desktop app (`Dart` + `Flutter`) for the unified `2D` grid
Complexity Ladder: one orthogonal $n \times n$ grid board, eight physics
switches, clickable connectors and draggable perimeter meeple-tokens, and the
complexity class read directly off the active switch vector (`L` through
`2EXPTIME`). Full switch definitions, lattice structure, and per-rung proof
status are in `DESIGN.md`.

- `ladder_core/` — pure Dart, zero Flutter dependencies: the eight switches and
  class readout, the $n \times n$ grid board and `2×2` folded tiles `A`, legal
  connector taps and meeple slides, the exact solver across open-centre walks
  (`L`, `NL`, `P`), `1`-player constraint logic (`NP`, `PSPACE`), `2`-player
  alternating constraint logic (`EXPTIME`), and folded tile instances
  (`NEXPTIME ·`, `EXPSPACE ·`, `2EXPTIME ·`), plus full-grid procedural board
  synthesis across `4×4`, `5×5`, and `6×6` grids. Run `dart test` to verify all
  rungs and `dart run tool/bench.dart` to benchmark synthesis and solving across
  grid sizes.
- `app/` — Flutter Material 3 app (`org.modelmodel.complexity_ladder`) for
  Android and Linux desktop. Tap any highlighted connector (or drag one of your
  meeples along a connector) to make its move; tap a dashed `2×2` box `A` on
  folded rungs to unfold its sub-grid in place. On `L`, `NL`, and `P`, coupled
  value-`1` perimeter tokens (`threshold E−1`, with locked `★` on goal-adjacent
  connectors) make the board dynamics visually continuous with `NP` and above,
  and on every rung the winning `★` slides into the recessed Goal socket in the
  target cell's centre. Players can toggle between `Green` and `Purple` in the
  app bar, step `undo`/`redo`/`reset`/2-tap `hint`/`new`, and inspect all eight
  physics switches, grid size (`4×4`, `5×5`, `6×6`), seed, proof status, and
  lattice readout in the drawer.

## Switches at a glance

| switch | off / low | on / high |
| --- | --- | --- |
| `thr` | `0` (walk / coupled `E−1` perimeter view) | `2` (inflow weight `>= 2` must stay behind) |
| `open` | open cell centres (walk regime) | closed cell centres (meeples slide on connector endpoints) |
| `directed` | `2-way` connectors | `1-way` arrow connectors |
| `alt` | `∀` off | opponent picks exit from `∀` cells on open walks |
| `once` | each blocker slides once (`✓`) | meeples slide freely |
| `two` | `1` player | `2` players (alternating race to respective goals) |
| `coded` | board drawn flat | `2×2` regions start folded as boxes of tile `A` |
| `cross` | ordinary `4`-way intersection | orthogonal crossing bridge (`N↔S`, `W↔E`) |

## Test & build (Flutter + Dart SDK)

```bash
# 1. Pure-Dart core unit tests & synthesis benchmark
cd ladder_core
dart pub get
dart test
dart run tool/bench.dart

# 2. Flutter widget tests & Linux desktop build
cd ../app
flutter pub get
flutter test
flutter build linux --release

# 3. Android release APK build & ADB install
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The Android release APK is signed with the debug key in
`app/android/app/build.gradle.kts` so `adb install -r` works directly without a
separate keystore (`app/build/app/outputs/flutter-apk/app-release.apk`).

Licence: GPL-3.0 (see `LICENSE`).
